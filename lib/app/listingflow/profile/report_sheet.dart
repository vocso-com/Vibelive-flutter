import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/events/discover_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/strapi.dart';
import '../../../core/session/session_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/component/component_queries.dart';
import '../../api/component/report_api.dart';
import '../../api/listingflow/listing_models.dart';
import '../../component/c_alert.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../component/skeleton.dart';
import 'helper/host_profile_rules.dart';
import '../../component/keyboard_inset.dart';
import 'profile_sheets.dart';

/// Report this host (RN report sheet): a category from
/// `/report-categories`, an optional note, then `POST /reports`. The submit
/// button is pinned under the scrolling part, so the note and the button
/// both stay above the keyboard.
Future<void> showReportSheet(BuildContext context, {required HostCard host}) =>
    showProfileSheet<void>(
      context,
      (_) => KeyboardInset(
        child: _ReportSheet(
          target: _ReportTarget(
            name: host.name,
            hostId: HostProfileRules.expertKey(host),
            // The public user, not the expert profile (RN).
            reportedUserId: host.userDocumentId ?? host.documentId,
          ),
        ),
      ),
      name: 'host_report_sheet',
    );

/// The same report, from a host's Vibe: same reasons, same `POST /reports`
/// against the host; the note says which Vibe, so the team can find it.
Future<void> showVibeReportSheet(
  BuildContext context, {
  required String hostName,
  required String? reportedUserId,
  required String expertDocumentId,
  required String statusDocumentId,
}) => showProfileSheet<void>(
  context,
  (_) => KeyboardInset(
    child: _ReportSheet(
      target: _ReportTarget(
        name: hostName,
        hostId: expertDocumentId,
        reportedUserId: reportedUserId,
        context: 'Reported from a Vibe ($statusDocumentId)',
      ),
    ),
  ),
  name: 'vibe_report_sheet',
);

/// Who is reported, and where from.
class _ReportTarget {
  const _ReportTarget({
    required this.name,
    required this.hostId,
    required this.reportedUserId,
    this.context,
  });

  final String name;

  /// Expert-profile key, for analytics.
  final String hostId;

  /// The reported public user's documentId.
  final String? reportedUserId;

  /// Appended to the note (what was reported, e.g. which Vibe).
  final String? context;
}

class _ReportSheet extends HookWidget {
  const _ReportSheet({required this.target});
  final _ReportTarget target;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final categories = useReportCategories(context);
    final selected = useState<Object?>(null);
    final note = useTextEditingController();
    final hostId = target.hostId;
    // The reason as sent, for the outcome events.
    final sentReason = useRef('');
    final submit = useSubmitReport(
      onSuccess: () {
        DiscoverEvents.reportSubmitted(
          hostId: hostId,
          reason: sentReason.value,
          hasNote: note.text.trim().isNotEmpty,
          noteLength: note.text.trim().length,
        );
        if (context.mounted) Navigator.of(context).pop();
        CAlert.show(
          title: 'host:report.success_title',
          message: 'host:report.success',
          variant: CAlertVariant.success,
        );
      },
      onError: (e) {
        DiscoverEvents.reportFailed(
          hostId: hostId,
          reason: sentReason.value,
          error: Analytics.errorCode(e),
        );
        CAlert.error(e, title: 'host:report.failed_title');
      },
    );

    void send() {
      if (submit.isPending) return;
      final session = SessionStore.instance.value;
      final reporter = session.userDocumentId ?? session.userId?.toString();
      final reported = target.reportedUserId;
      final (title, message) = reporter == null
          ? ('host:report.login_title', 'host:report.login_message')
          : reported == null
          ? ('host:report.title_short', 'host:report.unavailable')
          : selected.value == null
          ? ('host:report.missing_title', 'host:report.missing_category')
          : (null, null);
      if (title != null) {
        DiscoverEvents.reportBlocked(
          hostId: hostId,
          problem: reporter == null
              ? 'signed_out'
              : reported == null
              ? 'no_target'
              : 'no_reason',
        );
        CAlert.show(
          title: title,
          message: message,
          variant: CAlertVariant.warning,
        );
        return;
      }
      sentReason.value = '${selected.value}';
      submit.mutate(
        ReportInput(
          reporterId: reporter!,
          reportedUserId: reported!,
          categoryId: selected.value,
          note: [
            note.text.trim(),
            ?target.context,
          ].where((s) => s.isNotEmpty).join('\n\n'),
        ),
      );
    }

