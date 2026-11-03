import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/chat_events.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_api.dart';
import '../../api/chat/chat_models.dart';
import '../../api/chat/chat_queries.dart';
import '../../api/client/block_api.dart';
import '../../api/listingflow/listing_models.dart';
import '../../api/client/client_queries.dart';
import '../../callscreen/helper/push/chat_push.dart';
import '../../component/c_alert.dart';
import '../../component/c_state_view.dart';
import '../../component/c_text.dart';
import '../../component/skeleton.dart';
import '../../listingflow/profile/host_profile_sheet.dart';
import '../components/chat_composer.dart';
import '../components/chat_header.dart';
import '../components/chat_palette.dart';
import '../components/chat_secure_zone.dart';
import '../components/low_balance_bar.dart';
import '../helper/chat_pricing.dart';
import '../helper/low_balance.dart';
import '../helper/chat_room_controller.dart';
import '../helper/chat_screen_guard.dart';
import '../helper/chat_sync.dart';
import '../helper/chat_voice_player.dart';
import 'chat_calls.dart';
import 'chat_report_sheet.dart';
import 'chat_screen_actions.dart';
import 'chat_sheets.dart';
import 'chat_off_close.dart';
import 'message_list.dart';

/// `/chat/:userId`: one conversation, keyed by the other person's
/// public-user id (it may not exist yet). Header, messages, the low-balance
/// bar and the composer (or why there is none).
class ChatScreen extends HookWidget {
  const ChatScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final config = useChatConfigValue(context);
    final me = SessionStore.instance.value.userId?.toString();
    final controller = useMemoized(() => ChatRoomController(peer: userId), [
      userId,
    ]);
    final text = useTextEditingController();
    final actions = useMemoized(
      () => ChatScreenActions(
        context: context,
        controller: controller,
        text: text,
      )..attach(),
      [controller],
    );
    useEffect(() {
      ChatSync.instance.attach();
      unawaited(controller.load());
      return () {
        actions.dispose();
        controller.dispose();
        unawaited(ChatVoicePlayer.instance.release());
      };
    }, [controller]);
    _useVisibility(context, controller);
    _useOpenedEvent(controller);
    _useLowBalanceEvent(controller, config);
    useCloseWhenChatOff(context);

    final open = useValueListenable(controller.open);
    final host = useChatHost(open?.peer);
    // The app's block flow (it refreshes every list the person is in).
    final block = useBlockUser(
      onSuccess: () {
        ChatEvents.blocked('success');
        invalidateChatLists();
        if (context.mounted) Navigator.of(context).maybePop();
        CAlert.show(
          title: 'chat:block.success_title',
          message: 'chat:block.success',
          variant: CAlertVariant.success,
        );
      },
      onError: (e) {
        ChatEvents.blocked('failed');
        CAlert.error(e, title: 'chat:block.failed_title');
      },
    );
    final p = ChatPalette.of(context);

