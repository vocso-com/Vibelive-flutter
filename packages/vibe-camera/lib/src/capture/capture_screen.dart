import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../core/filters.dart';
import '../edit/edit_screen.dart';
import '../strings.dart';
import '../ui/filter_thumb.dart';
import '../ui/theme.dart';
import 'camera_lane.dart';
import 'camera_session.dart';

/// The camera: live preview with the chosen look, light, zoom, torch and
/// lens, and a record button that stops at [VibeCameraConfig.maxDuration].
/// Then the editor (or the clip as it is, when editing is off).
class VibeCaptureScreen extends StatefulWidget {
  const VibeCaptureScreen({super.key, required this.config, this.opener});

  final VibeCameraConfig config;

  /// Opens the camera ([CameraSession.open] when null; tests pass a fake).
  final VibeSessionOpener? opener;

  @override
  State<VibeCaptureScreen> createState() => _VibeCaptureScreenState();
}

enum _Status { opening, ready, denied, failed }

class _VibeCaptureScreenState extends State<VibeCaptureScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // How long each camera call may take before the screen gives up on it and
  // starts the camera afresh. Generous: a slow phone answers well inside
  // them. An open includes the first-time permission prompts.
  static const _openTimeout = Duration(seconds: 20);
  static const _startTimeout = Duration(seconds: 6);
  static const _stopTimeout = Duration(seconds: 10);
  static const _releaseTimeout = Duration(seconds: 5);

  VibeCaptureSession? _session;
  _Status _status = _Status.opening;

  /// An open for this screen is on its way.
  bool _opening = false;

  /// Moves on whenever the camera wanted changes (flipped, let go): an open
  /// asked for before it is closed again when it arrives.
  int _gen = 0;

  /// The app is on screen: not hidden or paused.
  bool _foreground = true;

  /// The editor is on top: the camera is not needed until a retake.
  bool _away = false;

  /// The gallery picker is open.
  bool _picking = false;

  late VibeLens _lens = widget.config.lens;
  int _filter = 0;
  double _light = 0;
  bool _showLight = false;
  bool _torch = false;
  double _zoom = 1;
  double _zoomAtStart = 1;
  double _swipe = 0;
  DateTime? _recordingSince;

  /// A start or stop is under way: the record button waits for it.
  bool _busy = false;
  String? _flash; // a message shown for a moment (filter name, "too short")
  Timer? _flashTimer;

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.config.maxDuration,
  )
    ..addListener(() {
      // The timer text changes once a second, not every frame.
      final s = (widget.config.maxDuration * _progress.value).inSeconds;
      if (s != _seconds.value) _seconds.value = s;
    })
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _stop();
    });
  final _seconds = ValueNotifier<int>(0);

  VibeCameraLane get _lane => VibeCameraLane.shared;
  List<VibeFilter> get _filters => widget.config.looks;
  VibeFilter get _look => _filters[_filter];
  bool get _recording => _recordingSince != null;
  bool get _wanted => mounted && _foreground && !_away;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = WidgetsBinding.instance.lifecycleState;
    _foreground = now != AppLifecycleState.hidden &&
        now != AppLifecycleState.paused &&
        now != AppLifecycleState.detached;
    _settle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flashTimer?.cancel();
    _progress.dispose();
    _seconds.dispose();
    _gen++;
    final s = _session;
    _session = null;
    // Closed mid-recording: the recording is stopped (and dropped) before
    // the camera closes, in turn with anything still under way.
    if (s != null) unawaited(_letGo(s));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only leaving the app lets the camera go. "Inactive" is a permission
    // prompt, the notification shade or Control Centre: the camera stays and
    // a recording keeps going. (Letting go there opened a second camera
    // behind every permission prompt, and closed the camera under a stop.)
    if (state == AppLifecycleState.inactive) return;
    final front = state == AppLifecycleState.resumed;
    if (front == _foreground) return;
    _foreground = front;
    // Back from outside the app, perhaps from Settings with access now
    // allowed: try again even after a refusal.
    _settle(retry: front);
  }

  /// Brings the camera in line with what the screen needs right now: open
  /// when wanted, a recording finished and the camera let go when not. Runs
  /// after every change; a start or stop under way calls it when it ends.
  void _settle({bool retry = false}) {
    if (!mounted || _busy) return;
    if (_wanted) {
      final refused = _status == _Status.denied || _status == _Status.failed;
      if (_session == null && !_opening && (retry || !refused)) _open();
    } else if (_recording) {
      // Left the app mid-recording: the clip is kept, the editor waits.
      unawaited(_stop());
    } else if (_session != null) {
      unawaited(_release());
    }
  }

  void _open() {
    _opening = true;
    if (_status != _Status.opening) setState(() => _status = _Status.opening);
    unawaited(_openFor(_gen));
  }

  Future<void> _openFor(int gen) async {
    VibeCaptureSession? session;
    Object? error;
    try {
      session = await _openSession(gen);
    } catch (e) {
      error = e;
      _log('open failed: $e');
    }
    _opening = false;
    if (session != null && !_take(session, gen)) unawaited(_letGo(session));
    if (!mounted) return;
    if (session == null && gen == _gen && _wanted) {
      setState(() => _status = error is VibeCameraDenied ? _Status.denied : _Status.failed);
      return;
    }
    // Flipped or left while it opened: open what is wanted now.
    _settle();
  }

  /// One camera, in the lane. One that answers after the timeout (a
  /// permission prompt left up a long time) is still used if the screen is
  /// waiting for exactly that camera, and closed otherwise, unless a newer
  /// camera has replaced it already.
  Future<VibeCaptureSession> _openSession(int gen) {
    final open = widget.opener ?? CameraSession.open;
    final lane = _lane;
    final ticket = lane.beginOpen();
    return lane.run(() {
      final pending = open(
        lens: _lens,
        preferredFps: widget.config.preferredFps,
        enableAudio: widget.config.enableAudio,
      );
      return pending.timeout(_openTimeout, onTimeout: () {
        unawaited(pending.then((late) {
          if (_take(late, gen)) return;
          if (lane.isNewestOpen(ticket)) unawaited(_letGo(late));
        }, onError: (Object _) {}));
        throw TimeoutException('The camera did not open', _openTimeout);
      });
    });
  }

  /// Keeps [session] when it is still the camera this screen wants.
  bool _take(VibeCaptureSession session, int gen) {
    if (gen != _gen || !_wanted || _session != null || _opening) return false;
    _session = session;
    _lens = session.lens;
    _zoom = session.minZoom;
    _torch = false;
    if (_light != 0) _quiet(session.setLight(_light));
    setState(() => _status = _Status.ready);
    return true;
  }

  /// Gives the camera back: the app left, the editor opened, the lens
  /// changed, or a call never answered (a fresh camera clears a wedged one).
  Future<void> _release({bool stopFirst = true}) async {
    _gen++;
    final s = _session;
    _session = null;
    _torch = false;
    if (mounted && _status != _Status.opening) setState(() => _status = _Status.opening);
    if (s != null) await _letGo(s, stopFirst: stopFirst);
  }

  /// Closes [s] in the lane, after whatever it is doing now. Still
  /// recording: that recording is stopped first, and dropped (not after a
  /// stop that just failed: asking again would only wait again).
  Future<void> _letGo(VibeCaptureSession s, {bool stopFirst = true}) => _lane
      .run<void>(() async {
        if (stopFirst && s.isRecording) {
          try {
            _drop(File(await s.stopRecording().timeout(_stopTimeout)));
          } catch (_) {
            // Closing the camera ends it anyway.
          }
        }
        await s.dispose().timeout(_releaseTimeout);
      })
      .catchError((Object e) => _log('release failed: $e'));

  static void _log(String message) => debugPrint('VibeCamera: $message');

  /// A camera setting changed in passing: nothing waits on it, and one that
  /// fails (the camera closing under it) changes nothing.
  static void _quiet(Future<void> f) => unawaited(f.catchError((Object _) {}));

  static void _drop(File file) => unawaited(file.delete().catchError((Object _) => file));

  Future<void> _flip() async {
    if (_recording || _busy || _picking) return;
    HapticFeedback.selectionClick();
    _lens = _lens == VibeLens.front ? VibeLens.back : VibeLens.front;
    // The open waits in the lane until the old camera is closed.
    await _release();
    _settle();
  }

  void _say(String text) {
    _flashTimer?.cancel();
    setState(() => _flash = text);
    _flashTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _pick(int index) {
    if (index == _filter || index < 0 || index >= _filters.length) return;
    HapticFeedback.selectionClick();
    setState(() => _filter = index);
    final f = _look;
    _say(widget.config.strings.filterName(f.id, f.name));
  }

  Future<void> _toggleRecord() async {
    if (_recording) return _stop();
    final session = _session;
    if (session == null || _busy || _picking || _status != _Status.ready) return;
    setState(() => _busy = true);
    try {
      HapticFeedback.mediumImpact();
      await _lane.run(session.startRecording, timeout: _startTimeout);
      if (!mounted) return;
      _recordingSince = DateTime.now();
      _showLight = false;
      _seconds.value = 0;
      _progress.forward(from: 0);
    } catch (e) {
      // Refused, or never answered: the button must not stay dead, and the
      // camera may be wedged, so it is opened afresh.
      _log('start failed: $e');
      if (!mounted) return;
      _say(widget.config.strings.cameraFailed);
      await _release();
    } finally {
      _busy = false;
      if (mounted) {
        setState(() {});
        // Left the app while it started: stop again. Let go: reopen.
        _settle();
      }
    }
  }

  Future<void> _stop() async {
    final session = _session;
    final since = _recordingSince;
    if (session == null || since == null || _busy) return;
    setState(() => _busy = true);
    _progress.stop();
    // The ring's own clock: the same as the wall clock, and capped at the limit.
    final elapsed = widget.config.maxDuration * _progress.value;
    String? path;
    try {
      path = await _lane.run(session.stopRecording, timeout: _stopTimeout);
    } catch (e) {
      _log('stop failed: $e');
    }
    _recordingSince = null;
    if (path == null && mounted) {
      // Nothing came back, and the camera may be wedged: a fresh one.
      _say(widget.config.strings.recordFailed);
      await _release(stopFirst: false);
    }
    _busy = false;
    if (!mounted) {
      if (path != null) _drop(File(path));
      return;
    }
    setState(() {});
    if (path == null) return _settle();
    HapticFeedback.lightImpact();
    await _useClip(File(path), elapsed: elapsed, since: since, fps: session.fps, mirror: session.mirrorRecording);
  }

  /// The finished recording: too short, unusable, straight back, or into
  /// the editor.
  Future<void> _useClip(
    File file, {
    required Duration elapsed,
    required DateTime since,
    required int? fps,
    required bool mirror,
  }) async {
    final config = widget.config;
    if (elapsed < config.minDuration) {
      _say(config.strings.tooShort);
      _drop(file);
      return _settle();
    }
    // A recording that failed on the way can still come back with a path:
    // to a file that is missing or empty.
    if (!_hasVideo(file)) {
      _drop(file);
      _say(config.strings.recordFailed);
      await _release();
      return _settle();
    }
    if (!config.edit) {
      // Out of the app (it stopped because the app left): the camera goes
      // now. Closing the screen would wait for the app to come back, as no
      // frames (so no route transitions) run in the background.
      _settle();
      Navigator.of(context).pop(
        VibeCameraResult(file: file, duration: elapsed, recordedAt: since, fps: fps, filterId: _look.id),
      );
      return;
    }
    final result = await _edit(
      VibeEditScreen(
        file: file,
        config: config,
        recordedAt: since,
        fps: fps,
        initialFilter: _look,
        // Android's front camera: the file is the preview's mirror image.
        mirror: mirror,
      ),
    );
    // Retake: the recording is not needed any more.
    if (result == null) _drop(file);
  }

  /// One stat call: quick enough to make on the spot.
  static bool _hasVideo(File file) {
    try {
      return file.statSync().size > 0;
    } catch (_) {
      return false;
    }
  }

  /// Opens the editor with the camera let go (it plays and renders video;
  /// no camera is needed under it), then hands its clip back, or opens the
  /// camera again for a retake. Null: retake.
  Future<VibeCameraResult?> _edit(VibeEditScreen editor) async {
    _away = true;
    unawaited(_release());
    final result = await Navigator.of(context).push<VibeCameraResult>(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => VibeTheme.wrap(widget.config.accent, editor),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
    if (!mounted) return result;
    if (result != null) {
      Navigator.of(context).pop(result);
      return result;
    }
    _away = false;
    _settle();
    return null;
  }

  /// A video from the phone's gallery, through the same editor (trimmed to
  /// the limit there), never flipped. Only offered when the app passed a
  /// picker.
  Future<void> _fromGallery() async {
    final pick = widget.config.pickFromGallery;
    if (pick == null || _recording || _busy || _picking) return;
    _picking = true;
    File? file;
    try {
      file = await pick();
    } catch (_) {
      file = null;
    } finally {
      _picking = false;
    }
    if (file == null || !mounted) return;
    await _edit(
      VibeEditScreen(
        file: file,
        config: widget.config,
        recordedAt: DateTime.now(),
        initialFilter: _look,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.config.strings;
    final accent = widget.config.accent;
    final session = _session;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_status == _Status.ready && session != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final box = context.size;
                  if (box == null) return;
                  setState(() => _showLight = false);
                  _quiet(session.focusAt(Offset(d.localPosition.dx / box.width, d.localPosition.dy / box.height)));
                },
                onScaleStart: (_) {
                  _zoomAtStart = _zoom;
                  _swipe = 0;
                },
                onScaleUpdate: (d) {
                  if (d.pointerCount >= 2) {
                    final z = (_zoomAtStart * d.scale)
                        .clamp(session.minZoom, math.min(session.maxZoom, 10.0))
                        .toDouble();
                    if ((z - _zoom).abs() > 0.01) {
                      _zoom = z;
                      _quiet(session.setZoom(z));
                    }
                  } else {
                    _swipe += d.focalPointDelta.dx;
                  }
                },
                onScaleEnd: (d) {
                  if (d.pointerCount > 0 || _swipe.abs() < 60) return;
                  _pick(_filter + (_swipe < 0 ? 1 : -1));
                },
                // Its own layer: the ring and timer repainting over it never
                // redraw the camera picture.
                child: RepaintBoundary(
                  child: ColorFiltered(
                    colorFilter: ColorFilter.matrix(_look.matrix),
                    child: session.preview(),
                  ),
                ),
              )
            else
              _CameraState(
                status: _status,
                strings: strings,
                accent: accent,
                onRetry: () => _settle(retry: true),
                onSettings: widget.config.onOpenSettings,
              ),
            // Top: close, frame rate, torch, flip.
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    _RoundButton(
                      icon: Icons.close_rounded,
                      label: strings.close,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const Spacer(),
                    if (session != null && session.hasTorch) ...[
                      const SizedBox(width: 8),
                      _RoundButton(
                        icon: _torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                        label: strings.flash,
                        active: _torch,
                        onTap: () {
                          setState(() => _torch = !_torch);
                          _quiet(session.setTorch(_torch));
                        },
                      ),
                    ],
                    if (!_recording) ...[
                      const SizedBox(width: 8),
                      _RoundButton(
                        icon: Icons.wb_sunny_rounded,
                        label: strings.light,
                        active: _showLight || _light != 0,
                        onTap: () => setState(() => _showLight = !_showLight),
                      ),
                      const SizedBox(width: 8),
                      _RoundButton(
                        icon: Icons.flip_camera_ios_rounded,
                        label: strings.flip,
                        onTap: _flip,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Light: the sensor's exposure, so the clip itself is brighter.
            if (_showLight && session != null)
              Positioned(
                right: 6,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _LightSlider(
                    value: _light,
                    accent: accent,
                    onChanged: (v) {
                      setState(() => _light = v);
                      _quiet(session.setLight(v));
                    },
                  ),
                ),
              ),
            if (_flash != null)
              Center(
                child: IgnorePointer(
                  child: Text(
                    _flash!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
                    ),
                  ),
                ),
              ),
            // Bottom: looks, timer, record.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ValueListenableBuilder<int>(
                        valueListenable: _seconds,
                        builder: (_, _, _) => _recording
                            ? _Chip(
                                text: '${_clock(Duration(seconds: _seconds.value))}'
                                    ' / ${_clock(widget.config.maxDuration)}',
                                color: const Color(0xCCE53935),
                              )
                            : Text(
                                strings.holdToRecord,
                                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                      ),
                      const SizedBox(height: 10),
                      if (!_recording)
                        SizedBox(
                          height: 74,
                          child: _FilterStrip(
                            filters: _filters,
                            selected: _filter,
                            accent: accent,
                            strings: widget.config.strings,
                            onPick: _pick,
                          ),
                        )
                      else
                        const SizedBox(height: 74),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Gallery on the left, a same-size gap on the right
                          // so the record button stays centred.
                          SizedBox(
                            width: 64,
                            child: widget.config.pickFromGallery != null &&
                                    !_recording
                                ? _GalleryButton(
                                    label: strings.gallery,
                                    onTap: _fromGallery,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 24),
                          RepaintBoundary(
                            child: AnimatedBuilder(
                              animation: _progress,
                              builder: (_, _) => _RecordButton(
                                recording: _recording,
                                progress: _progress.value,
                                accent: accent,
                                // Waits while a start or stop is under way;
                                // dimmed while there is no camera to use.
                                enabled: session != null && _status == _Status.ready && !_busy && !_picking,
                                ready: session != null && _status == _Status.ready,
                                onTap: _toggleRecord,
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          const SizedBox(width: 64),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Gallery": pick a video from the phone instead of recording.
class _GalleryButton extends StatelessWidget {
  const _GalleryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      key: const ValueKey('vibe-camera-gallery'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white70, width: 1.5),
            ),
            child: const Icon(
              Icons.photo_library_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

String _clock(Duration d) {
  final s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class _CameraState extends StatelessWidget {
  const _CameraState({
    required this.status,
    required this.strings,
    required this.accent,
    required this.onRetry,
    this.onSettings,
  });

  final _Status status;
  final VibeCameraStrings strings;
  final Color accent;
  final VoidCallback onRetry;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    if (status == _Status.opening) {
      return const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2));
    }
    final denied = status == _Status.denied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(denied ? Icons.no_photography_rounded : Icons.videocam_off_rounded, color: Colors.white54, size: 44),
            const SizedBox(height: 14),
            Text(
              denied ? strings.cameraDenied : strings.cameraFailed,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: const StadiumBorder(),
              ),
              onPressed: denied && onSettings != null ? onSettings : onRetry,
              child: Text(denied && onSettings != null ? strings.openSettings : strings.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.black38,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: active ? Colors.black : Colors.white, size: 22),
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.color = Colors.black38});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.3),
    ),
  );
}

class _LightSlider extends StatelessWidget {
  const _LightSlider({required this.value, required this.accent, required this.onChanged});
  final double value;
  final Color accent;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 220,
    width: 44,
    decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(22)),
    child: Column(
      children: [
        const SizedBox(height: 8),
        const Icon(Icons.wb_sunny_rounded, color: Colors.white, size: 18),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: accent,
                inactiveTrackColor: Colors.white30,
                thumbColor: Colors.white,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(value: value, min: -1, max: 1, onChanged: onChanged),
            ),
          ),
        ),
        const Icon(Icons.wb_sunny_outlined, color: Colors.white70, size: 14),
        const SizedBox(height: 8),
      ],
    ),
  );
}

