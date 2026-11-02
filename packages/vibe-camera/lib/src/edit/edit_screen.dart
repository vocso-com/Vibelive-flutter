import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../config.dart';
import '../core/adjustments.dart';
import '../core/crop.dart';
import '../core/edit.dart';
import '../core/filters.dart';
import '../core/text_overlay.dart';
import '../core/trim.dart';
import '../export/exporter.dart';
import '../strings.dart';
import '../ui/filter_thumb.dart';
import '../ui/text_painting.dart';
import '../ui/theme.dart';
import 'text_editor.dart';
import 'trim_bar.dart';

enum VibeTool { filters, adjust, trim, crop, text }

/// After recording: the clip on a loop with everything the user does shown
/// live — look, light, trim, crop, captions — then Done bakes it all into a
/// new video (or hands back the recording untouched when nothing changed).
class VibeEditScreen extends StatefulWidget {
  const VibeEditScreen({
    super.key,
    required this.file,
    required this.config,
    required this.recordedAt,
    this.fps,
    this.initialFilter,
  });

  final File file;
  final VibeCameraConfig config;
  final DateTime recordedAt;
  final int? fps;
  final VibeFilter? initialFilter;

  @override
  State<VibeEditScreen> createState() => _VibeEditScreenState();
}

class _VibeEditScreenState extends State<VibeEditScreen> {
  late final VibeExporter _exporter = widget.config.exporterOrDefault;
  VibeVideoInfo? _info;
  VideoPlayerController? _player;
  VibeEdit? _edit;
  List<Uint8List> _thumbs = const [];
  VibeTool _tool = VibeTool.filters;
  bool _failed = false;

  // Captions.
  String? _editingId; // open in the text editor
  String? _draggingId;
  bool _overTrash = false;
  final _trashKey = GlobalKey();

  // Saving.
  double? _saving;
  bool _cancelled = false;

