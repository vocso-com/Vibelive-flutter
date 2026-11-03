import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/host_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/hosthub/profile_models.dart';
import '../../client/me/helper/host_availability_controller.dart';
import '../../client/me/widgets/host_availability_sheet.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../hosthub/onboarding/helper/host_funnel.dart';

/// The host's availability at a glance (the mode's icon and Online /
/// Scheduled / Offline, with the time left on an offline timer) beside the
/// navbar; a tap opens [showHostAvailabilitySheet]. A mode being saved shows
/// at once. Fixed [width] so the dock can size the island beside it; long
/// labels (Hindi) scale down. The dock decides who sees it (hosts only).
/// Compact (108 pt) so the island keeps room for four tabs once Chats shows.
/// Static (no pulse or glow): it sits over a scrolling feed.
class HostStatusPill extends StatefulWidget {
  const HostStatusPill({super.key, required this.mode, required this.height});
  final HostAvailability mode;
  final double height;

  static double get width => 108.ms;

  @override
  State<HostStatusPill> createState() => _HostStatusPillState();
}

class _HostStatusPillState extends State<HostStatusPill> {
  @override
  void initState() {
    super.initState();
    // Resumes (or ends) an offline timer; after the frame, as it may save.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => HostAvailabilityController.attach(),
    );
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<HostAvailability?>(
        valueListenable: HostAvailabilityController.pending,
        builder: (_, pending, _) =>
            _Pill(mode: pending ?? widget.mode, height: widget.height),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.mode, required this.height});
  final HostAvailability mode;
  final double height;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg, label) = switch (mode) {
      HostAvailability.available => (
        const Color(0xFFE8F5E9),
        const Color(0xFFA5D6A7),
        const Color(0xFF1B5E20),
        'home:status.online',
      ),
      HostAvailability.custom => (
        const Color(0xFFF3E8FF),
        const Color(0xFFDDD6FE),
        const Color(0xFF5B21B6),
        'home:status.scheduled',
      ),
      HostAvailability.vacation => (
        const Color(0xFF1E293B),
        const Color(0xFF334155),
        AppColors.white,
        'home:status.offline',
      ),
    };
    final lead = Icon(HostStatusIcons.of(mode), size: 14.ms, color: fg);
    final text = CText(
      label,
      size: 12.5,
      weight: FontWeight.w900,
      color: fg,
      maxLines: 1,
    );
    return Pressable(
      activeOpacity: 0.85,
      semanticLabel: context.t('home:status.open'),
      onPressed: () {
        HostEvents.statusPillTapped(status: hostStatusName(mode));
        unawaited(showHostAvailabilitySheet(context, source: 'navbar_pill'));
      },
      child: Container(
        height: height,
        width: HostStatusPill.width,
        padding: EdgeInsets.symmetric(horizontal: 11.ms),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: AppColors.blackA(0.16),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              lead,
              SizedBox(width: 6.ms),
              if (mode == HostAvailability.vacation)
                ValueListenableBuilder<Duration?>(
                  valueListenable: HostAvailabilityController.remaining,
                  builder: (_, left, _) => left == null
                      ? text
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            text,
                            CText(
                              'home:status.left',
                              variables: {'time': formatOfflineLeft(left)},
                              size: 9,
                              weight: FontWeight.w700,
                              color: fg.withValues(alpha: 0.75),
                              maxLines: 1,
                            ),
                          ],
                        ),
                )
              else
                text,
              SizedBox(width: 2.ms),
              Icon(LucideIcons.chevronDown, size: 13.ms, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
