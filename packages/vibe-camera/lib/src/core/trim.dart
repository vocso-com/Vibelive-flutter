import 'package:flutter/foundation.dart';

/// The part of a clip kept: [start]…[end].
@immutable
class VibeTrim {
  const VibeTrim(this.start, this.end);

  final Duration start;
  final Duration end;

  Duration get length => end - start;

  /// The whole [duration], capped at [max] from the start.
  factory VibeTrim.full(Duration duration, {Duration? max}) =>
      VibeTrim(Duration.zero, max != null && duration > max ? max : duration);

  /// [start]/[end] made valid for a [duration]-long clip: inside it, in order,
  /// at least [min] apart (when the clip allows) and at most [max].
  static VibeTrim clamp({
    required Duration start,
    required Duration end,
    required Duration duration,
    Duration min = const Duration(seconds: 1),
    Duration? max,
  }) {
    final total = duration < Duration.zero ? Duration.zero : duration;
    var s = start < Duration.zero ? Duration.zero : (start > total ? total : start);
    var e = end > total ? total : (end < Duration.zero ? Duration.zero : end);
    if (e < s) e = s;
    final shortest = min > total ? total : min;
    if (e - s < shortest) {
      e = s + shortest;
      if (e > total) {
        e = total;
        s = total - shortest;
      }
    }
    if (max != null && e - s > max) e = s + max;
    return VibeTrim(s, e);
  }

  bool isFull(Duration duration) => start <= Duration.zero && end >= duration;

  @override
  bool operator ==(Object other) =>
      other is VibeTrim && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