  VibeCameraStrings get _s => widget.config.strings;
  Color get _accent => widget.config.accent;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player?.removeListener(_loop);
    _player?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // Reading the file and opening the player are independent: side by
      // side, the clip shows sooner.
      final player = VideoPlayerController.file(widget.file);
      final (info, _) = await (_exporter.probe(widget.file), player.initialize()).wait;
      await player.setLooping(false);
      player.addListener(_loop);
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _info = info;
        _player = player;
        _edit = VibeEdit(
          trim: VibeTrim.full(info.duration, max: widget.config.maxDuration),
          filter: widget.initialFilter ?? VibeFilters.normal,
        );
      });
      unawaited(player.play());
      final thumbs = await _exporter.thumbnails(widget.file, info.duration);
      if (mounted) setState(() => _thumbs = thumbs);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Plays the kept part on a loop.
  void _loop() {
    final p = _player;
    final edit = _edit;
    if (p == null || edit == null || !p.value.isInitialized) return;
    final at = p.value.position;
    if (at >= edit.trim.end || (p.value.isCompleted && !p.value.isPlaying)) {
      p.seekTo(edit.trim.start);
      if (!p.value.isPlaying && _saving == null) p.play();
    } else if (at < edit.trim.start - const Duration(milliseconds: 80)) {
      p.seekTo(edit.trim.start);
    }
    if (_tool == VibeTool.trim && mounted) setState(() {});
  }

  void _update(VibeEdit next) => setState(() => _edit = next);

  Future<bool> _confirmDiscard() async {
    final edit = _edit;
    final info = _info;
    if (edit == null || info == null || edit.isUntouched(info.duration)) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => VibeTheme.wrap(
        _accent,
        AlertDialog(
          title: Text(_s.discardTitle, style: const TextStyle(color: Colors.white, fontSize: 18)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_s.keepEditing, style: const TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_s.discard, style: const TextStyle(color: Color(0xFFFF5A5F), fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
    return ok ?? false;
  }

  Future<void> _done() async {
    final edit = _edit;
    final info = _info;
    if (edit == null || info == null || _saving != null) return;
    final kept = edit.trim.length;
    if (edit.isUntouched(info.duration)) {
      Navigator.of(context).pop(
        VibeCameraResult(
          file: widget.file,
          duration: kept,
          recordedAt: widget.recordedAt,
          size: info.size,
          fps: widget.fps,
          filterId: edit.filter.id,
        ),
      );
      return;
    }
    await _player?.pause();
    setState(() {
      _saving = 0;
      _cancelled = false;
    });
    final job = VibeExportJob(
      source: widget.file,
      edit: edit,
      info: info,
      quality: widget.config.exportQuality,
      maxFps: widget.config.maxOutputFps,
    );
    try {
      final out = await _exporter.export(
        job,
        onProgress: (p) {
          if (mounted && _saving != null) setState(() => _saving = p);
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        VibeCameraResult(
          file: out,
          duration: kept,
          recordedAt: widget.recordedAt,
          size: job.outputSize,
          fps: widget.fps,
          edited: true,
          filterId: edit.filter.id,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = null);
      if (!_cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_s.saveFailed)));
      }
      unawaited(_player?.play());
    }
  }

  Future<void> _cancelSave() async {
    _cancelled = true;
    await _exporter.cancel();
  }

  Future<void> _editText([VibeTextOverlay? existing]) async {
    final edit = _edit;
    if (edit == null) return;
    setState(() => _editingId = existing?.id ?? '__new__');
    final result = await Navigator.of(context).push<VibeTextOverlay?>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        pageBuilder: (_, _, _) => VibeTheme.wrap(
          _accent,
          VibeTextEditor(
            initial: existing ??
                VibeTextOverlay(id: 't${DateTime.now().microsecondsSinceEpoch}', text: ''),
            strings: _s,
            accent: _accent,
          ),
        ),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
    if (!mounted) return;
    setState(() => _editingId = null);
    if (result == null) return; // cancelled: nothing changes
    final texts = [...edit.texts.where((t) => t.id != result.id)];
    if (result.text.trim().isNotEmpty) {
      final at = existing == null ? texts.length : edit.texts.indexWhere((t) => t.id == result.id);
      texts.insert(at.clamp(0, texts.length), result);
    }
    _update(edit.copyWith(texts: texts));
  }

  @override
  Widget build(BuildContext context) {
    final edit = _edit;
    final info = _info;
    final player = _player;
    final ready = edit != null && info != null && player != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (popped, _) async {
        if (popped || _saving != null) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    _TopBar(
                      strings: _s,
                      accent: _accent,
                      canSave: ready && _saving == null,
                      onBack: () async {
                        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
                      },
                      onDone: _done,
                    ),
                    Expanded(
                      child: _failed
                          ? Center(child: Text(_s.cameraFailed, style: const TextStyle(color: Colors.white70)))
                          : !ready
                          ? const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2))
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                              child: _Preview(
                                edit: edit,
                                info: info,
                                player: player,
                                tool: _tool,
                                hiddenId: _editingId,
                                draggingId: _draggingId,
                                onTapText: _editText,
                                onDragText: (id) => setState(() => _draggingId = id),
                                onMoveText: (t, global) {
                                  final trash = _trashKey.currentContext?.findRenderObject() as RenderBox?;
                                  final over = trash != null &&
                                      (trash.localToGlobal(Offset.zero) & trash.size)
                                          .inflate(24)
                                          .contains(global);
                                  if (over != _overTrash) HapticFeedback.selectionClick();
                                  setState(() => _overTrash = over);
                                  _update(edit.copyWith(texts: [for (final x in edit.texts) x.id == t.id ? t : x]));
                                },
                                onDropText: (t) {
                                  final drop = _overTrash;
                                  setState(() {
                                    _draggingId = null;
                                    _overTrash = false;
                                  });
                                  if (drop) {
                                    _update(edit.copyWith(texts: [for (final x in edit.texts) if (x.id != t.id) x]));
                                  }
                                },
                                onPanCrop: (center) => _update(edit.copyWith(cropCenter: center)),
                              ),
                            ),
                    ),
                    if (ready)
                      SizedBox(
                        height: 132,
                        child: _draggingId != null
                            ? Center(
                                child: _Trash(key: _trashKey, hot: _overTrash, label: _s.dragToDelete),
                              )
                            : _ToolPanel(
                                tool: _tool,
                                edit: edit,
                                info: info,
                                player: player,
                                thumbs: _thumbs,
                                config: widget.config,
                                onChanged: (next) {
                                  final trimChanged = next.trim != edit.trim;
                                  _update(next);
                                  if (trimChanged) player.seekTo(next.trim.start);
                                },
                                onAddText: () => _editText(),
                              ),
                      ),
                    if (ready)
                      _ToolBar(
                        tool: _tool,
                        strings: _s,
                        accent: _accent,
                        onPick: (t) => setState(() => _tool = t),
                      ),
                  ],
                ),
                if (_saving != null)
                  _SavingOverlay(
                    progress: _saving!,
                    strings: _s,
                    accent: _accent,
                    onCancel: _cancelSave,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The clip as it will come out: cropped frame, look and light, captions.
class _Preview extends StatefulWidget {
  const _Preview({
    required this.edit,
    required this.info,
    required this.player,
    required this.tool,
    required this.hiddenId,
    required this.draggingId,
    required this.onTapText,
    required this.onDragText,
    required this.onMoveText,
    required this.onDropText,
    required this.onPanCrop,
  });

  final VibeEdit edit;
  final VibeVideoInfo info;
  final VideoPlayerController player;
  final VibeTool tool;
  final String? hiddenId;
  final String? draggingId;
  final ValueChanged<VibeTextOverlay> onTapText;
  final ValueChanged<String?> onDragText;
  final void Function(VibeTextOverlay text, Offset global) onMoveText;
  final ValueChanged<VibeTextOverlay> onDropText;
  final ValueChanged<Offset> onPanCrop;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  /// The caption under the finger, as it moves (kept across rebuilds).
  VibeTextOverlay? _grabbed;

  VibeTextOverlay? _hit(Offset local, Size frame) {
    for (final t in widget.edit.texts.reversed) {
      if (VibeTextPainting.box(t, frame).inflate(12).contains(local)) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.edit;
    final tool = widget.tool;
    final video = widget.info.size;
    final crop = edit.cropRect(video);
    return LayoutBuilder(
      builder: (context, box) {
        final scale = (box.maxWidth / crop.width).clamp(0.0, box.maxHeight / crop.height);
        final frame = Size(crop.width * scale, crop.height * scale);
        return Center(
          child: SizedBox.fromSize(
            size: frame,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final t = _hit(d.localPosition, frame);
                  if (t != null) widget.onTapText(t);
                },
                onPanStart: (d) {
                  _grabbed = _hit(d.localPosition, frame);
                  if (_grabbed != null) widget.onDragText(_grabbed!.id);
                },
                onPanUpdate: (d) {
                  final t = _grabbed;
                  if (t != null) {
                    final moved = t.copyWith(
                      position: t.position + Offset(d.delta.dx / frame.width, d.delta.dy / frame.height),
                    );
                    _grabbed = moved;
                    widget.onMoveText(moved, d.globalPosition);
                  } else if (tool == VibeTool.crop) {
                    // Drag the picture inside the frame.
                    widget.onPanCrop(Offset(
                      (edit.cropCenter.dx - d.delta.dx / scale / video.width).clamp(0.0, 1.0),
                      (edit.cropCenter.dy - d.delta.dy / scale / video.height).clamp(0.0, 1.0),
                    ));
                  }
                },
                onPanEnd: (_) {
                  final t = _grabbed;
                  _grabbed = null;
                  if (t != null) widget.onDropText(t);
                },
                child: Stack(
                  children: [
                    Positioned(
                      left: -crop.left * scale,
                      top: -crop.top * scale,
                      width: video.width * scale,
                      height: video.height * scale,
                      child: ColorFiltered(
                        colorFilter: ColorFilter.matrix(edit.matrix),
                        child: VideoPlayer(widget.player),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(painter: VibeTextLayerPainter(edit.texts, hiddenId: widget.hiddenId)),
                    ),
                    if (tool == VibeTool.crop && edit.aspect != VibeCropAspect.original)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(painter: _GridPainter()),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Rule-of-thirds lines while framing a crop.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(Offset(size.width * i / 3, 0), Offset(size.width * i / 3, size.height), p);
      canvas.drawLine(Offset(0, size.height * i / 3), Offset(size.width, size.height * i / 3), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.strings,
    required this.accent,
    required this.canSave,
    required this.onBack,
    required this.onDone,
  });

  final VibeCameraStrings strings;
  final Color accent;
  final bool canSave;
  final VoidCallback onBack;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
    child: Row(
      children: [
        TextButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.replay_rounded, color: Colors.white, size: 20),
          label: Text(strings.retake, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        const Spacer(),
        FilledButton(
          key: const ValueKey('vibe-done'),
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.white12,
            disabledForegroundColor: Colors.white38,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            shape: const StadiumBorder(),
          ),
          onPressed: canSave ? onDone : null,
          child: Text(strings.done, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
}

class _ToolBar extends StatelessWidget {
  const _ToolBar({required this.tool, required this.strings, required this.accent, required this.onPick});

  final VibeTool tool;
  final VibeCameraStrings strings;
  final Color accent;
  final ValueChanged<VibeTool> onPick;

  @override
  Widget build(BuildContext context) {
    final items = [
      (VibeTool.filters, Icons.auto_awesome_rounded, strings.filters),
      (VibeTool.adjust, Icons.tune_rounded, strings.adjust),
      (VibeTool.trim, Icons.content_cut_rounded, strings.trim),
      (VibeTool.crop, Icons.crop_rounded, strings.crop),
      (VibeTool.text, Icons.title_rounded, strings.text),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      child: Row(
        children: [
          for (final (t, icon, label) in items)
            Expanded(
              child: GestureDetector(
                key: ValueKey('vibe-tool-${t.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(t),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: t == tool ? accent : Colors.white70, size: 22),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t == tool ? Colors.white : Colors.white60,
                          fontSize: 11,
                          fontWeight: t == tool ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({
    required this.tool,
    required this.edit,
    required this.info,
    required this.player,
    required this.thumbs,
    required this.config,
    required this.onChanged,
    required this.onAddText,
  });

  final VibeTool tool;
  final VibeEdit edit;
  final VibeVideoInfo info;
  final VideoPlayerController player;
  final List<Uint8List> thumbs;
  final VibeCameraConfig config;
  final ValueChanged<VibeEdit> onChanged;
  final VoidCallback onAddText;

  VibeCameraStrings get s => config.strings;

  @override
  Widget build(BuildContext context) => switch (tool) {
    VibeTool.filters => _filters(),
    VibeTool.adjust => _adjust(),
    VibeTool.trim => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: VibeTrimBar(
        duration: info.duration,
        trim: edit.trim,
        position: player.value.position,
        thumbs: thumbs,
        accent: config.accent,
        max: config.maxDuration,
        min: config.minDuration,
        onChanged: (t) => onChanged(edit.copyWith(trim: t)),
      ),
    ),
    VibeTool.crop => _crop(),
    VibeTool.text => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            key: const ValueKey('vibe-add-text'),
            style: FilledButton.styleFrom(
              backgroundColor: config.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: const StadiumBorder(),
            ),
            onPressed: onAddText,
            icon: const Icon(Icons.add_rounded),
            label: Text(s.addText, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ),
  };

  Widget _filters() {
    final thumb = thumbs.isEmpty ? null : thumbs.first;
    final looks = config.looks;
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      itemCount: looks.length,
      itemBuilder: (_, i) {
        final f = looks[i];
        final on = f == edit.filter;
        return GestureDetector(
          key: ValueKey('vibe-edit-filter-${f.id}'),
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(edit.copyWith(filter: f));
          },
          child: Container(
            width: 68,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 82,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: on ? config.accent : Colors.transparent, width: 2.5),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: thumb == null
                        ? VibeFilterThumb(filter: f)
                        : ColorFiltered(
                            colorFilter: ColorFilter.matrix(f.matrix),
                            child: Image.memory(thumb, fit: BoxFit.cover, gaplessPlayback: true),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.filterName(f.id, f.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: on ? Colors.white : Colors.white70,
                    fontSize: 11,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _adjust() {
    final a = edit.adjustments;
    Widget row(IconData icon, String label, double value, VibeAdjustments Function(double) next) => Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 8),
        SizedBox(
          width: 84,
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: config.accent,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: value,
              min: -1,
              max: 1,
              onChanged: (v) => onChanged(edit.copyWith(adjustments: next((v * 20).round() / 20))),
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '${(value * 100).round()}',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white60, fontSize: 11, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          row(Icons.wb_sunny_outlined, s.brightness, a.brightness, (v) => a.copyWith(brightness: v)),
          row(Icons.contrast_rounded, s.contrast, a.contrast, (v) => a.copyWith(contrast: v)),
          row(Icons.palette_outlined, s.saturation, a.saturation, (v) => a.copyWith(saturation: v)),
          row(Icons.thermostat_rounded, s.warmth, a.warmth, (v) => a.copyWith(warmth: v)),
        ],
      ),
    );
  }

  Widget _crop() {
    final video = info.size;
    final options = [
      (VibeCropAspect.original, s.cropOriginal),
      (VibeCropAspect.portrait, s.cropPortrait),
      (VibeCropAspect.fourFive, s.cropFourFive),
      (VibeCropAspect.square, s.cropSquare),
    ];
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (aspect, label) in options)
            _AspectButton(
              key: ValueKey('vibe-crop-${aspect.name}'),
              ratio: aspect.ratio ?? (video.height > 0 ? video.width / video.height : 9 / 16),
              label: label,
              selected: edit.aspect == aspect,
              accent: config.accent,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(edit.copyWith(aspect: aspect, cropCenter: const Offset(0.5, 0.5)));
              },
            ),
        ],
      ),
    );
  }
}

/// One crop shape: the frame drawn at its real proportions over its name,
/// always visible on the black panel (not a themed chip that only shows
/// once picked).
class _AspectButton extends StatelessWidget {
  const _AspectButton({
    super.key,
    required this.ratio,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final double ratio;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const box = 40.0;
    final w = ratio >= 1 ? box : box * ratio;
    final h = ratio >= 1 ? box / ratio : box;
    final color = selected ? accent : Colors.white;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 76,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? accent : Colors.white24, width: selected ? 2 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: box,
              height: box,
              child: Center(
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: selected ? 0.25 : 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: color, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Trash extends StatelessWidget {
  const _Trash({super.key, required this.hot, required this.label});
  final bool hot;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: hot ? 64 : 52,
        height: hot ? 64 : 52,
        decoration: BoxDecoration(
          color: hot ? const Color(0xFFE53935) : Colors.white12,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
    ],
  );
}

class _SavingOverlay extends StatelessWidget {
  const _SavingOverlay({
    required this.progress,
    required this.strings,
    required this.accent,
    required this.onCancel,
  });

  final double progress;
  final VibeCameraStrings strings;
  final Color accent;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: progress <= 0 ? null : progress,
                    strokeWidth: 5,
                    color: accent,
                    backgroundColor: Colors.white12,
                  ),
                  Text(
                    '${(progress * 100).round()}%',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(strings.saving, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onCancel,
              child: Text(strings.cancel, style: const TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    ),
  );
}
