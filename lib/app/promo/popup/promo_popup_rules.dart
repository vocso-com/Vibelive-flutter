import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/storage/app_prefs.dart';
import '../../api/promo_banner/promo_popup_models.dart';

/// What this phone remembers about one popup.
@immutable
class PromoPopupHistory {
  const PromoPopupHistory({
    this.shown = 0,
    this.lastShownAt,
    this.lastClosedAt,
    this.acted = false,
  });

  static const none = PromoPopupHistory();

  factory PromoPopupHistory.fromJson(Object? json) {
    if (json is! Map) return none;
    DateTime? at(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return PromoPopupHistory(
      shown: json['s'] is int ? json['s'] as int : 0,
      lastShownAt: at(json['ls']),
      lastClosedAt: at(json['lc']),
      acted: json['a'] == true,
    );
  }

  /// Times it was shown on this phone.
  final int shown;
  final DateTime? lastShownAt;
  final DateTime? lastClosedAt;

  /// The main button was tapped once.
  final bool acted;

  Map<String, Object> toJson() => {
    's': shown,
    if (lastShownAt != null) 'ls': lastShownAt!.millisecondsSinceEpoch,
    if (lastClosedAt != null) 'lc': lastClosedAt!.millisecondsSinceEpoch,
    if (acted) 'a': true,
  };

  /// For trimming: the latest moment this popup mattered.
  int get touchedAt => [
    lastShownAt?.millisecondsSinceEpoch ?? 0,
    lastClosedAt?.millisecondsSinceEpoch ?? 0,
  ].reduce((a, b) => a > b ? a : b);

  PromoPopupHistory copyWith({
    int? shown,
    DateTime? lastShownAt,
    DateTime? lastClosedAt,
    bool? acted,
  }) => PromoPopupHistory(
    shown: shown ?? this.shown,
    lastShownAt: lastShownAt ?? this.lastShownAt,
    lastClosedAt: lastClosedAt ?? this.lastClosedAt,
    acted: acted ?? this.acted,
  );
}

/// The admin's "When it shows" rules, as pure functions (unit-tested).
abstract final class PromoPopupRulesCheck {
  /// Whether [p] may show at [now], given what this phone remembers.
  static bool eligible(PromoPopup p, PromoPopupHistory h, DateTime now) {
    final ends = p.content.endsAt;
    if (ends != null && !ends.isAfter(now)) return false;
    if (!p.template.canShow(p.content, now)) return false;
    final r = p.rules;
    if (r.maxShows > 0 && h.shown >= r.maxShows) return false;
    if (r.stopAfterAction && h.acted) return false;
    return switch (r.frequency) {
      PromoPopupFrequency.everyOpen => true,
      PromoPopupFrequency.afterClose =>
        h.lastClosedAt == null ||
            now.difference(h.lastClosedAt!) >=
                Duration(hours: r.reshowAfterHours),
      PromoPopupFrequency.daily =>
        h.lastShownAt == null || !_sameDay(h.lastShownAt!, now),
      PromoPopupFrequency.once => h.shown == 0,
    };
  }

  /// The first eligible popup in the admin's order, or null.
  static PromoPopup? pick(
    List<PromoPopup> popups,
    PromoPopupHistory Function(String id) history,
    DateTime now,
  ) {
    for (final p in popups) {
      if (eligible(p, history(p.id), now)) return p;
    }
    return null;
  }

  static bool _sameDay(DateTime a, DateTime b) {
    final x = a.toLocal();
    final y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}

/// [PromoPopupHistory] per popup id, kept in [AppPrefs]
/// (`promo_popups_state`), at most [keep] popups (the most recent).
abstract final class PromoPopupStore {
  static const key = 'promo_popups_state';
  static const keep = 100;

  static Map<String, PromoPopupHistory> _read() {
    try {
      final raw = AppPrefs.getString(key);
      if (raw == null) return {};
      final map = jsonDecode(raw);
      if (map is! Map) return {};
      return {
        for (final e in map.entries)
          '${e.key}': PromoPopupHistory.fromJson(e.value),
      };
    } catch (_) {
      return {};
    }
  }

  static PromoPopupHistory of(String id) =>
      _read()[id] ?? PromoPopupHistory.none;

  static Future<void> _write(Map<String, PromoPopupHistory> all) async {
    var entries = all.entries.toList();
    if (entries.length > keep) {
      entries.sort((a, b) => b.value.touchedAt.compareTo(a.value.touchedAt));
      entries = entries.take(keep).toList();
    }
    await AppPrefs.setString(
      key,
      jsonEncode({for (final e in entries) e.key: e.value.toJson()}),
    );
  }

  static Future<void> shown(String id, DateTime at) async {
    final all = _read();
    final h = all[id] ?? PromoPopupHistory.none;
    all[id] = h.copyWith(shown: h.shown + 1, lastShownAt: at);
    await _write(all);
  }

  /// Closed in any way; [acted]: by its main button.
  static Future<void> closed(String id, DateTime at, {bool acted = false}) async {
    final all = _read();
    final h = all[id] ?? PromoPopupHistory.none;
    all[id] = h.copyWith(lastClosedAt: at, acted: acted || h.acted);
    await _write(all);
  }

  @visibleForTesting
  static Future<void> clear() => AppPrefs.remove(key);
}
