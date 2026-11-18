import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../component/c_toast.dart';
import '../../component/skeleton.dart';
import '../../listingflow/profile/host_profile_sheet.dart';
import '../components/chat_composer.dart';
import '../components/chat_header.dart';
import '../components/chat_palette.dart';
import '../components/chat_secure_zone.dart';
import '../components/low_balance_bar.dart';
import '../components/private_photo_tip.dart';
import '../components/vanish_mode.dart';
import '../helper/low_balance.dart';
import '../helper/chat_room_controller.dart';
import '../helper/chat_screen_guard.dart';
import '../helper/chat_sync.dart';
import '../helper/chat_voice_player.dart';
import '../helper/private_photo_promo.dart';
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
    _useLeaveVanishInBackground(controller);
    _useOpenedEvent(controller);
    _useLowBalanceEvent(controller, config);
    useCloseWhenChatOff(context);

    final open = useValueListenable(controller.open);
    final vanish = useValueListenable(controller.vanish);
    final switching = useState(false);
    final lastSwitch = useRef<DateTime?>(null);
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

    // Vanish mode's look fades in and out over the whole chat at once.
    final look = useAnimationController(
      duration: const Duration(milliseconds: 380),
      initialValue: vanish.on ? 1 : 0,
    );
    final burst = useMemoized(() => ValueNotifier<int>(0));
    useEffect(() => burst.dispose, [burst]);
    // A live switch (mine, theirs, or a refused one going back): the room
    // fades, and the 🤫 fall when it came on.
    useEffect(() {
      void onSwitch() {
        final s = controller.vanishSwitch.value;
        unawaited(look.animateTo(s.on ? 1 : 0, curve: Curves.easeInOutCubic));
        if (s.celebrate) burst.value++;
      }

      controller.vanishSwitch.addListener(onSwitch);
      return () => controller.vanishSwitch.removeListener(onSwitch);
    }, [controller]);
    // Anything else (a chat that was already in vanish mode when it opened):
    // shown as it is, at once — no fade, no 🤫, nothing that looks like it
    // just came on.
    useEffect(() {
      if (!look.isAnimating) look.value = vanish.on ? 1 : 0;
      return null;
    }, [vanish.on]);

    // Where the gesture exists: vanish mode is on the server, and the chat
    // is one I can write in.
    final canSwitch =
        open != null &&
        vanish.canSwitch &&
        config.enabled &&
        !open.peer.deleted &&
        !open.notAvailable;
    void switchVanish(String source) => unawaited(
      _switchVanish(
        context,
        controller,
        switching,
        lastSwitch,
        !vanish.on,
        source,
      ),
    );

    return ChatSecureZone(
      active: config.screenshotProtection,
      child: AnimatedBuilder(
        animation: look,
        builder: (context, child) => ChatVanishScope(
          t: look.value,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: look.value >= 0.5 || ChatPalette.of(context).dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            child: child!,
          ),
        ),
        child: _Frame(
          header: ChatHeader(
            open: controller.open,
            onMenu: () => unawaited(
              _menu(
                context,
                controller,
                host,
                block.mutate,
                vanish: canSwitch ? vanish.on : null,
                onVanish: () => open?.conversationId == null
                    ? CToast.show('chat:vanish.needs_chat')
                    : switchVanish('menu'),
              ),
            ),
            onPeer: host == null
                ? null
                : () => showHostProfile(context, host, source: 'chat'),
            // No calls in vanish mode: "Turn off" sits where they were.
            calls: open == null
                ? null
                : vanish.on
                ? VanishOffPill(
                    busy: switching.value,
                    onTap: () => switchVanish('header'),
                  )
                : open.paying && host != null
                ? ChatCallButtons(host: host)
                : null,
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: _Body(
                  controller: controller,
                  actions: actions,
                  me: me,
                  onVanishSwitch: canSwitch
                      ? () => open.conversationId == null
                            ? CToast.show('chat:vanish.needs_chat')
                            : switchVanish('swipe')
                      : null,
                ),
              ),
              Positioned.fill(child: VanishBurst(trigger: burst)),
            ],
          ),
          bottom: open == null
              ? null
              : _Bottom(
                  open: open,
                  config: config,
                  controller: controller,
                  actions: actions,
                  text: text,
                  vanish: vanish,
                  // Read here, above the Scaffold: its body never sees the
                  // keyboard's inset.
                  keyboardUp: MediaQuery.viewInsetsOf(context).bottom > 0,
                ),
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

  /// The app went to the background: that is leaving the chat, so what I
  /// read in vanish mode goes (closing the screen does it too). A sheet over
  /// the chat is not leaving.
  static void _useLeaveVanishInBackground(ChatRoomController controller) {
    final lifecycle = useAppLifecycleState();
    useEffect(() {
      if (lifecycle == AppLifecycleState.paused ||
          lifecycle == AppLifecycleState.hidden ||
          lifecycle == AppLifecycleState.detached) {
        controller.leaveVanish();
      }
      return null;
    }, [lifecycle]);
  }

  /// Switches vanish mode for this chat (both people see it).
  static Future<void> _switchVanish(
    BuildContext context,
    ChatRoomController controller,
    ValueNotifier<bool> busy,
    ObjectRef<DateTime?> lastSwitch,
    bool on,
    String source,
  ) async {
    // One switch at a time, and no swipe right after one finished: a second
    // swipe within a second is almost always the same intent, twice. A tap on
    // "Turn off" or the ⋮ menu is deliberate and always goes.
    final last = lastSwitch.value;
    if (busy.value ||
        (source == 'swipe' &&
            last != null &&
            DateTime.now().difference(last) < const Duration(seconds: 1))) {
      return;
    }
    busy.value = true;
    try {
      await controller.setVanish(on);
      // No toast: the banner appearing / going says it, and a toast would sit
      // over the composer right when they start typing.
      ChatEvents.vanishSwitched(on: on, source: source, result: 'done');
      // They know vanish mode now: the first-time tip never shows again.
      ChatMessageList.markVanishTipUsed(controller.me);
    } on ApiException catch (e) {
      ChatEvents.vanishSwitched(on: on, source: source, result: 'failed');
      CToast.error(e);
    } finally {
      lastSwitch.value = DateTime.now();
      if (context.mounted) busy.value = false;
    }
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
        // The free opener never counts as low balance.
        if (config.firstMessageFree && o.paying && o.conversationId == null) {
          return;
        }
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
    Future<void> Function(BlockUserInput input) block, {
    bool? vanish,
    VoidCallback? onVanish,
  }) async {
    final open = controller.open.value;
    if (open == null) return;
    final action = await showChatMenu(
      context,
      prices: open.paying,
      vanish: vanish,
    );
    ChatEvents.menuAction(action?.name ?? 'dismissed');
    if (action == null || !context.mounted) return;
    switch (action) {
      case ChatMenuAction.vanish:
        onVanish?.call();
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
    this.onVanishSwitch,
  });

  final ChatRoomController controller;
  final ChatScreenActions actions;
  final String? me;
  final VoidCallback? onVanishSwitch;

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
            onVanishSwitch: onVanishSwitch,
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
    required this.vanish,
    this.keyboardUp = false,
  });

  final ChatOpen open;
  final ChatConfig config;
  final ChatRoomController controller;
  final ChatScreenActions actions;
  final TextEditingController text;
  final ChatVanishInfo vanish;

  /// The keyboard is up: the private photo tip folds away (typing keeps
  /// its room).
  final bool keyboardUp;

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
    // A host's own (shorter) limit when the server says so.
    final voiceMax = open.voiceMaxSeconds ?? config.voice.maxSeconds;
    // Private photos, pointed out to a host who has never sent one. Not in
    // vanish mode: the photo button is gone there.
    final promoHere =
        open.mySide == ChatSide.host &&
        open.conversationId != null &&
        config.privatePhotos.enabled &&
        !vanish.on;
    return ListenableBuilder(
      listenable: PrivatePhotoPromo.instance,
      builder: (context, _) {
        final promo = PrivatePhotoPromo.instance;
        final tip =
            promoHere && !keyboardUp && promo.showing(PrivatePhotoSpot.tip);
        if (tip) ChatEvents.privatePromo('shown', spot: 'tip');
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: tip
                  ? PrivatePhotoTip(
                      min: config.privatePhotos.minPrice,
                      max: config.privatePhotos.maxPrice,
                      onAction: () => unawaited(actions.privatePhotoFromTip()),
                      onClose: () {
                        ChatEvents.privatePromo('closed', spot: 'tip');
                        unawaited(promo.dismiss(PrivatePhotoSpot.tip));
                      },
                    )
                  : const SizedBox(width: double.infinity),
            ),
            _bar(
              context,
              voiceMax,
              attachDot: promoHere && promo.showing(PrivatePhotoSpot.button),
            ),
          ],
        );
      },
    );
  }

  Widget _bar(BuildContext context, int voiceMax, {required bool attachDot}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LowBalanceBar(
          balance: controller.balance,
          textPrice: open.pricePerMessage,
          threshold: config.lowBalanceMessages,
          paying: open.paying,
          chatEnabled: open.chatEnabled,
          // The opener (no conversation yet) is free, so show that instead of
          // a balance or a low-balance warning.
          firstMessageFree:
              config.firstMessageFree && open.conversationId == null,
          // My free messages left (once per person, across all chats).
          freeLeft: controller.freeLeft,
          onAdd: () {
            ChatEvents.addMoney('bar');
            unawaited(ChatScreenActions.openWallet(context));
          },
        ),
        ChatComposer(
          controller: text,
          maxLength: config.maxMessageLength,
          voiceMaxSeconds: voiceMax,
          textOnly: vanish.on,
          attachDot: attachDot,
          onSend: actions.sendText,
          onAttach: () => unawaited(actions.attachPhoto()),
          onVoice: actions.sendVoice,
        ),
      ],
    );
  }
}

/// The screen itself, painted from the chat palette inside the vanish scope
/// (so its background fades with everything else).
class _Frame extends StatelessWidget {
  const _Frame({required this.header, required this.body, this.bottom});

  final Widget header;
  final Widget body;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return Scaffold(
      backgroundColor: p.screen,
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          header,
          Expanded(child: body),
          ?bottom,
        ],
      ),
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
