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
  VibeCaptureSession? _session;
  _Status _status = _Status.opening;
  late VibeLens _lens = widget.config.lens;
  int _filter = 0;
  double _light = 0;
  bool _showLight = false;
  bool _torch = false;
  double _zoom = 1;
  double _zoomAtStart = 1;
  double _swipe = 0;
  DateTime? _recordingSince;
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

  List<VibeFilter> get _filters => widget.config.looks;
  VibeFilter get _look => _filters[_filter];
  bool get _recording => _recordingSince != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flashTimer?.cancel();
    _progress.dispose();
    _seconds.dispose();
    _session?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera belongs to whoever is in front: let go when we are not.
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (_recording) _stop();
      final s = _session;
      _session = null;
      s?.dispose();
    } else if (state == AppLifecycleState.resumed && _session == null) {
      _open();
    }
  }

  Future<void> _open() async {
    setState(() => _status = _Status.opening);
    final open = widget.opener ?? CameraSession.open;
    try {
      final session = await open(
        lens: _lens,
        preferredFps: widget.config.preferredFps,
        enableAudio: widget.config.enableAudio,
      );
      if (!mounted) {
        await session.dispose();
        return;
      }
      _session = session;
      _lens = session.lens;
      _zoom = session.minZoom;
      if (_light != 0) unawaited(session.setLight(_light));
      setState(() => _status = _Status.ready);
    } on VibeCameraDenied {
      if (mounted) setState(() => _status = _Status.denied);
    } catch (_) {
      if (mounted) setState(() => _status = _Status.failed);
    }
  }

  Future<void> _flip() async {
    if (_recording || _busy) return;
    HapticFeedback.selectionClick();
    final old = _session;
    _session = null;
    _torch = false;
    _lens = _lens == VibeLens.front ? VibeLens.back : VibeLens.front;
    setState(() => _status = _Status.opening);
    await old?.dispose();
    await _open();
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
    if (session == null || _busy) return;
    _busy = true;
    try {
      HapticFeedback.mediumImpact();
      await session.startRecording();
      _recordingSince = DateTime.now();
      _showLight = false;
      _seconds.value = 0;
      _progress.forward(from: 0);
      if (mounted) setState(() {});
    } catch (_) {
      _say(widget.config.strings.cameraFailed);
    } finally {
      _busy = false;
    }
  }

  Future<void> _stop() async {
    final session = _session;
    final since = _recordingSince;
    if (session == null || since == null || _busy) return;
    _busy = true;
    _progress.stop();
    // The ring's own clock: the same as the wall clock, and capped at the limit.
    final elapsed = widget.config.maxDuration * _progress.value;
    String path;
    try {
      path = await session.stopRecording();
    } catch (_) {
      _recordingSince = null;
      _busy = false;
      if (mounted) setState(() {});
      return;
    }
    _recordingSince = null;
    _busy = false;
    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() {});
    final file = File(path);
    if (elapsed < widget.config.minDuration) {
      _say(widget.config.strings.tooShort);
      unawaited(file.delete().catchError((Object _) => file));
      return;
    }
    if (!widget.config.edit) {
      Navigator.of(context).pop(
        VibeCameraResult(
          file: file,
          duration: elapsed,
          recordedAt: since,
          fps: session.fps,
          filterId: _look.id,
        ),
      );
      return;
    }
    final result = await Navigator.of(context).push<VibeCameraResult>(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => VibeTheme.wrap(
          widget.config.accent,
          VibeEditScreen(
            file: file,
            config: widget.config,
            recordedAt: since,
            fps: session.fps,
            initialFilter: _look,
          ),
        ),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result);
    } else {
      // Retake: the recording is not needed any more.
      unawaited(file.delete().catchError((Object _) => file));
    }
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
                  session.focusAt(Offset(d.localPosition.dx / box.width, d.localPosition.dy / box.height));
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
                      session.setZoom(z);
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
                onRetry: _open,
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
                          session.setTorch(_torch);
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
                      session.setLight(v);
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
                      RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _progress,
                          builder: (_, _) => _RecordButton(
                          recording: _recording,
                          progress: _progress.value,
                          accent: accent,
                            enabled: _status == _Status.ready,
                            onTap: _toggleRecord,
                          ),
                        ),
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
    required this.onTap,
  });

  final bool recording;
  final double progress;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('vibe-record'),
    onTap: enabled ? onTap : null,
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
