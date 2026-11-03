import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/log.dart';
import '../../component/c_toast.dart';
import '../helper/chat_device.dart';

/// Hold-to-record state of the composer: [since] while recording, the
/// whole seconds in [elapsed] (the price line reads them), [drag] for
/// slide-to-cancel. Stops itself at [maxSeconds] and sends.
class VoiceRecording {
  VoiceRecording({required this.maxSeconds, required this.onDone});

  final int maxSeconds;

  /// A finished note: its file and length.
  final void Function(String path, int seconds) onDone;

  final since = ValueNotifier<DateTime?>(null);
  final elapsed = ValueNotifier<int>(0);

  /// Finger travel towards the start edge (cancel at [cancelAt]).
  final drag = ValueNotifier<double>(0);

  static const cancelAt = 90.0;

  Timer? _tick;
  bool _pressing = false;
  bool _starting = false;
  bool _disposed = false;

  bool get recording => since.value != null;

  /// Finger down on the mic.
  Future<void> press() async {
    _pressing = true;
    if (recording || _starting) return;
    _starting = true;
    try {
      final device = ChatDevice.instance;
      if (!await device.micPermission()) {
        CToast.show('chat:composer.mic_denied');
        return;
      }
      // Let go while the permission prompt was up: nothing to record.
      if (!_pressing || _disposed) return;
      await device.startRecording();
      if (_disposed) return;
      if (!_pressing) {
        await device.cancelRecording();
        return;
      }
      unawaited(HapticFeedback.mediumImpact());
      since.value = DateTime.now();
      elapsed.value = 0;
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        final start = since.value;
        if (start == null) return;
        final s = DateTime.now().difference(start).inSeconds;
        if (s != elapsed.value) elapsed.value = s;
        if (s >= maxSeconds) unawaited(release());
      });
    } catch (e) {
      Log.w('ChatVoice', 'record start failed: $e');
      since.value = null;
    } finally {
      _starting = false;
    }
  }

  /// Finger moved: [dx] towards the start edge, positive.
  void moved(double dx) {
    if (!recording) return;
    drag.value = dx < 0 ? 0 : dx;
    if (dx >= cancelAt) unawaited(cancel());
  }

  /// Finger up: sends what was recorded (at least a second).
  Future<void> release() async {
    _pressing = false;
    final start = since.value;
    if (start == null) return;
    _stopTicking();
    final seconds = DateTime.now().difference(start).inSeconds;
    try {
      final path = await ChatDevice.instance.stopRecording();
      if (path == null) return;
      if (seconds < 1) {
        CToast.show('chat:composer.too_short');
        return;
      }
      onDone(path, seconds.clamp(1, maxSeconds));
    } catch (e) {
      Log.w('ChatVoice', 'record stop failed: $e');
    }
  }

  /// Slid away (or the screen went): nothing is sent.
  Future<void> cancel() async {
    _pressing = false;
    if (since.value == null) return;
    _stopTicking();
    unawaited(HapticFeedback.selectionClick());
    try {
      await ChatDevice.instance.cancelRecording();
    } catch (_) {}
  }

  void _stopTicking() {
    _tick?.cancel();
    _tick = null;
    since.value = null;
    drag.value = 0;
  }

  void dispose() {
    _disposed = true;
    if (recording) unawaited(cancel());
    _tick?.cancel();
    since.dispose();
    elapsed.dispose();
    drag.dispose();
  }
}
