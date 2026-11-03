import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A picked photo: where it is and how big (pixels, bytes).
class ChatPickedPhoto {
  const ChatPickedPhoto(this.path, {this.width, this.height, this.bytes = 0});

  final String path;
  final int? width;
  final int? height;
  final int bytes;
}

/// The phone side of the composer (camera / gallery, microphone), behind a
/// seam so widget tests fake it: `ChatDevice.instance = _Fake();`.
abstract class ChatDevice {
  const ChatDevice();

  static ChatDevice instance = const _Device();

  /// Longest edge of a sent photo, and its JPEG quality: a chat photo is
  /// read on a phone, so this keeps uploads small and fast.
  static const maxEdge = 1600.0;
  static const quality = 80;

  /// Null when cancelled.
  Future<ChatPickedPhoto?> pickPhoto({required bool camera});

  /// Asks for the microphone the first time; false when refused.
  Future<bool> micPermission();

  /// Starts a voice note (AAC, mono, 64 kbps: ~8 KB a second, matching
  /// the server's length floor); returns its path.
  Future<String> startRecording();

  /// Stops it: the file, or null when nothing was recorded.
  Future<String?> stopRecording();

  /// Stops and deletes it (slid away to cancel).
  Future<void> cancelRecording();

  Future<void> dispose();
}

class _Device extends ChatDevice {
  const _Device();

  static AudioRecorder? _recorder;
  static AudioRecorder get _mic => _recorder ??= AudioRecorder();

  @override
  Future<ChatPickedPhoto?> pickPhoto({required bool camera}) async {
    final file = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: ChatDevice.maxEdge,
      maxHeight: ChatDevice.maxEdge,
      imageQuality: ChatDevice.quality,
    );
    if (file == null) return null;
    final bytes = await file.length();
    final size = await _size(file.path);
    return ChatPickedPhoto(
      file.path,
      width: size?.$1,
      height: size?.$2,
      bytes: bytes,
    );
  }

  /// JPEG / PNG pixel size read from the header (no full decode).
  static Future<(int, int)?> _size(String path) async {
    try {
      final raf = await File(path).open();
      try {
        final head = await raf.read(64 * 1024);
        return _ImageHeader.size(head);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> micPermission() => _mic.hasPermission();

  @override
  Future<String> startRecording() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/chat_voice');
    await dir.create(recursive: true);
    final path = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _mic.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 22050,
        numChannels: 1,
      ),
      path: path,
    );
    return path;
  }

  @override
  Future<String?> stopRecording() => _mic.stop();

  @override
  Future<void> cancelRecording() => _mic.cancel();

  @override
  Future<void> dispose() async {
    final r = _recorder;
    _recorder = null;
    await r?.dispose();
  }
}

/// Pixel size from the first bytes of a JPEG or PNG.
abstract final class _ImageHeader {
  static (int, int)? size(List<int> b) {
    if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50) {
      int be(int i) =>
          (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
      return (be(16), be(20));
    }
    if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) return null;
      final marker = b[i + 1];
      final len = (b[i + 2] << 8) | b[i + 3];
      final sof =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (sof) {
        final h = (b[i + 5] << 8) | b[i + 6];
        final w = (b[i + 7] << 8) | b[i + 8];
        return (w, h);
      }
      i += 2 + len;
    }
    return null;
  }
}