    return ChatSecureZone(
      active: config.screenshotProtection,
      child: Scaffold(
        backgroundColor: p.screen,
        resizeToAvoidBottomInset: true,
        body: Column(
          children: [
            ChatHeader(
              open: controller.open,
              onMenu: () =>
                  unawaited(_menu(context, controller, host, block.mutate)),
              onPeer: host == null
                  ? null
                  : () => showHostProfile(context, host, source: 'chat'),
              calls: open != null && open.paying && host != null
                  ? ChatCallButtons(host: host)
                  : null,
            ),
            Expanded(
              child: _Body(controller: controller, actions: actions, me: me),
            ),
            if (open != null)
              _Bottom(
                open: open,
                config: config,
                controller: controller,
                actions: actions,
                text: text,
              ),
          ],
        ),
      ),
    );
  }

  /// Visible = this route is the top full-screen one and the app is in
  /// front: its pushes are not drawn, it polls, and marks messages read.
  static void _useVisibility(
    BuildContext context,
    ChatRoomController controller,
  ) {
    final route = ModalRoute.of(context);
    final top = useValueListenable(ChatScreenGuard.instance.observer.top);
    final lifecycle = useAppLifecycleState();
    final front = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    final onTop = top == null ? (route?.isCurrent ?? true) : top == route;
    final visible = front && onTop;
    useEffect(() {
      controller.setVisible(visible);
      if (visible) {
        final id = controller.conversationId;
        if (id != null) unawaited(ChatPush.clear(id));
      }
      return null;
    }, [visible]);
    // The conversation became known while on screen: its notification too.
    useEffect(() {
      void onOpen() {
        final id = controller.conversationId;
        if (visible && id != null) unawaited(ChatPush.clear(id));
      }

      controller.open.addListener(onOpen);
      return () => controller.open.removeListener(onOpen);
    }, [controller, visible]);
  }

  static void _useOpenedEvent(ChatRoomController controller) {
    final sent = useRef(false);
    useEffect(() {
      void onOpen() {
        final o = controller.open.value;
        if (o == null || sent.value) return;
        sent.value = true;
        ChatEvents.opened(
          peerId: o.peer.userId,
          paying: o.paying,
          peerIsHost: o.peer.isHost,
          hasConversation: o.conversationId != null,
          chatEnabled: o.chatEnabled,
        );
      }

      controller.open.addListener(onOpen);
      return () => controller.open.removeListener(onOpen);
    }, [controller]);
  }

  /// `chat_low_balance_shown` when the bar comes up (once per count).
  static void _useLowBalanceEvent(
    ChatRoomController controller,
    ChatConfig config,
  ) {
    useEffect(() {
      void check() {
        final o = controller.open.value;
        if (o == null) return;
        final low = ChatLowBalance.of(
          paying: o.paying,
          chatEnabled: o.chatEnabled,
          balance: controller.balance.value,
          textPrice: o.pricePerMessage,
          threshold: config.lowBalanceMessages,
        );
        if (low != null) ChatEvents.lowBalanceShown(low.messagesLeft);
      }

      controller.balance.addListener(check);
      controller.open.addListener(check);
      return () {
        controller.balance.removeListener(check);
        controller.open.removeListener(check);
      };
    }, [controller, config.lowBalanceMessages]);
  }

  static Future<void> _menu(
    BuildContext context,
    ChatRoomController controller,
    HostCard? host,
    Future<void> Function(BlockUserInput input) block,
  ) async {
    final open = controller.open.value;
    if (open == null) return;
    final action = await showChatMenu(context, prices: open.paying);
    ChatEvents.menuAction(action?.name ?? 'dismissed');
    if (action == null || !context.mounted) return;
    switch (action) {
      case ChatMenuAction.prices:
        final add = await showChatPrices(
          context,
          open: open,
          config: currentChatConfig(),
          balance: controller.balance.value,
          host: host,
        );
        if (add && context.mounted) {
          ChatEvents.addMoney('prices');
          unawaited(ChatScreenActions.openWallet(context));
        }
      case ChatMenuAction.report:
        final id = open.conversationId;
        if (id == null) {
          await CAlert.show(
            title: 'chat:report.title',
            message: 'chat:report.no_conversation',
          );
          return;
        }
        await showChatReportSheet(
          context,
          conversationId: id,
          name: open.peer.name,
        );
      case ChatMenuAction.block:
        await _block(context, open.peer, block);
    }
  }

  static Future<void> _block(
    BuildContext context,
    ChatPeer peer,
    Future<void> Function(BlockUserInput input) block,
  ) async {
    final ok = await CAlert.confirm(
      title: 'chat:block.title',
      message: 'chat:block.message',
      variables: {'name': peer.name},
      confirmLabel: 'chat:block.confirm',
      variant: CAlertVariant.error,
    );
    ChatEvents.blocked(ok ? 'confirmed' : 'cancelled');
    if (ok && context.mounted) await block(BlockUserInput(peer.userId));
  }
}

