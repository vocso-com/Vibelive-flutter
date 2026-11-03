import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/chat_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_models.dart';
import '../../api/chat/chat_queries.dart';
import '../../component/c_text.dart';
import '../../component/c_toast.dart';
import '../../hosthub/hub/hub_list.dart';
import '../../hosthub/onboarding/helper/host_palette.dart';
import '../../hosthub/onboarding/widgets/host_switch.dart';

/// Me → Settings: chat notifications (everyone) and, for hosts, "Accept
/// chats" (`GET/PUT /chats/settings`). Hidden while chat is off. Each
/// switch moves at once and moves back if the save fails.
class ChatSettingsCard extends StatelessWidget {
  const ChatSettingsCard({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ChatAvailability.instance,
    builder: (_, on, _) => on ? const _Card() : const SizedBox.shrink(),
  );
}

class _Card extends HookWidget {
  const _Card();

  @override
  Widget build(BuildContext context) {
    final settings = useChatSettings(context);
    final s = settings.data;
    final host = SessionStore.instance.value.isExpert;

    Future<void> save(ChatSettings next, String setting, bool on) async {
      ChatEvents.settingChanged(setting: setting, on: on);
      try {
        await saveChatSettings(next);
      } on ApiException catch (e) {
        CToast.error(
          e.messageKey == null
              ? e.copyWith(messageKey: 'chat:settings.save_failed')
              : e,
        );
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 12.ms),
      child: HubListCard(
        rows: [
          _SwitchRow(
            key: const ValueKey('chat-setting-notify'),
            icon: LucideIcons.bell,
            label: 'chat:settings.notify',
            hint: 'chat:settings.notify_hint',
            value: s?.notify,
            onChanged: (v) => unawaited(
              save(
                (s ?? const ChatSettings()).copyWith(notify: v),
                'notify',
                v,
              ),
            ),
          ),
          if (host)
            _SwitchRow(
              key: const ValueKey('chat-setting-accept'),
              icon: LucideIcons.messageCircle,
              label: 'chat:settings.accept',
              hint: 'chat:settings.accept_hint',
              value: s == null ? null : (s.acceptChats ?? true),
              onChanged: (v) => unawaited(
                save(
                  (s ?? const ChatSettings()).copyWith(acceptChats: v),
                  'accept_chats',
                  v,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.icon,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String hint;

  /// Null while loading (the switch waits).
  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Padding(
      padding: EdgeInsets.all(14.ms),
      child: Row(
        children: [
          Container(
            width: 32.ms,
            height: 32.ms,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.tint,
              borderRadius: BorderRadius.circular(10.ms),
            ),
            child: Icon(icon, size: 17.ms, color: p.accent),
          ),
          SizedBox(width: 12.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CText(
                  label,
                  size: 15,
                  weight: FontWeight.w600,
                  color: p.text,
                  maxLines: 1,
                ),
                SizedBox(height: 2.ms),
                CText(
                  hint,
                  size: 12.5,
                  weight: FontWeight.w500,
                  color: p.muted,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          SizedBox(width: 10.ms),
          Opacity(
            opacity: value == null ? 0.4 : 1,
            child: HostSwitch(
              value: value ?? false,
              semanticLabel: context.t(label),
              onChanged: value == null ? null : onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
