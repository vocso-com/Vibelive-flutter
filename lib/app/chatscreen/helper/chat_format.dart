import 'package:intl/intl.dart';

import 'chat_rows.dart';

/// Times and days of the chat, in the app language. A locale whose date
/// symbols are not loaded falls back to English (as `HistoryFormat`).
class ChatFormat {
  ChatFormat._(this._time, this._dayMonth, this._full, this._weekday);

  factory ChatFormat.of(String localeTag) =>
      _cache[localeTag] ??= _build(localeTag);

  static final _cache = <String, ChatFormat>{};

  static ChatFormat _build(String tag) {
    try {
      return ChatFormat._(
        DateFormat.jm(tag),
        DateFormat.MMMd(tag),
        DateFormat.yMMMd(tag),
        DateFormat.EEEE(tag),
      );
    } catch (_) {
      return ChatFormat._(
        DateFormat.jm('en_US'),
        DateFormat.MMMd('en_US'),
        DateFormat.yMMMd('en_US'),
        DateFormat.EEEE('en_US'),
      );
    }
  }

  final DateFormat _time;
  final DateFormat _dayMonth;
  final DateFormat _full;
  final DateFormat _weekday;

  /// `3:05 PM`.
  String time(DateTime at) => _time.format(at.toLocal());

  /// The date separator: an i18n key (`today`, `yesterday`) or the date
  /// itself (weekday within a week, then `Nov 3`, `Nov 3, 2025`).
  ({String? key, String? text}) day(DateTime at, {DateTime? now}) {
    final today = localDay(now ?? DateTime.now());
    final day = localDay(at);
    final days = today.difference(day).inDays;
    if (days == 0) return (key: 'chat:day.today', text: null);
    if (days == 1) return (key: 'chat:day.yesterday', text: null);
    if (days > 1 && days < 7) return (key: null, text: _weekday.format(day));
    if (day.year == today.year) return (key: null, text: _dayMonth.format(day));
    return (key: null, text: _full.format(day));
  }

  /// The chat list's time column: the time today, else as [day].
  ({String? key, String? text}) listTime(DateTime at, {DateTime? now}) {
    final today = localDay(now ?? DateTime.now());
    if (localDay(at) == today) return (key: null, text: time(at));
    return day(at, now: now);
  }

  /// `0:07`, `1:30`: a voice note's length or position.
  static String clock(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// `04:59`: time left on a bought photo, whole seconds rounded up so it
  /// shows the full time at the start and 00:00 only at the end.
  static String countdown(DateTime until, DateTime now) {
    final ms = until.difference(now).inMilliseconds;
    final s = ms <= 0 ? 0 : (ms / 1000).ceil();
    return '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }
}