/// Messages, or the first load's skeleton / problem.
class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    required this.actions,
    required this.me,
  });

  final ChatRoomController controller;
  final ChatScreenActions actions;
  final String? me;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatOpen?>(
      valueListenable: controller.open,
      builder: (context, open, _) {
        if (open != null) {
          return ChatMessageList(
            controller: controller,
            actions: actions,
            me: me,
          );
        }
        return ValueListenableBuilder<ApiException?>(
          valueListenable: controller.error,
          builder: (context, error, _) {
            if (error == null) return const _Skeleton();
            final code = ChatRefusal.of(error).code;
            if (code == ChatCodes.notAvailable) {
              return const CStateView(
                title: 'chat:notice.not_available',
                icon: LucideIcons.messageCircleOff,
              );
            }
            if (code == ChatCodes.blocked) {
              return const CStateView(
                title: 'chat:notice.blocked',
                icon: LucideIcons.userX,
              );
            }
            if (error.type == ApiErrorType.notFound ||
                code == ChatCodes.hostsOnly) {
              return CStateView(
                title: code == ChatCodes.hostsOnly
                    ? 'chat:notice.hosts_only'
                    : 'chat:notice.deleted',
                icon: LucideIcons.messageCircleOff,
              );
            }
            return CStateView.error(
              context,
              error,
              onRetry: () => unawaited(controller.load()),
            );
          },
        );
      },
    );
  }
}

/// The bar under the messages: the composer, or why there is none.
class _Bottom extends StatelessWidget {
  const _Bottom({
    required this.open,
    required this.config,
    required this.controller,
    required this.actions,
    required this.text,
  });

  final ChatOpen open;
  final ChatConfig config;
  final ChatRoomController controller;
  final ChatScreenActions actions;
  final TextEditingController text;

  @override
  Widget build(BuildContext context) {
    final notice = !config.enabled
        ? 'chat:notice.disabled'
        : open.peer.deleted
        ? 'chat:notice.deleted'
        : open.notAvailable
        ? 'chat:notice.not_available'
        : open.paying && !open.chatEnabled
        ? 'chat:notice.host_off'
        : open.mySide == ChatSide.host && open.conversationId == null
        ? 'chat:notice.reply_only'
        : null;
    if (notice != null) return _Notice(text: notice);
    final side = open.mySide;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LowBalanceBar(
          balance: controller.balance,
          textPrice: open.pricePerMessage,
          threshold: config.lowBalanceMessages,
          paying: open.paying,
          chatEnabled: open.chatEnabled,
          onAdd: () {
            ChatEvents.addMoney('bar');
            unawaited(ChatScreenActions.openWallet(context));
          },
        ),
        ChatComposer(
          controller: text,
          maxLength: config.maxMessageLength,
          idleLine: ChatPriceLine.idle(
            side: side,
            config: config,
            textPrice: open.pricePerMessage,
            imagePrice: open.imagePrice,
          ),
          textPrice: actions.priceOf(ChatMessageType.text),
          voicePrice: (s) => actions.priceOf(ChatMessageType.audio, seconds: s),
          voiceMaxSeconds: config.voice.maxSeconds,
          onSend: actions.sendText,
          onAttach: () => unawaited(actions.attachPhoto()),
          onVoice: actions.sendVoice,
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return DecoratedBox(
      key: ValueKey('chat-notice-$text'),
      decoration: BoxDecoration(
        color: p.bar,
        border: Border(top: BorderSide(color: p.barBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.ms, vertical: 18.ms),
          child: CText(
            text,
            size: 14,
            weight: FontWeight.w700,
            color: p.muted,
            align: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Shimmer(
      child: ListView(
        reverse: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.all(12.ms),
        children: [
          for (final (end, f) in const [
            (true, 0.5),
            (false, 0.62),
            (false, 0.4),
            (true, 0.7),
            (false, 0.55),
          ])
            Align(
              alignment: end
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: Padding(
                padding: EdgeInsets.only(top: 10.ms),
                child: SkeletonBox(
                  width: w * f,
                  height: 40.ms,
                  radius: ChatPalette.radius,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
