import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../../core/storage/app_prefs.dart';
import '../../../api/paymentscreen/wallet_models.dart';

/// What a top-up of [amount] lands in the wallet with a [percent] bonus.
@immutable
class BonusPreview {
  factory BonusPreview.of(num amount, num percent) {
    final base = amount.isFinite && amount > 0 ? amount.toDouble() : 0.0;
    final pct = percent.isFinite && percent > 0 ? percent.toDouble() : 0.0;
    final bonus = (base * pct / 100).round();
    return BonusPreview._(base, bonus);
  }

  const BonusPreview._(this.amount, this.bonus);

  final double amount;
  final int bonus;
  double get total => amount + bonus;
}

/// Eligibility and per-install capping of the first-top-up offer (RN
/// `first-topup-offer.js`): once per session, three times ever, never again
/// after two dismissals. Asking a fourth time is nagging.
abstract final class FirstTopupOffer {
  static const maxLifetimeShows = 3;
  static const maxDismissals = 2;

  // Not under the `qcache:` prefix: logout must not reset the capping.
  static const _kShown = 'wallet:first_topup_offer_shown';
  static const _kDismissed = 'wallet:first_topup_offer_dismissed';

  static bool _shownThisSession = false;

  /// Bonus and referral credits do not count: a joining bonus must not
  /// disqualify someone from the offer it exists to set up.
  static bool hasPaidTopup(Iterable<WalletTransaction> rows) => rows.any(
    (tx) =>
        tx.type == 'topup' &&
        (tx.paymentStatus ?? '').toLowerCase() == 'success' &&
        const {'razorpay', 'payu'}.contains((tx.method ?? '').toLowerCase()),
  );

  static bool shouldShow({
    required bool enabled,
    required double percent,
    required bool hasPaid,
    int timesShown = 0,
    int dismissals = 0,
    bool shownThisSession = false,
  }) =>
      enabled &&
      percent > 0 &&
      !hasPaid &&
      !shownThisSession &&
      timesShown < maxLifetimeShows &&
      dismissals < maxDismissals;

  /// Checks the stored caps and, when the offer may show, counts it as
  /// shown. The caller has already checked the flag and the history.
  static bool claimShow({required bool enabled, required double percent}) {
    final shown = _read(_kShown);
    if (!shouldShow(
      enabled: enabled,
      percent: percent,
      hasPaid: false,
      timesShown: shown,
      dismissals: _read(_kDismissed),
      shownThisSession: _shownThisSession,
    )) {
      return false;
    }
    _shownThisSession = true;
    _write(_kShown, shown + 1);
    return true;
  }

  /// Whether the caps would let it show now, without counting a show.
  static bool mayShow({required double percent}) => shouldShow(
    enabled: true,
    percent: percent,
    hasPaid: false,
    timesShown: _read(_kShown),
    dismissals: _read(_kDismissed),
    shownThisSession: _shownThisSession,
  );

  static void recordDismissal() => _write(_kDismissed, _read(_kDismissed) + 1);

  /// Every amount the wallet offers (the admin's `wallet_preset_amounts`),
  /// lowest first, each once.
  static List<int> amounts(List<int> presets) =>
      ({for (final n in presets) if (n > 0) n}.toList()..sort());

  /// The amount picked for them at first: the middle one (most people pick
  /// the middle of three), marked "popular".
  static int? suggested(List<int> amounts) => amounts.isEmpty
      ? null
      : amounts[amounts.length == 2 ? 1 : (amounts.length - 1) ~/ 2];

  /// Three options is a choice; six is a form. The lowest, then the middle
  /// of what is offered (RN).
  static List<int> options(List<int> presets) {
    final sorted = presets.where((n) => n > 0).toList()..sort();
    if (sorted.length <= 3) return sorted;
    final mid = sorted.length ~/ 2;
    return [
      sorted.first,
      sorted[mid],
      sorted[math.min(mid + 1, sorted.length - 1)],
    ];
  }

  static int _read(String key) =>
      int.tryParse(AppPrefs.getString(key) ?? '') ?? 0;

  static void _write(String key, int value) =>
      unawaited(AppPrefs.setString(key, '$value'));

  @visibleForTesting
  static void debugResetSession() => _shownThisSession = false;
}
