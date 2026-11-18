import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/call_ui_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_alert.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../helper/call_actions.dart';
import '../helper/call_alerts.dart';
import 'call_avatar.dart';
import 'call_safety_row.dart';
import 'helper/call_format.dart';
import 'helper/call_select.dart';
import 'helper/call_track.dart';
import 'helper/call_ui_state.dart';

enum _Kind { report, block }

/// RN close-button hitSlop.
const double _slop = 12;

/// RN in-call "SOMETHING WRONG?" panel (header flag; no backdrop, no
/// animation, a tap outside does not close it). Report / Block end the call
/// and then say "Thanks for telling us". [onHold] receives a future that
/// completes once that alert is closed, so the post-call step waits for it.
class CallSafetyPanel extends HookWidget {
  const CallSafetyPanel({super.key, required this.onHold});

  final void Function(Future<void> until) onHold;

  @override
  Widget build(BuildContext context) {
    final ui = CallScope.of(context).ui!;
    final busy = useState<_Kind?>(null);
    final name = useCallSelect((s) => nonEmpty(s.shownName));

    Future<void> run(_Kind kind) async {
      if (busy.value != null) return;
      final read = Completer<void>();
      onHold(read.future);
      busy.value = kind;
      final call = currentCallInfo();
      final outcome = kind == _Kind.report
          ? await CallActions.reportDuringCall()
          : await CallActions.blockDuringCall();
      CallUiEvents.safetyAction(
        action: kind.name,
        source: 'in_call',
        outcome: switch (outcome) {
          CallSafetyOutcome.done => 'done',
          CallSafetyOutcome.noTarget => 'no_target',
          CallSafetyOutcome.failed => 'failed',
        },
        call: call,
      );
      if (context.mounted) {
        busy.value = null;
        ui.safetyOpen.value = false;
      }
      try {
        // Root navigator: this panel is gone by now.
        await CAlert.show(
          title: CallFlowKeys.safetyTitle,
          message: CallFlowKeys.safetyMessage(
            outcome,
            block: kind == _Kind.block,
          ),
        );
      } finally {
        read.complete();
      }
    }

    final SafetyRowSizes sizes = (
      disc: 34.ms,
      icon: 16.ms,
      gap: 12.ms,
      padV: 11.ms,
      label: 13.5,
      hint: 10.5,
      hintGap: 1.ms,
    );
    return Positioned(
      left: 16.ms,
      right: 16.ms,
      bottom: MediaQuery.paddingOf(context).bottom + 140.ms,
      child: Stack(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(16.ms, 14.ms, 16.ms, 10.ms),
            decoration: BoxDecoration(
              color: CallColors.safetyPanel,
              borderRadius: BorderRadius.circular(24.ms),
              border: Border.all(color: AppColors.whiteA(0.12), width: 1.ms),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: 10.ms),
                  child: Row(
                    children: [
                      Expanded(
                        child: CText(
                          'call:safety.title',
                          color: AppColors.whiteA(0.55),
                          size: 9.5,
                          weight: FontWeight.w900,
                          letterSpacing: 1.6,
                          maxLines: 1,
                        ),
                      ),
                      // The X is drawn over this spot with its 12 pt slop
                      // (RN hitSlop must not grow the row).
                      SizedBox.square(dimension: 16.ms),
                    ],
                  ),
                ),
                CallSafetyRow(
                  sizes: sizes,
                  icon: LucideIcons.flag,
                  label: 'call:safety.report_label',
                  hint: 'call:safety.report_hint',
                  busy: busy.value == _Kind.report,
                  otherBusy: busy.value == _Kind.block,
                  onPressed: () => run(_Kind.report),
                ),
                CallSafetyRow(
                  sizes: sizes,
                  icon: LucideIcons.userX,
                  label: name == null
                      ? 'call:safety.block_label_plain'
                      : 'call:safety.block_label',
                  labelVariables: {'name': ?name},
                  hint: 'call:safety.block_hint',
                  busy: busy.value == _Kind.block,
                  otherBusy: busy.value == _Kind.report,
                  onPressed: () => run(_Kind.block),
                ),
              ],
            ),
          ),
          Positioned(
            top: 14.ms - _slop,
            right: 16.ms - _slop,
            child: Pressable(
              onPressed: () {
                ui.safetyOpen.value = false;
                CallUiEvents.safetyPanelClosed(currentCallInfo());
              },
              hitPadding: const EdgeInsets.all(_slop),
              semanticLabel: context.t('actions.close'),
              child: Icon(
                LucideIcons.x,
                size: 16.ms,
                color: AppColors.whiteA(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
