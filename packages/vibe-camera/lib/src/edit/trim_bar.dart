
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/trim.dart';

/// The clip as a strip of frames with two handles: the part kept is bright,
/// the rest dimmed; a line shows where playback is. The kept part is never
/// shorter than [min] nor longer than [max].
class VibeTrimBar extends StatelessWidget {
  const VibeTrimBar({
    super.key,
    required this.duration,
    required this.trim,
    required this.position,
    required this.thumbs,
    required this.accent,
    required this.onChanged,
    this.min = const Duration(seconds: 1),
    this.max,
    this.mirror = false,
  });

  final Duration duration;
  final VibeTrim trim;
  final Duration position;
  final List<Uint8List> thumbs;

  /// Each frame flipped left-right, like the editor's preview.
  final bool mirror;
  final Color accent;
  final ValueChanged<VibeTrim> onChanged;
  final Duration min;
  final Duration? max;

  static const _handle = 16.0;

  @override
  Widget build(BuildContext context) {
    final total = duration.inMicroseconds <= 0 ? 1 : duration.inMicroseconds;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_fmt(trim.start)}  –  ${_fmt(trim.end)}   (${_fmt(trim.length)})',
          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 58,
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth - _handle * 2;
              double x(Duration d) => _handle + w * d.inMicroseconds / total;
              Duration at(double dx) => Duration(
                microseconds: (((dx - _handle) / w).clamp(0.0, 1.0) * total).round(),
              );
              final left = x(trim.start), right = x(trim.end);
              // A handle stops at the other one (and at the longest clip
              // allowed); it never pushes it along.
              void move({Duration? start, Duration? end}) {
                var s = start ?? trim.start;
                var e = end ?? trim.end;
                if (start != null) {
                  if (s > trim.end - min) s = trim.end - min;
                  if (max != null && trim.end - s > max!) s = trim.end - max!;
                }
                if (end != null) {
                  if (e < trim.start + min) e = trim.start + min;
                  if (max != null && e - trim.start > max!) e = trim.start + max!;
                }
                final next = VibeTrim.clamp(
                  start: s,
                  end: e,
                  duration: duration,
                  min: min,
                  max: max,
                );
                if (next != trim) {
                  HapticFeedback.selectionClick();
                  onChanged(next);
                }
              }

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // The frames.
                  Positioned(
                    left: _handle,
                    right: _handle,
                    top: 4,
                    bottom: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: thumbs.isEmpty
                          ? const ColoredBox(color: Colors.white10)
                          : Row(
                              children: [
                                for (final t in thumbs)
                                  Expanded(
                                    child: Transform.flip(
                                      flipX: mirror,
                                      child: Image.memory(t, fit: BoxFit.cover, gaplessPlayback: true, height: double.infinity),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                  // What is cut away.
                  Positioned(left: _handle, width: (left - _handle).clamp(0.0, w), top: 4, bottom: 4, child: const ColoredBox(color: Color(0xAA000000))),
                  Positioned(left: right, right: _handle, top: 4, bottom: 4, child: const ColoredBox(color: Color(0xAA000000))),
                  // The kept window.
                  Positioned(
                    left: left - _handle,
                    width: right - left + _handle * 2,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.symmetric(horizontal: BorderSide(color: accent, width: 4)),
                        ),
                      ),
                    ),
                  ),
                  // Playback.
                  if (position >= trim.start && position <= trim.end)
                    Positioned(
                      left: x(position) - 1,
                      top: 0,
                      bottom: 0,
                      child: const IgnorePointer(child: SizedBox(width: 2, child: ColoredBox(color: Colors.white))),
                    ),
                  _Handle(
                    key: const ValueKey('vibe-trim-start'),
                    left: left - _handle,
                    width: _handle,
                    accent: accent,
                    onDrag: (dx) => move(start: at(x(trim.start) + dx)),
                  ),
                  _Handle(
                    key: const ValueKey('vibe-trim-end'),
                    left: right,
                    width: _handle,
                    accent: accent,
                    onDrag: (dx) => move(end: at(x(trim.end) + dx)),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static String _fmt(Duration d) {
    final tenths = (d.inMilliseconds / 100).round();
    return '${tenths ~/ 10}.${tenths % 10}s';
  }
}

class _Handle extends StatelessWidget {
  const _Handle({super.key, required this.left, required this.width, required this.accent, required this.onDrag});

  final double left;
  final double width;
  final Color accent;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => Positioned(
    left: left,
    width: width,
    top: 0,
    bottom: 0,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      child: DecoratedBox(
        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(5)),
        child: const Center(
          child: SizedBox(width: 3, height: 18, child: ColoredBox(color: Colors.white)),
        ),
      ),
    ),
  );
}
