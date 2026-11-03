import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/events/chat_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/strapi.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_api.dart';
import '../../api/chat/chat_queries.dart';
import '../../api/component/component_queries.dart';
import '../../component/c_alert.dart';
import '../../component/c_button.dart';
import '../../component/c_text.dart';
import '../../component/keyboard_inset.dart';
import '../../component/pressable.dart';
import '../../component/skeleton.dart';
import '../../listingflow/profile/profile_sheets.dart';

/// Report this chat (`POST /chats/report`): a reason from the app's report
/// categories and an optional note. The report carries the conversation
/// (and a message, when one was picked), so the team sees what happened.
Future<void> showChatReportSheet(
  BuildContext context, {
  required String conversationId,
  required String name,
  String? messageId,
}) => showProfileSheet<void>(
  context,
  (_) => KeyboardInset(
    child: _ReportSheet(
      conversationId: conversationId,
      messageId: messageId,
      name: name,
    ),
  ),
  name: 'chat_report_sheet',
);

class _ReportSheet extends HookWidget {
  const _ReportSheet({
    required this.conversationId,
    required this.name,
    this.messageId,
  });

  final String conversationId;
  final String? messageId;
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final categories = useReportCategories(context);
    final selected = useState<JsonMap?>(null);
    final note = useTextEditingController();
    final submit = useChatReport(
      onSuccess: () {
        ChatEvents.reported(category: _idOf(selected.value)?.toString());
        if (context.mounted) Navigator.of(context).pop();
        CAlert.show(
          title: 'chat:report.success_title',
          message: 'chat:report.success',
          variant: CAlertVariant.success,
        );
      },
      onError: (e) {
        ChatEvents.reportFailed(error: Analytics.errorCode(e));
        CAlert.error(e, title: 'chat:report.failed_title');
      },
    );

    void send() {
      if (submit.isPending) return;
      final cat = selected.value;
      if (cat == null) {
        CAlert.show(
          title: 'chat:report.missing_title',
          message: 'chat:report.missing_category',
          variant: CAlertVariant.warning,
        );
        return;
      }
      final text = note.text.trim();
      final label = J.str(cat['category']) ?? J.str(cat['name']) ?? '';
      submit.mutate(
        ChatReportInput(
          conversationId: conversationId,
          messageId: messageId,
          // The server wants the numeric category id.
          categoryId: cat['id'] ?? _idOf(cat),
          reason: text.isNotEmpty ? text : label,
        ),
      );
    }

    final list = categories.data ?? const <JsonMap>[];
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
                title: 'chat:report.title',
              ),
              Flexible(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(20.ms, 16.ms, 20.ms, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CText(
                        'chat:report.reporting',
                        variables: {'name': name},
                        size: 12,
                        weight: FontWeight.w600,
                        color: c.textMuted,
                        maxLines: 1,
                      ),
                      SizedBox(height: 12.ms),
                      if (categories.isLoading && list.isEmpty)
                        Shimmer(
                          child: Wrap(
                            spacing: 8.ms,
                            runSpacing: 8.ms,
                            children: [
                              for (final w in const [96, 72, 120, 84])
                                SkeletonBox(
                                  width: w.ms,
                                  height: 34.ms,
                                  radius: 12.ms,
                                ),
                            ],
                          ),
                        )
                      else
                        Wrap(
                          spacing: 8.ms,
                          runSpacing: 8.ms,
                          children: [
                            for (final cat in list)
                              _Chip(
                                label:
                                    J.str(cat['category']) ??
                                    J.str(cat['name']) ??
                                    context.t('chat:report.category_fallback'),
                                selected:
                                    selected.value != null &&
                                    _idOf(selected.value) == _idOf(cat),
                                onTap: () => selected.value = cat,
                              ),
                          ],
                        ),
                      SizedBox(height: 12.ms),
                      MediaQuery.withNoTextScaling(
                        child: TextField(
                          controller: note,
                          minLines: 3,
                          maxLines: 5,
                          maxLength: 600,
                          style: TextStyle(color: c.text, fontSize: 14.ms),
                          cursorColor: c.accent,
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: context.t('chat:report.note_placeholder'),
                            enabledBorder: _border(c.border),
                            focusedBorder: _border(c.accent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20.ms, 14.ms, 20.ms, 0),
                child: CButton(
                  title: 'chat:report.submit',
                  loading: submit.isPending,
                  showArrow: false,
                  color: StatusColors.dangerRed,
                  titleColor: AppColors.white,
                  onPressed: send,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Object? _idOf(JsonMap? category) => category == null
      ? null
      : (J.str(category['documentId']) ?? category['id']);

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14.ms),
    borderSide: BorderSide(color: color),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onPressed: onTap,
      child: Container(
        height: 34.ms,
        padding: EdgeInsets.symmetric(horizontal: 12.ms),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.accentA(0.15) : AppColors.transparent,
          borderRadius: BorderRadius.circular(12.ms),
          border: Border.all(color: selected ? c.accent : c.border),
        ),
        child: CText.raw(
          label,
          size: 12,
          weight: FontWeight.w800,
          color: selected ? c.accent : c.text,
          maxLines: 1,
        ),
      ),
    );
  }
}
