import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/screen_tracker.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/callscreen/call_queries.dart';
import '../../chatscreen/entry/history_chat.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import 'helper/history_entry.dart';

enum HistoryMenuChoice { chat, rate, profile, report }

/// The row's ⋮ menu (RN explore `MenuAction` modal): Message (chat on),
/// Rate this Call, See Profile, Report. Null when dismissed.
Future<HistoryMenuChoice?> showHistoryMenu(
  BuildContext context,
  HistoryEntry entry,
) => showGeneralDialog<HistoryMenuChoice>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.t('actions.close'),
  barrierColor: AppColors.blackA(0.55),
  transitionDuration: const Duration(milliseconds: 180),
  routeSettings: ScreenTracker.sheet('call_history_menu'),
  transitionBuilder: (_, anim, _, child) =>
      FadeTransition(opacity: anim, child: child),
  pageBuilder: (_, _, _) => _HistoryMenu(entry: entry),
);

class _HistoryMenu extends HookWidget {
  const _HistoryMenu({required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entry;
    // Only a caller who talked to a host can rate; a review already left
    // turns the action into "Review Submitted". A failed lookup counts as
    // "no review" (RN `checkReview`).
    final review = useCallReview(context, e.item, enabled: e.canRate);
    final reviewed = review.data != null;
    final checking =
        e.canRate && !reviewed && (review.isLoading || review.isFetching);
    void pick(HistoryMenuChoice choice) => Navigator.of(context).pop(choice);
    final chat = useHistoryChatRoute(context, e);

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.all(16.ms),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 8.ms),
              decoration: BoxDecoration(
                color: c.modalCard,
                borderRadius: BorderRadius.circular(18.ms),
                border: Border.all(color: c.modalBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (chat != null)
                    _MenuAction(
                      icon: LucideIcons.messageCircle,
                      label: 'chat:history.message',
                      onPressed: () => pick(HistoryMenuChoice.chat),
                    ),
                  if (e.canRate)
                    _MenuAction(
                      icon: LucideIcons.star,
                      iconColor: reviewed ? c.accent : null,
                      label: reviewed
                          ? 'call:history.menu.reviewed'
                          : 'call:history.menu.rate',
                      loading: checking,
                      onPressed: reviewed || checking
                          ? null
                          : () => pick(HistoryMenuChoice.rate),
                    ),
                  if (e.isExpert)
                    _MenuAction(
                      icon: LucideIcons.user,
                      label: 'call:history.menu.profile',
                      onPressed: () => pick(HistoryMenuChoice.profile),
                    ),
                  _MenuAction(
                    icon: LucideIcons.flag,
                    label: e.isHostRole
                        ? 'call:history.menu.report_host'
                        : 'call:history.menu.report_user',
                    onPressed: () => pick(HistoryMenuChoice.report),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconColor,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? iconColor;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = 18.ms;
    return Pressable(
      onPressed: onPressed,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.ms, vertical: 12.ms),
          child: Row(
            children: [
              SizedBox.square(
                dimension: size,
                child: loading
                    ? Padding(
                        padding: EdgeInsets.all(2.ms),
                        child: RepaintBoundary(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.modalText,
                          ),
                        ),
                      )
                    : Icon(icon, size: size, color: iconColor ?? c.modalText),
              ),
              SizedBox(width: 10.ms),
              Expanded(
                child: CText(
                  label,
                  size: 14,
                  weight: FontWeight.w800,
                  color: c.modalText,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
