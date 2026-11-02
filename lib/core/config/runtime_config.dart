import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../network/strapi.dart';

/// Pricing limits read from config (RN `runtime-config.js` `pricing`).
@immutable
class RuntimePricing {
  const RuntimePricing({
    this.voiceCommissionPercent = 40,
    this.videoCommissionPercent = 40,
    this.minVoiceCallRate = 7,
    this.minVideoCallRate = 12,
    this.minBalanceVoiceCall = 20,
    this.minBalanceVideoCall = 20,
    this.minMinutesToInitiate = 5,
    this.minAmountToAddWallet = 20,
    this.minAmountToWithdrawal = 100,
  });

  final double voiceCommissionPercent;
  final double videoCommissionPercent;
  final double minVoiceCallRate;
  final double minVideoCallRate;
  final double minBalanceVoiceCall;
  final double minBalanceVideoCall;

  /// The cash wallet must cover this many minutes before a call starts.
  final double minMinutesToInitiate;
  final double minAmountToAddWallet;
  final double minAmountToWithdrawal;
}

/// Bonus flags (RN `runtime-config.js` `bonus`). All off by default.
@immutable
class RuntimeBonus {
  const RuntimeBonus({
    this.joiningEnabled = false,
    this.joiningAmount = 0,
    this.joiningExpiryDays = 0,
    this.abandonOfferEnabled = false,
    this.abandonOfferPercent = 0,
    this.abandonOfferWindowMinutes = 0,
    this.firstTopupBonusEnabled = false,
    this.firstTopupBonusPercent = 0,
    this.bonusCreditHostPayoutEnabled = false,
  });

  final bool joiningEnabled;
  final double joiningAmount;
  final double joiningExpiryDays;
  final bool abandonOfferEnabled;
  final double abandonOfferPercent;
  final double abandonOfferWindowMinutes;
  final bool firstTopupBonusEnabled;
  final double firstTopupBonusPercent;
  final bool bonusCreditHostPayoutEnabled;

  bool get firstTopupOn => firstTopupBonusEnabled && firstTopupBonusPercent > 0;
  bool get abandonOfferOn => abandonOfferEnabled && abandonOfferPercent > 0;
}

/// Whether host-recorded media is switched on, and the limits the app has to
/// enforce before uploading.
///
/// Both off by default. A build that never reaches the server, or one talking
/// to a server that predates these settings, must not offer a record button
/// for a feature the server will refuse — a host who records and is then
/// refused reads that as the app being broken, not as a feature that is off.
///
/// The limits carry their shipped values even while a feature is off, so they
/// can never be missing at the moment they start to matter.
@immutable
class RuntimeHostMedia {
  const RuntimeHostMedia({
    this.videoIntroEnabled = false,
    this.videoIntroMaxSeconds = 60,
    this.statusVisible = false,
    this.statusEnabled = false,
    this.statusMaxPerDay = 10,
    this.statusVisibleHours = 24,
    this.statusMaxSeconds = 30,
    this.statusAutoApprove = false,
  });

  final bool videoIntroEnabled;
  final double videoIntroMaxSeconds;

  /// Vibes in the app at all (admin master switch): the Home row and the
  /// Vibes on profiles. Off hides them for everyone.
  final bool statusVisible;

  /// Hosts may post (only ever on while [statusVisible] is).
  final bool statusEnabled;
  final double statusMaxPerDay;
  final double statusVisibleHours;

  /// Longest Vibe (status) the camera records (admin → Host Media).
  final double statusMaxSeconds;

  /// Vibes go live without review: a post shows at once.
  final bool statusAutoApprove;

  Duration get statusLimit => Duration(seconds: statusMaxSeconds.round());

  Duration get introLimit => Duration(seconds: videoIntroMaxSeconds.round());

  /// A cap of zero means posting is stopped on purpose, which the switch alone
  /// does not express.
  bool get canPostStatus => statusEnabled && statusMaxPerDay > 0;
  bool get canRecordIntro => videoIntroEnabled && videoIntroMaxSeconds > 0;
}

/// The single source for every pricing-derived number (RN
/// `runtime-config.js`). Every default is the literal the app shipped with,
/// so a failed or missing fetch changes nothing and no figure can read 0 or
/// NaN. Derive, never duplicate: use [CallRequirement] and
/// [topUpSuggestion] instead of doing the arithmetic at a call site.
@immutable
class RuntimeConfig {
  const RuntimeConfig({
    this.pricing = const RuntimePricing(),
    this.bonus = const RuntimeBonus(),
    this.presetAmounts = defaultPresets,
    this.gstPercent = 18,
    this.hostMedia = const RuntimeHostMedia(),
    this.configVersion,
    this.ttlSeconds = 900,
  });

  static const defaults = RuntimeConfig();
  static const defaultPresets = [50, 100, 500, 750, 1000, 1500];

  final RuntimePricing pricing;
  final RuntimeBonus bonus;

  /// Add-money quick-select amounts, ascending, never empty.
  final List<int> presetAmounts;

  /// GST added on top of a wallet top-up.
  final double gstPercent;