/// The looks, each a swatch drawn through its own matrix.
class _FilterStrip extends StatefulWidget {
  const _FilterStrip({
    required this.filters,
    required this.selected,
    required this.accent,
    required this.strings,
    required this.onPick,
  });

  final List<VibeFilter> filters;
  final int selected;
  final Color accent;
  final VibeCameraStrings strings;
  final ValueChanged<int> onPick;

  @override
  State<_FilterStrip> createState() => _FilterStripState();
}

class _FilterStripState extends State<_FilterStrip> {
  final _scroll = ScrollController();
  static const _item = 62.0;

  @override
  void didUpdateWidget(_FilterStrip old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected && _scroll.hasClients) {
      final target = (widget.selected * _item) - (_scroll.position.viewportDimension - _item) / 2;
      _scroll.animateTo(
        target.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: _scroll,
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    itemCount: widget.filters.length,
    itemExtent: _item,
    itemBuilder: (_, i) {
      final f = widget.filters[i];
      final on = i == widget.selected;
      return GestureDetector(
        key: ValueKey('vibe-filter-${f.id}'),
        onTap: () => widget.onPick(i),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 48,
              height: 48,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: on ? widget.accent : Colors.white38, width: on ? 2.5 : 1.5),
              ),
              child: ClipOval(child: VibeFilterThumb(filter: f)),
            ),
            const SizedBox(height: 5),
            Text(
              widget.strings.filterName(f.id, f.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: on ? Colors.white : Colors.white70,
                fontSize: 10.5,
                fontWeight: on ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// White ring, accent core; recording: the core turns into a red square and
/// the ring fills as the clip runs towards its limit.
class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.recording,
    required this.progress,
    required this.accent,
    required this.enabled,
    required this.ready,
    required this.onTap,
  });

  final bool recording;
  final double progress;
  final Color accent;
  final bool enabled;
  final bool ready;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('vibe-record'),
    behavior: HitTestBehavior.opaque,
    onTap: enabled ? onTap : null,
    child: AnimatedOpacity(
      opacity: ready ? 1 : 0.45,
      duration: const Duration(milliseconds: 160),
      child: SizedBox(
        width: 76,
        height: 76,
        child: CustomPaint(
          painter: _RingPainter(progress: recording ? progress : 0, accent: accent),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: recording ? 28 : 58,
              height: recording ? 28 : 58,
              decoration: BoxDecoration(
                color: recording ? const Color(0xFFE53935) : accent,
                borderRadius: BorderRadius.circular(recording ? 8 : 29),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.accent});
  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.white,
    );
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.accent != accent;
}
