import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/config/runtime_config.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/query/query_hooks.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/hosthub_keys.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import '../../../api/hosthub/profile_models.dart';
import '../../../api/paymentscreen/billing_models.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import '../../../api/paymentscreen/runtime_config_queries.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/draft_controller.dart';
import '../helper/host_palette.dart';
import '../helper/host_payout.dart';
import '../helper/validation.dart';
import '../widgets/coin_stack.dart';
import '../widgets/continue_bar.dart';
import '../widgets/host_switch.dart';
import '../widgets/rate_stepper.dart';
import '../widgets/sheet_frame.dart';
import '../widgets/step_body.dart';

/// Rates: audio and/or video, both off until the host turns one on (it
/// then starts at the backend's minimum). Under each rate, live: what the
/// host earns per minute (big), what the caller pays and the platform fee,
/// and what callers who joined with their invite link bring (RN
/// CallRatesScreen "Estimated earnings payout"), worked out the way the
/// backend bills a call ([HostPayoutTerms]).
class RatesStep extends HookWidget {
  const RatesStep({super.key, required this.draft, this.callPricing});
  final HostDraftController draft;

  /// Overrides the host's own [CallPricing] (tests / explicit callers); null
  /// reads it from the host's own profile.
  final CallPricing? callPricing;

  @override
  Widget build(BuildContext context) {
    final pricing = usePricingConfig(context).data ?? PricingConfig.empty;
    final runtime = useRuntimeConfig(context);
    // The backend adds a `callPricing` block to the host's own profile when
    // it controls pricing for them (call_pricing §5.2). Read unconditionally
    // (hooks); a non-host / inactive host reads as null and the editable
    // screen below is unchanged.
    final ownPricing = useHostProfile(context).data?.callPricing;
    // Re-read the host's own profile on resume so a change the admin makes
    // (level, feature on) lands without a reinstall (§7.3); the CONFIG_UPDATED
    // push with scope `call_pricing` does the same while the app is open.
    useOnAppLifecycleStateChange((_, state) {
      if (state == AppLifecycleState.resumed) {
        queryCache.invalidateAll(const [HostHubKeys.profileAll]);
      }
    });
    final voicePayout = HostRatePayout.from(runtime, pricing, video: false);
    final videoPayout = HostRatePayout.from(runtime, pricing, video: true);
    final voiceMin = HostValidation.minRate(pricing.minimumVoiceRate);
    final videoMin = HostValidation.minRate(pricing.minimumVideoRate);
    // A floor above the current rate lifts it once the config is known.
    useEffect(() {
      if (draft.audioRate.value < voiceMin) draft.audioRate.value = voiceMin;
      if (draft.videoRate.value < videoMin) draft.videoRate.value = videoMin;
      return null;
    }, [voiceMin, videoMin]);
    final p = HostPalette.of(context);

    // Backend controls pricing for this host: a read-only earnings screen.
    // The host keeps the format on/off switch; only the amounts are fixed.
    final backendPricing = callPricing ?? ownPricing ?? CallPricing.inactive;
    if (backendPricing.active) {
      return HostEarningsReadOnly(draft: draft, pricing: backendPricing);
    }

    void showEarnings() {
      HostEvents.earningsViewed(
        audioRate: draft.audioOn.value ? draft.audioRate.value : null,
        videoRate: draft.videoOn.value ? draft.videoRate.value : null,
      );
      _showEarnings(
        context,
        draft,
        voice: voicePayout,
        video: videoPayout,
        runtime: runtime,
      );
    }

    void openInvite() => context.push<void>(AppRoutes.referral);

    return HostStepBody(
      title: 'hostflow:rates.title',
      subtitle: 'hostflow:rates.subtitle',
      children: [
        RateFormatCard(
          icon: LucideIcons.headphones,
          title: 'hostflow:rates.audio',
          subtitle: 'hostflow:rates.audio_sub',
          on: draft.audioOn,
          rate: draft.audioRate,
          min: voiceMin,
          payout: voicePayout,
          onInfo: showEarnings,
          onInvite: openInvite,
        ),
        SizedBox(height: 12.ms),
        RateFormatCard(
          icon: LucideIcons.video,
          title: 'hostflow:rates.video',
          subtitle: 'hostflow:rates.video_sub',
          on: draft.videoOn,
          rate: draft.videoRate,
          min: videoMin,
          payout: videoPayout,
          onInfo: showEarnings,
          onInvite: openInvite,
        ),
        SizedBox(height: 6.ms),
        // The full breakdown (call lengths, fees, invite link, payouts).
        Pressable(
          onPressed: showEarnings,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 10.ms),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.info, size: 17.ms, color: p.accent),
                SizedBox(width: 6.ms),
                Flexible(
                  child: CText(
                    'hostflow:rates.earnings_link',
                    size: 14.5,
                    weight: FontWeight.w700,
                    color: p.accent,
                  ),
                ),
                SizedBox(width: 4.ms),
                Icon(LucideIcons.arrowRight, size: 14.ms, color: p.accent),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The Rates step when VibeLive sets this host's pricing (call_pricing §7.1):
/// the host no longer picks an amount. Each format shows what they EARN per
/// minute, set by VibeLive, with the format on/off switch still editable.
/// No "caller pays", no platform fee, no invite-link rows, no fee sheet.
class HostEarningsReadOnly extends StatelessWidget {
  const HostEarningsReadOnly({
    super.key,
    required this.draft,
    required this.pricing,
  });

  final HostDraftController draft;
  final CallPricing pricing;

  @override
  Widget build(BuildContext context) => HostStepBody(
    title: 'hostflow:rates.title',
    subtitle: 'hostflow:rates.ro_subtitle',
    children: [
      _EarningCard(
        icon: LucideIcons.headphones,
        title: 'hostflow:rates.audio',
        subtitle: 'hostflow:rates.audio_sub',
        on: draft.audioOn,
        earn: pricing.voiceEarn,
        callType: 'audio',
      ),
      SizedBox(height: 12.ms),
      _EarningCard(
        icon: LucideIcons.video,
        title: 'hostflow:rates.video',
        subtitle: 'hostflow:rates.video_sub',
        on: draft.videoOn,
        earn: pricing.videoEarn,
        callType: 'video',
      ),
      SizedBox(height: 16.ms),
      _SetByVibeLiveNote(level: pricing.level),
    ],
  );
}

/// A read-only format card: the same header and switch as [RateFormatCard],
/// but once on it shows the fixed earning instead of a stepper.
class _EarningCard extends StatelessWidget {
  const _EarningCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.on,
    required this.earn,
    required this.callType,
  });

  final IconData icon;

  /// i18n keys.
  final String title;
  final String subtitle;
  final ValueNotifier<bool> on;

  /// Per-minute earning (₹); null = the backend sent no number (show nothing).
  final double? earn;

  /// `audio` / `video`, for analytics.
  final String callType;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return HostCard(
      padding: EdgeInsets.all(14.ms),
      child: ValueListenableBuilder<bool>(
        valueListenable: on,
        builder: (_, enabled, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48.ms,
                  height: 48.ms,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: p.buttonGradient,
                    borderRadius: BorderRadius.circular(13.ms),
                  ),
                  child: Icon(icon, size: 24.ms, color: p.onAccent),
                ),
                SizedBox(width: 12.ms),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CText(
                        title,
                        size: 17,
                        weight: FontWeight.w800,
                        color: p.text,
                      ),
                      SizedBox(height: 2.ms),
                      CText(
                        subtitle,
                        size: 13,
                        weight: FontWeight.w500,
                        color: p.muted,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8.ms),
                HostSwitch(
                  key: ValueKey('hostflow-switch-$title'),
                  value: enabled,
                  onChanged: (v) {
                    on.value = v;
                    HostEvents.callTypeToggled(callType: callType, enabled: v);
                  },
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: enabled
                  ? Padding(
                      padding: EdgeInsets.only(top: 14.ms),
                      child: _EarningAmount(earn: earn),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// "YOU EARN ₹14 / min" on the money-green card, with "Set by VibeLive"
/// under it. No info icon: there is no fee breakdown in this mode.
class _EarningAmount extends StatelessWidget {
  const _EarningAmount({required this.earn});

  final double? earn;

  @override
  Widget build(BuildContext context) {
    final c = _RateColors.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(14.ms, 12.ms, 10.ms, 12.ms),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: c.earnBg,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16.ms),
        border: Border.all(color: c.earnBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CText(
                  'hostflow:rates.you_earn',
                  size: 12,
                  weight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: c.earnLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2.ms),
                // Missing amount: show nothing rather than crash.
                if (earn case final earn?) ...[
                  _Amount(amount: earn, color: c.earnAmount, size: 32),
                  SizedBox(height: 4.ms),
                ],
                CText(
                  'hostflow:rates.set_by_vibelive',
                  size: 12,
                  height: 17,
                  weight: FontWeight.w600,
                  color: c.earnText,
                ),
              ],
            ),
          ),
          SizedBox(width: 6.ms),
          CoinStack(
            size: 62.ms,
            face: c.coinFace,
            side: c.coinSide,
            ring: c.coinRing,
            glyph: c.coinGlyph,
          ),
        ],
      ),
    );
  }
}

