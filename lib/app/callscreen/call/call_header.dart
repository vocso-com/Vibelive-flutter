import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../helper/call_billing.dart';
import '../helper/call_controller.dart';
import '../helper/call_session.dart';
import 'call_avatar.dart';
import 'helper/call_format.dart';
import 'helper/call_select.dart';

/// RN `CallHeader`: back circle, company pills, status pill (live timer
/// once connected), remote name, report flag. Stays above the ended
/// blocker.
class CallHeader extends StatelessWidget {
  const CallHeader({super.key, required this.onBack, required this.onFlag});

  final VoidCallback onBack;
  final VoidCallback onFlag;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Padding(
      padding: EdgeInsets.fromLTRB(16.sw, 10.vs, 16.sw, 0),
      child: Row(
        children: [
          _Circle(
            icon: LucideIcons.chevronLeft,
            iconSize: 24.ms,
            label: context.t('actions.back'),
            onPressed: onBack,
          ),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: _Centre(),
            ),
          ),
          _Circle(
            icon: LucideIcons.flag,
            iconSize: 18.ms,
            label: context.t('call:safety.title'),
            onPressed: onFlag,
          ),
        ],
      ),
    ),
  );
}

/// 40 circle on 25 % white (not `CBackButton`: that one is a bordered
/// square).
class _Circle extends StatelessWidget {
  const _Circle({
    required this.icon,
    required this.iconSize,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final double iconSize;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Pressable(
    onPressed: onPressed,
    activeOpacity: 0.2,
    semanticLabel: label,
    child: Container(
      width: 40.sw,
      height: 40.sw,
      decoration: BoxDecoration(
        color: AppColors.whiteA(0.25),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: iconSize, color: AppColors.white, weight: 600),
    ),
  );
}

class _Centre extends HookWidget {
  const _Centre();

  @override
  Widget build(BuildContext context) {
    final (callerCompany, receiverOfCompany, name) = useCallSelect(
      // "Company Account" is the company caller's own badge; its receiver
      // sees "App Official" instead, never both (U6).
      (s) => (
        s.isCaller && s.callerIsCompany,
        s.isReceiver && s.remote.isCompany,
        nonEmpty(s.remote.name),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (callerCompany) const _CompanyPill(),
        if (receiverOfCompany) const _OfficialPill(),
        const _StatusPill(),
        const _FreePill(),
        if (name != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: CText.raw(
              name,
              color: AppColors.whiteA(0.7),
              size: 12,
              weight: FontWeight.w800,
              letterSpacing: 1.5,
              uppercase: true,
              maxLines: 1,
              align: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

/// Hidden while calling / ringing; `...` while connecting, the live timer
/// once connected, `CALL ENDED...` after. The only widget on the call
/// screen that listens to the timer.
class _StatusPill extends HookWidget {
  const _StatusPill();

  @override
  Widget build(BuildContext context) {
    final (phase, instant) = useCallSelect(
      (s) => (s.phase, s.isInstantCall),
    );
    if (phase.isPreConnect && !instant) return const SizedBox.shrink();
    const style = (color: AppColors.white, size: 13.0, weight: FontWeight.w900);
    final Widget text;
    if (phase == CallPhase.ongoing) {
      text = ValueListenableBuilder<int>(
        valueListenable: CallController.instance.elapsed,
        builder: (_, seconds, _) => CText.raw(
          formatCallTime(seconds),
          color: style.color,
          size: style.size,
          weight: style.weight,
          maxLines: 1,
        ),
      );
    } else {
      final key = callStatusKey(phase, instant: instant);
      text = CText.raw(
        '${key == null ? '' : context.t(key)}...',
        color: style.color,
        size: style.size,
        weight: style.weight,
        maxLines: 1,
      );
    }
    return Container(
      constraints: BoxConstraints(minWidth: 100.sw),
      height: 30.vs,
      padding: EdgeInsets.symmetric(horizontal: 12.sw),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.whiteA(0.15),
        borderRadius: BorderRadius.circular(15.sw),
      ),
      child: text,
    );
  }
}

/// The caller's free time left on a free call (docs/free_calls.md), under
/// the timer; gone once the free minutes are over.
class _FreePill extends HookWidget {
  const _FreePill();

  @override
  Widget build(BuildContext context) {
    final (phase, callId, caller) = useCallSelect(
      (s) => (s.phase, s.callId, s.isCaller),
    );
    final free = caller && phase == CallPhase.ongoing
        ? CallBilling.freeFor(callId)
        : null;
    if (free == null) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: CallController.instance.elapsed,
      builder: (context, seconds, _) {
        final left = free.duration.inSeconds - seconds;
        if (left <= 0) return const SizedBox.shrink();
        return Padding(
          key: const ValueKey('call-free-pill'),
          padding: EdgeInsets.only(top: 6.vs),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10.sw, vertical: 4.vs),
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12.sw),
            ),
            child: CText(
              'call:free.left',
              variables: {'time': formatCallTime(left)},
              color: AppColors.white,
              size: 11,
              weight: FontWeight.w800,
              maxLines: 1,
            ),
          ),
        );
      },
    );
  }
}

class _CompanyPill extends StatelessWidget {
  const _CompanyPill();

  @override
  Widget build(BuildContext context) => Container(
    margin: EdgeInsets.only(bottom: 6.vs),
    padding: EdgeInsets.symmetric(horizontal: 12.sw, vertical: 4.vs),
    decoration: BoxDecoration(
      color: CallColors.companyPillBg,
      border: Border.all(color: CallColors.companyRing),
      borderRadius: BorderRadius.circular(20.sw),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.business, size: 14.ms, color: CallColors.companyPillText),
        SizedBox(width: 4.sw),
        const Flexible(
          child: CText(
            'call:badge.company',
            size: 12,
            weight: FontWeight.w700,
            color: CallColors.companyPillText,
            maxLines: 1,
          ),
        ),
      ],
    ),
  );
}

class _OfficialPill extends StatelessWidget {
  const _OfficialPill();

  @override
  Widget build(BuildContext context) => Container(
    margin: EdgeInsets.only(bottom: 6.vs),
    padding: EdgeInsets.symmetric(horizontal: 12.sw, vertical: 4.vs),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(20.sw),
      boxShadow: [BoxShadow(color: AppColors.blackA(0.15), blurRadius: 6)],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Flexible(
          child: CText(
            'call:badge.official',
            size: 12,
            weight: FontWeight.w700,
            color: AppColors.black,
            maxLines: 1,
          ),
        ),
        SizedBox(width: 4.sw),
        Icon(Icons.verified, size: 14.ms, color: AppColors.black),
      ],
    ),
  );
}