    final list = categories.data ?? const <JsonMap>[];
    final muted = c.isDark ? AppColors.whiteA(0.5) : AppColors.blackA(0.45);
    final name = target.name.isEmpty
        ? context.t(HostCard.unknownNameKey)
        : target.name;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SheetCard(
        child: Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHeader(
                icon: LucideIcons.flag,
                iconColor: StatusColors.dangerRed,
                title: 'host:report.title',
              ),
              Flexible(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(20.ms, 18.ms, 20.ms, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CText(
                        'host:report.reporting',
                        variables: {'name': name},
                        size: 12,
                        weight: FontWeight.w600,
                        color: muted,
                        maxLines: 1,
                      ),
                      SizedBox(height: 14.ms),
                      if (categories.isLoading && list.isEmpty)
                        const _CategorySkeleton()
                      else if (list.isEmpty)
                        // Required by the API: say so instead of a submit
                        // button that can only fail.
                        CText(
                          'host:report.categories_failed',
                          size: 12,
                          italic: true,
                          color: muted,
                        )
                      else
                        Wrap(
                          spacing: 8.ms,
                          runSpacing: 8.ms,
                          children: [
                            for (final cat in list)
                              _CategoryChip(
                                category: cat,
                                selected:
                                    selected.value != null &&
                                    selected.value == _idOf(cat),
                                onTap: () {
                                  selected.value = _idOf(cat);
                                  DiscoverEvents.reportReasonSelected(
                                    hostId: hostId,
                                    reason: '${_idOf(cat)}',
                                  );
                                },
                              ),
                          ],
                        ),
                      SizedBox(height: 14.ms),
                      _NoteField(controller: note),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20.ms, 16.ms, 20.ms, 0),
                child: _SubmitButton(
                  busy: submit.isPending,
                  ready: selected.value != null,
                  onTap: send,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Object? _idOf(JsonMap category) =>
      J.str(category['documentId']) ?? category['id'];
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final JsonMap category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = J.str(category['category']) ?? J.str(category['name']);
    final color = selected ? c.accent : c.text;
    return Pressable(
      onPressed: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 34.ms,
        padding: EdgeInsets.symmetric(horizontal: 12.ms),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.accentA(0.15) : AppColors.transparent,
          borderRadius: BorderRadius.circular(12.ms),
          border: Border.all(
            color: selected
                ? c.accent
                : (c.isDark ? AppColors.whiteA(0.12) : AppColors.blackA(0.12)),
          ),
        ),
        child: label == null
            ? CText(
                'host:report.category_fallback',
                size: 12,
                weight: FontWeight.w800,
                color: color,
                maxLines: 1,
              )
            : CText.raw(
                label,
                size: 12,
                weight: FontWeight.w800,
                color: color,
                maxLines: 1,
              ),
      ),
    );
  }
}

class _CategorySkeleton extends StatelessWidget {
  const _CategorySkeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Wrap(
      spacing: 8.ms,
      runSpacing: 8.ms,
      children: [
        for (final w in const [96, 72, 120, 84, 104])
          SkeletonBox(width: w.ms, height: 34.ms, radius: 12.ms),
      ],
    ),
  );
}

/// Multi-line note with a live `n/600` counter (only the counter rebuilds
/// while typing).
class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    final muted = dark ? AppColors.whiteA(0.4) : AppColors.blackA(0.4);
    const max = HostProfileRules.maxReportNote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        MediaQuery.withNoTextScaling(
          child: TextField(
            controller: controller,
            minLines: 4,
            maxLines: 6,
            maxLength: max,
            keyboardType: TextInputType.multiline,
            cursorColor: c.accent,
            style: TextStyle(color: c.text, fontSize: 14.ms),
            decoration: InputDecoration(
              // No label to float: no relayout animation on focus.
              floatingLabelBehavior: FloatingLabelBehavior.never,
              counterText: '',
              hintText: context.t('host:report.note_placeholder'),
              hintStyle: TextStyle(
                color: dark ? AppColors.whiteA(0.35) : AppColors.blackA(0.35),
                fontSize: 14.ms,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14.ms,
                vertical: 12.ms,
              ),
              enabledBorder: _border(
                dark ? AppColors.whiteA(0.12) : AppColors.blackA(0.12),
              ),
              focusedBorder: _border(c.accent),
            ),
          ),
        ),
        SizedBox(height: 6.ms),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, _) => CText.raw(
            '${value.text.length}/$max',
            size: 11,
            weight: FontWeight.w600,
            color: value.text.length >= max ? StatusColors.dangerRed : muted,
          ),
        ),
      ],
    );
  }

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14.ms),
    borderSide: BorderSide(color: color),
  );
}

/// Only a submission in flight disables it: a missing category is
/// explained on tap instead of a dead button (RN).
class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.busy,
    required this.ready,
    required this.onTap,
  });

  final bool busy;
  final bool ready;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: busy ? 0.6 : (ready ? 1 : 0.75),
    child: Pressable(
      onPressed: busy ? null : onTap,
      activeOpacity: 0.85,
      child: Container(
        height: 52.ms,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: StatusColors.dangerRed,
          borderRadius: BorderRadius.circular(18.ms),
        ),
        child: busy
            ? const SizedBox.square(
                dimension: 20,
                child: RepaintBoundary(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.white,
                  ),
                ),
              )
            : const CText(
                'host:report.submit',
                size: 13,
                weight: FontWeight.w900,
                letterSpacing: 1.4,
                color: AppColors.white,
              ),
      ),
    ),
  );
}
