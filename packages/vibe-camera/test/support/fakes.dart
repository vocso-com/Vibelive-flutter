import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vibe_camera/vibe_camera.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A camera that "records" by writing a small file.
class FakeSession implements VibeCaptureSession {
  FakeSession({this.lens = VibeLens.front, this.fps = 120, this.mirrorRecording = false});

  @override
  final VibeLens lens;
  @override
  final int? fps;
  @override
  final bool mirrorRecording;
  bool recording = false;
  double? light;
  bool? torch;
  int stops = 0;
  bool disposed = false;

  @override
  Widget preview() => const ColoredBox(key: ValueKey('fake-preview'), color: Color(0xFF335577));
  @override
  bool get hasTorch => lens == VibeLens.back;
  @override
  bool get isRecording => recording;
  @override
  double get minZoom => 1;
  @override
  double get maxZoom => 8;
  @override
  Future<void> setLight(double v) async => light = v;
  @override
  Future<void> setZoom(double zoom) async {}
  @override
  Future<void> setTorch(bool on) async => torch = on;
  @override
  Future<void> focusAt(Offset point) async {}
  @override
  Future<void> startRecording() async => recording = true;
  @override
  Future<String> stopRecording() async {
    recording = false;
    stops++;
    final f = File('${Directory.systemTemp.path}/vibe_fake_${DateTime.now().microsecondsSinceEpoch}.mp4');
    f.writeAsBytesSync([0, 0, 0, 1]);
    return f.path;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

/// Video work without native code: records what it was asked.
class FakeExporter implements VibeExporter {
  FakeExporter({this.info = const VibeVideoInfo(duration: Duration(seconds: 10), size: Size(720, 1280), fps: 120)});

  final VibeVideoInfo info;
  final jobs = <VibeExportJob>[];
  bool fail = false;

  @override
  Future<VibeVideoInfo> probe(File file) async => info;

  @override
  Future<List<Uint8List>> thumbnails(File file, Duration duration, {int count = 8, Size size = const Size(96, 160)}) async =>
      const [];

  @override
  Future<File> export(VibeExportJob job, {ValueChanged<double>? onProgress}) async {
    jobs.add(job);
    onProgress?.call(0.5);
    if (fail) throw StateError('render failed');
    onProgress?.call(1);
    final f = File('${Directory.systemTemp.path}/vibe_out_${jobs.length}.mp4');
    f.writeAsBytesSync([1]);
    return f;
  }

  @override
  Future<void> cancel() async {}
}

/// Playback without a platform: initialised at once, never really plays.
class FakeVideoPlatform extends VideoPlayerPlatform {
  final _events = <int, StreamController<VideoEvent>>{};
  int _next = 0;

  @override
  Future<void> init() async {}
  @override
  Future<int?> create(DataSource dataSource) async {
    final id = _next++;
    final c = StreamController<VideoEvent>();
    _events[id] = c;
    scheduleMicrotask(() => c.add(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 10),
      size: const Size(720, 1280),
    )));
    return id;
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) => create(options.dataSource);
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async {
    unawaited(_events.remove(playerId)?.close());
  }

  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Widget buildView(int playerId) => const SizedBox.expand();
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox.expand();
}

/// A button that opens the camera and keeps what it hands back.
class Launcher extends StatefulWidget {
  const Launcher({super.key, required this.config, required this.opener});
  final VibeCameraConfig config;
  final VibeSessionOpener opener;

  @override
  State<Launcher> createState() => LauncherState();
}

class LauncherState extends State<Launcher> {
  VibeCameraResult? result;
  bool closed = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async {
          final r = await VibeCamera.open(context, config: widget.config, opener: widget.opener);
          setState(() {
            result = r;
            closed = true;
          });
        },
        child: const Text('open'),
      ),
    ),
  );
}

Future<void> pumpFor(dynamic tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