/// The footer note: earnings are VibeLive's to set, with the level if known.
class _SetByVibeLiveNote extends StatelessWidget {
  const _SetByVibeLiveNote({this.level});

  final int? level;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(LucideIcons.info, size: 15.ms, color: p.muted),
        SizedBox(width: 6.ms),
        Flexible(
          child: CText(
            level != null
                ? 'hostflow:rates.set_note_level'
                : 'hostflow:rates.set_note',
            variables: level != null ? {'level': level} : null,
            size: 13,
            height: 18,
            weight: FontWeight.w500,
            color: p.muted,
            align: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// One call format: icon, title, what it is and its switch; once on, the
/// rate and what it earns.
class RateFormatCard extends StatelessWidget {
  const RateFormatCard({
    super.key,
    required this.icon,
    required this.title,
    required this.on,
    required this.rate,
    required this.min,
    this.subtitle,
    this.payout,
    this.onInfo,
    this.onInvite,
  });

  final IconData icon;

  /// i18n keys.
  final String title;
  final String? subtitle;
  final ValueNotifier<bool> on;
  final ValueNotifier<int> rate;

  /// The backend's minimum (₹/min): where the rate starts when turned on.
  final int min;

  /// What the host earns at [rate]; shown under it.
  final HostRatePayout? payout;

  /// "How earnings work".
  final VoidCallback? onInfo;

  /// The invite link (Refer & earn).
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return HostCard(
      padding: EdgeInsets.all(14.ms),
      child: ValueListenableBuilder<bool>(
        valueListenable: on,
        builder: (_, enabled, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48.ms,
                  height: 48.ms,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: p.buttonGradient,
                    borderRadius: BorderRadius.circular(13.ms),
                  ),
                  child: Icon(icon, size: 24.ms, color: p.onAccent),
                ),
                SizedBox(width: 12.ms),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CText(
                        title,
                        size: 17,
                        weight: FontWeight.w800,
                        color: p.text,
                      ),
                      if (subtitle != null) ...[
                        SizedBox(height: 2.ms),
                        CText(
                          subtitle!,
                          size: 13,
                          weight: FontWeight.w500,
                          color: p.muted,
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 8.ms),
                HostSwitch(
                  key: ValueKey('hostflow-switch-$title'),
                  value: enabled,
                  onChanged: (v) {
                    // Turned on: starts at the backend's minimum.
                    if (v) rate.value = min;
                    on.value = v;
                    HostEvents.callTypeToggled(
                      callType: title.contains('video') ? 'video' : 'audio',
                      enabled: v,
                    );
                  },
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: enabled
                  ? Padding(
                      padding: EdgeInsets.only(top: 14.ms),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Label left, stepper right; the stepper wraps
                          // under the label on a narrow phone.
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            runSpacing: 8.ms,
                            spacing: 8.ms,
                            children: [
                              CText(
                                'hostflow:rates.your_rate',
                                size: 14,
                                weight: FontWeight.w500,
                                color: p.muted,
                              ),
                              HostRateStepper(
                                rate: rate,
                                min: min,
                                max: HostValidation.rateCeiling,
                                step: HostValidation.rateStep,
                              ),
                            ],
                          ),
                          if (payout case final payout?)
                            _Earnings(
                              rate: rate,
                              payout: payout,
                              onInfo: onInfo,
                              onInvite: onInvite,
                            ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// The earnings cards' own colors: money green and invite purple, in both
/// themes (the app's accent is lime in dark, purple in light).
@immutable
class _RateColors {
  const _RateColors({
    required this.earnBg,
    required this.earnBorder,
    required this.earnLabel,
    required this.earnAmount,
    required this.earnText,
    required this.coinFace,
    required this.coinSide,
    required this.coinRing,
    required this.coinGlyph,
    required this.inviteBg,
    required this.inviteBorder,
    required this.inviteAccent,
    required this.inviteAmount,
    required this.inviteText,
    required this.inviteIconBg,
  });

  static const dark = _RateColors(
    earnBg: [Color(0xFF1F3D10), Color(0xFF0F1A0A)],
    earnBorder: Color(0x99A8EC4A),
    earnLabel: Color(0xFFD9F5B8),
    earnAmount: BrandColors.lime,
    earnText: Color(0xCCFFFFFF),
    coinFace: Color(0xFFB9F25C),
    coinSide: Color(0xFF4F8A17),
    coinRing: Color(0xFFE2FFB0),
    coinGlyph: Color(0xFF1F3A0B),
    inviteBg: [Color(0xFF2C1554), Color(0xFF170B2E)],
    inviteBorder: Color(0x998F5EFE),
    inviteAccent: Color(0xFFC9A6FF),
    inviteAmount: Color(0xFFE2CCFF),
    inviteText: Color(0xFFC9A6FF),
    inviteIconBg: Color(0x478F5EFE),
  );

  static const light = _RateColors(
    earnBg: [Color(0xFFF2FBE7), Color(0xFFE0F4C8)],
    earnBorder: Color(0xFF9BD65A),
    earnLabel: Color(0xFF3D6B17),
    earnAmount: Color(0xFF2F7A0E),
    earnText: Color(0xFF4A5D3A),
    coinFace: Color(0xFF9ADB48),
    coinSide: Color(0xFF4F8A17),
    coinRing: Color(0xFFD8F7A8),
    coinGlyph: Color(0xFF1F3A0B),
    inviteBg: [Color(0xFFF7F1FF), Color(0xFFECDFFF)],
    inviteBorder: Color(0xFFC6A8FF),
    inviteAccent: BrandColors.purple,
    inviteAmount: Color(0xFF4A12C0),
    inviteText: Color(0xFF6B4BB0),
    inviteIconBg: Color(0x245E17EB),
  );

  static _RateColors of(BuildContext context) =>
      HostPalette.of(context).isDark ? dark : light;

  final List<Color> earnBg;
  final Color earnBorder;
  final Color earnLabel;
  final Color earnAmount;
  final Color earnText;
  final Color coinFace;
  final Color coinSide;
  final Color coinRing;
  final Color coinGlyph;
  final List<Color> inviteBg;
  final Color inviteBorder;
  final Color inviteAccent;
  final Color inviteAmount;
  final Color inviteText;
  final Color inviteIconBg;
}

/// "YOU EARN ₹15 / min" with the coins; "Customer pays · Platform fee"
/// under it; the invite-link card when invite callers pay more. Follows the
/// stepper.
class _Earnings extends StatelessWidget {
  const _Earnings({
    required this.rate,
    required this.payout,
    this.onInfo,
    this.onInvite,
  });

  final ValueListenable<int> rate;
  final HostRatePayout payout;
  final VoidCallback? onInfo;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final c = _RateColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: rate,
      builder: (_, r, _) {
        final std = payout.standard;
        final earns = std.perMinute(r);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 12.ms),
            Container(
              padding: EdgeInsets.fromLTRB(14.ms, 12.ms, 10.ms, 12.ms),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: c.earnBg,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16.ms),
                border: Border.all(color: c.earnBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Caption(
                          text: 'hostflow:rates.you_earn',
                          color: c.earnLabel,
                          onInfo: onInfo,
                        ),
                        SizedBox(height: 2.ms),
                        _Amount(amount: earns, color: c.earnAmount, size: 32),
                        SizedBox(height: 4.ms),
                        CText(
                          'hostflow:rates.earn_desc',
                          size: 12,
                          height: 17,
                          weight: FontWeight.w500,
                          color: c.earnText,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 6.ms),
                  CoinStack(
                    size: 62.ms,
                    face: c.coinFace,
                    side: c.coinSide,
                    ring: c.coinRing,
                    glyph: c.coinGlyph,
                  ),
                ],
              ),
            ),
            SizedBox(height: 8.ms),
            CText(
              'hostflow:rates.fee_line',
              variables: {
                'pays': rupees(r.toDouble()),
                'percent': rupees(std.percent),
                'fee': rupees(r - earns),
              },
              size: 12,
              weight: FontWeight.w500,
              color: p.muted,
            ),
            if (payout.inviteIsBetter) ...[
              SizedBox(height: 10.ms),
              Pressable(
                onPressed: onInvite,
                activeOpacity: 0.85,
                child: Container(
                  padding: EdgeInsets.fromLTRB(12.ms, 10.ms, 10.ms, 10.ms),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: c.inviteBg,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16.ms),
                    border: Border.all(color: c.inviteBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40.ms,
                        height: 40.ms,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.inviteIconBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.link,
                          size: 18.ms,
                          color: c.inviteAccent,
                        ),
                      ),
                      SizedBox(width: 12.ms),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Caption(
                              text: 'hostflow:rates.invite_title',
                              color: c.inviteAccent,
                            ),
                            _Amount(
                              amount: payout.invite.perMinute(r),
                              color: c.inviteAmount,
                              size: 22,
                            ),
                            CText(
                              'hostflow:rates.invite_desc',
                              size: 12,
                              weight: FontWeight.w500,
                              color: c.inviteText,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 6.ms),
                      Icon(
                        LucideIcons.chevronRight,
                        size: 20.ms,
                        color: c.inviteAccent,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// "YOU EARN ⓘ": small caps; the ⓘ opens "How earnings work".
class _Caption extends StatelessWidget {
  const _Caption({required this.text, required this.color, this.onInfo});

  /// i18n key.
  final String text;
  final Color color;
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        child: CText(
          text,
          size: 12,
          weight: FontWeight.w800,
          letterSpacing: 0.8,
          color: color,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      SizedBox(width: 5.ms),
      Pressable(
        onPressed: onInfo,
        semanticLabel: context.t('hostflow:rates.earn_title'),
        hitPadding: EdgeInsets.all(8.ms),
        child: Icon(LucideIcons.info, size: 13.ms, color: color),
      ),
    ],
  );
}

/// "₹15 / min": the amount large, "/ min" smaller on its baseline. Shrinks
/// rather than overflow.
class _Amount extends StatelessWidget {
  const _Amount({
    required this.amount,
    required this.color,
    required this.size,
  });

  final double amount;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        CText(
          'hostflow:rates.amount_plain',
          variables: {'amount': rupees(amount)},
          size: size,
          weight: FontWeight.w900,
          color: color,
          maxLines: 1,
        ),
        SizedBox(width: 4.ms),
        CText(
          'hostflow:rates.per_min_short',
          size: size * 0.5,
          weight: FontWeight.w800,
          color: color,
          maxLines: 1,
        ),
      ],
    ),
  );
}

/// "How earnings work": for each format on offer, what a 1, 5, 10 and 30
/// minute call pays, the fee rules, invite-link callers, and where the money
/// goes.
Future<void> _showEarnings(
  BuildContext context,
  HostDraftController draft, {
  required HostRatePayout voice,
  required HostRatePayout video,
  required RuntimeConfig runtime,
}) {
  return showHostSheet<void>(
    context,
    title: 'hostflow:rates.earn_title',
    name: 'host_earnings_sheet',
    child: Builder(
      builder: (sheet) {
        final p = HostPalette.of(sheet);
        Widget line(String key, [Map<String, dynamic>? vars]) => Padding(
          padding: EdgeInsets.only(bottom: 10.ms),
          child: CText(
            key,
            variables: vars,
            size: 14.5,
            height: 21,
            weight: FontWeight.w500,
            color: p.text,
          ),
        );
        final formats = [
          if (draft.audioOn.value)
            ('hostflow:rates.earn_audio', draft.audioRate.value, voice),
          if (draft.videoOn.value)
            ('hostflow:rates.earn_video', draft.videoRate.value, video),
        ];
        final invite = formats.any((f) => f.$3.inviteIsBetter);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20.ms, 0, 20.ms, 8.ms),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              line('hostflow:rates.earn_body'),
              for (final (title, rate, payout) in formats) ...[
                _CallTable(title: title, rate: rate, payout: payout),
                SizedBox(height: 14.ms),
              ],
              if (invite) line('hostflow:rates.earn_invite'),
              line('hostflow:rates.earn_short'),
              if (!runtime.bonus.bonusCreditHostPayoutEnabled)
                line('hostflow:rates.earn_bonus'),
              line('hostflow:rates.earn_note', {
                'min': rupees(runtime.pricing.minAmountToWithdrawal),
              }),
              SizedBox(height: 8.ms),
              HostButton(
                label: 'hostflow:rates.got_it',
                arrow: false,
                onPressed: () => Navigator.of(sheet).pop(),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// One format in the sheet: its fee rule and a call-length table.
class _CallTable extends StatelessWidget {
  const _CallTable({
    required this.title,
    required this.rate,
    required this.payout,
  });

  /// i18n key ("Audio at ₹{{rate}}/min").
  final String title;
  final int rate;
  final HostRatePayout payout;

  static const lengths = [1, 5, 10, 30];

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final std = payout.standard;
    Widget cell(
      String key,
      Map<String, dynamic>? vars, {
      bool head = false,
      bool strong = false,
      TextAlign align = TextAlign.start,
    }) => Expanded(
      child: CText(
        key,
        variables: vars,
        size: head ? 11.5 : 13.5,
        weight: head
            ? FontWeight.w800
            : (strong ? FontWeight.w800 : FontWeight.w600),
        color: head ? p.muted : (strong ? p.accent : p.text),
        align: align,
      ),
    );
    return Container(
      padding: EdgeInsets.all(12.ms),
      decoration: BoxDecoration(
        color: p.soft,
        borderRadius: BorderRadius.circular(14.ms),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CText(
            title,
            variables: {'rate': rate},
            size: 15,
            weight: FontWeight.w800,
            color: p.text,
          ),
          SizedBox(height: 4.ms),
          CText(
            'hostflow:rates.fee_rule',
            variables: {
              'percent': rupees(std.percent),
              'min': rupees(std.minimumPerCall),
            },
            size: 12.5,
            height: 18,
            weight: FontWeight.w500,
            color: p.muted,
          ),
          SizedBox(height: 10.ms),
          Row(
            children: [
              cell('hostflow:rates.col_call', null, head: true),
              cell(
                'hostflow:rates.col_pays',
                null,
                head: true,
                align: TextAlign.end,
              ),
              cell(
                'hostflow:rates.col_gets',
                null,
                head: true,
                align: TextAlign.end,
              ),
            ],
          ),
          for (final m in lengths)
            Padding(
              padding: EdgeInsets.only(top: 6.ms),
              child: Row(
                children: [
                  cell('hostflow:rates.minutes', {'minutes': m}),
                  cell('hostflow:rates.amount_plain', {
                    'amount': rupees((rate * m).toDouble()),
                  }, align: TextAlign.end),
                  cell(
                    'hostflow:rates.amount_plain',
                    {'amount': rupees(std.forCall(rate, m))},
                    strong: true,
                    align: TextAlign.end,
                  ),
                ],
              ),
            ),
          if (payout.inviteIsBetter) ...[
            SizedBox(height: 10.ms),
            CText(
              'hostflow:rates.invite_rule',
              variables: {
                'percent': rupees(payout.invite.percent),
                'min': rupees(payout.invite.minimumPerCall),
                'amount': rupees(payout.invite.perMinute(rate)),
              },
              size: 12.5,
              height: 18,
              weight: FontWeight.w600,
              color: p.success,
            ),
          ],
        ],
      ),
    );
  }
}