  /// Host video intros and statuses: on or off, and their limits.
  final RuntimeHostMedia hostMedia;
  final String? configVersion;

  /// How long a fetched config stays fresh (server-supplied).
  final double ttlSeconds;

  Duration get ttl => Duration(milliseconds: (ttlSeconds * 1000).round());

  /// Resolves the config from the `/app-config` body ([appConfig], RN's
  /// source) and the `/pricing-config` row ([pricingConfig]). The first one
  /// carrying a `pricing` / `bonus` / `presetAmounts` block wins; a legacy
  /// flat pricing row only fills the wallet minimum and rate floors.
  factory RuntimeConfig.resolve(Object? appConfig, [Object? pricingConfig]) {
    final server = _unwrap(appConfig) ?? _unwrap(pricingConfig);
    final legacy = Strapi.map(pricingConfig) ?? const <String, dynamic>{};
    const d = RuntimeConfig.defaults;
    const dp = RuntimePricing();
    const db = RuntimeBonus();
    final sp = Strapi.map(server?['pricing']) ?? const <String, dynamic>{};
    final sb = Strapi.map(server?['bonus']) ?? const <String, dynamic>{};

    double p(String key, double fallback, [String? legacyKey]) =>
        _num(_pick(sp, key)) ??
        (legacyKey == null ? null : _positive(legacy[legacyKey])) ??
        fallback;
    // Bonus settings: the admin's Pricing config field first, then the
    // app-config copy, then the default.
    double b(String key, double fallback, String admin) =>
        _num(legacy[admin]) ?? _num(_pick(sb, key)) ?? fallback;
    bool flag(String key, bool fallback, String admin) {
      final v = legacy[admin] ?? _pick(sb, key);
      return v == null ? fallback : J.boolean(v);
    }

    // Admin's `wallet_preset_amounts` (Pricing config) first, then the
    // app-config copy, then the built-in list.
    final fromAdmin = presetList(legacy['wallet_preset_amounts']);
    final presets = fromAdmin.isNotEmpty
        ? fromAdmin
        : presetList(server?['presetAmounts']);

    return RuntimeConfig(
      pricing: RuntimePricing(
        voiceCommissionPercent: p(
          'voiceCommissionPercent',
          dp.voiceCommissionPercent,
        ),
        videoCommissionPercent: p(
          'videoCommissionPercent',
          dp.videoCommissionPercent,
        ),
        minVoiceCallRate: p(
          'minVoiceCallRate',
          dp.minVoiceCallRate,
          'Minimum_voiceCall_Rate',
        ),
        minVideoCallRate: p(
          'minVideoCallRate',
          dp.minVideoCallRate,
          'Minimum_videoCall_Rate',
        ),
        minBalanceVoiceCall: p('minBalanceVoiceCall', dp.minBalanceVoiceCall),
        minBalanceVideoCall: p('minBalanceVideoCall', dp.minBalanceVideoCall),
        minMinutesToInitiate: p(
          'minMinutesToInitiate',
          dp.minMinutesToInitiate,
        ),
        minAmountToAddWallet: p(
          'minAmountToAddWallet',
          dp.minAmountToAddWallet,
          'Minimum_Amount_to_add_wallet',
        ),
        minAmountToWithdrawal: p(
          'minAmountToWithdrawal',
          dp.minAmountToWithdrawal,
          'Minimum_Amount_To_Withdrawal',
        ),
      ),
      bonus: RuntimeBonus(
        joiningEnabled: flag(
          'joiningEnabled',
          db.joiningEnabled,
          'joining_bonus_enabled',
        ),
        joiningAmount: b(
          'joiningAmount',
          db.joiningAmount,
          'joining_bonus_amount',
        ),
        joiningExpiryDays: b(
          'joiningExpiryDays',
          db.joiningExpiryDays,
          'joining_bonus_expiry_days',
        ),
        abandonOfferEnabled: flag(
          'abandonOfferEnabled',
          db.abandonOfferEnabled,
          'abandon_offer_enabled',
        ),
        abandonOfferPercent: b(
          'abandonOfferPercent',
          db.abandonOfferPercent,
          'abandon_offer_percent',
        ),
        abandonOfferWindowMinutes: b(
          'abandonOfferWindowMinutes',
          db.abandonOfferWindowMinutes,
          'abandon_offer_window_minutes',
        ),
        firstTopupBonusEnabled: flag(
          'firstTopupBonusEnabled',
          db.firstTopupBonusEnabled,
          'first_topup_bonus_enabled',
        ),
        firstTopupBonusPercent: b(
          'firstTopupBonusPercent',
          db.firstTopupBonusPercent,
          'first_topup_bonus_percent',
        ),
        bonusCreditHostPayoutEnabled: flag(
          'bonusCreditHostPayoutEnabled',
          db.bonusCreditHostPayoutEnabled,
          'bonus_credit_host_payout_enabled',
        ),
      ),
      presetAmounts: presets.isEmpty ? d.presetAmounts : presets,
      gstPercent: _num(server?['gstPercent']) ?? d.gstPercent,
      hostMedia: _hostMedia(server?['hostMedia']),
      configVersion: J.str(server?['configVersion']),
      ttlSeconds: _positive(server?['ttlSeconds']) ?? d.ttlSeconds,
    );
  }

  /// The `hostMedia` block, or the shipped defaults when a server predates it.
  ///
  /// `statusMaxPerDay` uses [_count] rather than [_positive]: zero there is a
  /// real answer — somebody stopped posting on purpose — whereas a zero-second
  /// clip limit would refuse every recording a host makes.
  static RuntimeHostMedia _hostMedia(Object? node) {
    final m = Strapi.map(node);
    const d = RuntimeHostMedia();
    if (m == null) return d;
    return RuntimeHostMedia(
      videoIntroEnabled: J.boolean(m['videoIntroEnabled']),
      videoIntroMaxSeconds:
          _positive(m['videoIntroMaxSeconds']) ?? d.videoIntroMaxSeconds,
      // A server that predates the master switch: posting on meant shown.
      statusVisible: m.containsKey('statusVisible')
          ? J.boolean(m['statusVisible'])
          : J.boolean(m['statusEnabled']),
      statusEnabled: J.boolean(m['statusEnabled']),
      statusMaxPerDay: _count(m['statusMaxPerDay']) ?? d.statusMaxPerDay,
      statusVisibleHours:
          _positive(m['statusVisibleHours']) ?? d.statusVisibleHours,
      statusMaxSeconds: _positive(m['statusMaxSeconds']) ?? d.statusMaxSeconds,
      statusAutoApprove: J.boolean(m['statusAutoApprove']),
    );
  }

  /// A finite number that may legitimately be zero.
  static double? _count(Object? v) {
    final n = _num(v);
    return n == null || n < 0 ? null : n;
  }

  /// RN `isRuntimeConfigStale`: no timestamp counts as stale.
  bool isStale(DateTime? savedAt, {DateTime? now}) =>
      savedAt == null || (now ?? DateTime.now()).difference(savedAt) > ttl;

  /// The cache wrapper and the Strapi envelope alike.
  static Map<String, dynamic>? _unwrap(Object? node) {
    Object? current = node;
    for (var depth = 0; depth < 4; depth++) {
      if (current is! Map) return null;
      // Any key the server's runtime-config block carries identifies it. Leaving
      // hostMedia out meant a response whose only block was hostMedia was not
      // recognised as the config at all, and the features read as off.
      if (current['pricing'] != null ||
          current['bonus'] != null ||
          current['presetAmounts'] != null ||
          current['hostMedia'] != null) {
        return Map<String, dynamic>.from(current);
      }
      current = current['data'] ?? current['attributes'];
    }
    return null;
  }

  /// `minMinutesToInitiate`, else its snake_case spelling.
  static Object? _pick(Map<String, dynamic> m, String key) =>
      m[key] ??
      m[key.replaceAllMapped(
        RegExp('[A-Z]'),
        (x) => '_${x.group(0)!.toLowerCase()}',
      )];

  /// RN `num`: null / blank / non-finite read as missing.
  static double? _num(Object? v) {
    final n = v is String && v.trim().isEmpty ? null : J.number(v);
    return n != null && n.isFinite ? n : null;
  }

  /// Top-up amounts from a list (`[50, 100]`) or admin text separated by
  /// commas, spaces or semicolons (`"50, 100, 200"`): positive, whole,
  /// de-duplicated, smallest first. Anything unreadable is skipped.
  static List<int> presetList(Object? raw) {
    final items = raw is List
        ? raw
        : raw is String
        ? raw.split(RegExp(r'[,;\s]+'))
        : const [];
    return <int>{
      for (final v in items)
        if (_positive(v is String ? v.replaceAll(RegExp(r'[^0-9.\-]'), '') : v)
            case final n?)
          n.round(),
    }.toList()..sort();
  }

  static double? _positive(Object? v) {
    final n = _num(v);
    return n != null && n > 0 ? n : null;
  }
}

/// The balance a call needs, and how far short the wallet is (RN
/// `computeCallRequirement`). Fails open: an unreadable rate or balance
/// lets the call through, like the gate always did.
@immutable
class CallRequirement {
  const CallRequirement._(this.required, this.gap);

  factory CallRequirement.of({
    required double rate,
    required double minMinutes,
    double? balance,
  }) {
    if (!rate.isFinite || rate <= 0 || !minMinutes.isFinite) {
      return const CallRequirement._(0, 0);
    }
    final required = rate * minMinutes;
    if (balance == null || !balance.isFinite) {
      return CallRequirement._(required, 0);
    }
    return CallRequirement._(required, math.max(0, required - balance));
  }

  final double required;
  final double gap;
  bool get canCall => gap == 0;
}

/// RN `computeTopUpSuggestion`: the gap, lifted to the wallet minimum, in
/// whole rupees. A zero gap still suggests the minimum.
int topUpSuggestion({required double gap, required double minAmountToAdd}) {
  final minimum = minAmountToAdd.isFinite && minAmountToAdd > 0
      ? minAmountToAdd
      : const RuntimePricing().minAmountToAddWallet;
  final target = gap.isFinite && gap > 0 ? gap : minimum;
  return math.max(target.ceil(), minimum.ceil());
}
