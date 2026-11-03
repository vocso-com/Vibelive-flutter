import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/events/chat_events.dart';
import '../../../core/config/runtime_config.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../api/chat/chat_api.dart';
import '../../api/chat/chat_models.dart';
import '../../api/chat/chat_queries.dart';
import '../../api/paymentscreen/runtime_config_queries.dart';
import '../../component/c_toast.dart';
import '../components/message_bubble.dart';
import '../helper/chat_device.dart';
import '../helper/chat_outbox.dart';
import '../helper/chat_pricing.dart';
import '../helper/chat_room_controller.dart';
import '../helper/low_balance.dart';
import '../helper/pending_queue.dart';
import 'chat_sheets.dart';
import 'private_photo_viewer.dart';
import 'private_price_sheet.dart';

/// What the chat screen does on a tap, outside its build: the bubbles'
/// actions, the photo button, unlocking, and refused sends. One instance
/// per screen, so rows never need new closures.
class ChatScreenActions implements ChatBubbleActions {
  ChatScreenActions({
    required this.context,
    required this.controller,
    required this.text,
  });

  final BuildContext context;
  final ChatRoomController controller;

  /// The composer's text (a refused text goes back in).
  final TextEditingController text;

  StreamSubscription<OutboxRefused>? _refusals;
  bool _recharging = false;

  ChatConfig get _config => currentChatConfig();
  ChatOpen? get _open => controller.open.value;

  void attach() => _refusals = controller.refusals.listen(_onRefused);

  void dispose() => unawaited(_refusals?.cancel());

  // ── Sending ────────────────────────────────────────────────────────────

  ChatPrice priceOf(ChatMessageType type, {int seconds = 0}) {
    final o = _open;
    return ChatPricing.priceFor(
      side: o?.mySide ?? ChatSide.payer,
      type: type,
      config: _config,
      textPrice: o?.pricePerMessage,
      imagePrice: o?.imagePrice,
      seconds: seconds,
    );
  }

  void sendText(String value) {
    controller.sendText(value);
    ChatEvents.messageSent(
      type: 'text',
      paying: _open?.paying ?? false,
      pricePaise: priceOf(ChatMessageType.text).paise,
    );
  }

  void sendVoice(String path, int seconds) {
    controller.sendVoice(path, seconds);
    ChatEvents.voiceRecorded(outcome: 'sent', seconds: seconds);
    ChatEvents.messageSent(
      type: 'audio',
      paying: _open?.paying ?? false,
      pricePaise: priceOf(ChatMessageType.audio, seconds: seconds).paise,
      seconds: seconds,
    );
  }

  /// The photo button: gallery / camera / (host) a private photo.
  Future<void> attachPhoto() async {
    final o = _open;
    if (o == null) return;
    final canSell =
        o.mySide == ChatSide.host &&
        o.conversationId != null &&
        _config.privatePhotos.enabled;
    final choice = await showAttachSheet(context, canSellPrivate: canSell);
    if (choice == null || !context.mounted) return;
    if (choice == ChatAttach.private) return _privatePhoto();
    final camera = choice == ChatAttach.camera;
    final photo = await _pick(camera: camera);
    if (photo == null || !context.mounted) return;
    if (!await confirmPhoto(context, photo: photo)) return;
    final price = priceOf(ChatMessageType.image); // analytics only
    controller.sendPhoto(photo.path, width: photo.width, height: photo.height);
    ChatEvents.messageSent(
      type: 'image',
      paying: o.paying,
      pricePaise: price.paise,
    );
  }

  Future<ChatPickedPhoto?> _pick({required bool camera}) async {
    final ChatPickedPhoto? photo;
    try {
      photo = await ChatDevice.instance.pickPhoto(camera: camera);
    } catch (_) {
      CToast.show('chat:composer.pick_failed', variant: CToastVariant.error);
      return null;
    }
    if (photo == null) return null;
    ChatEvents.photoPicked(camera ? 'camera' : 'gallery');
    final max = _config.mediaMaxMb * 1024 * 1024;
    if (max > 0 && photo.bytes > max) {
      CToast.show(
        'chat:composer.too_big',
        variables: {'mb': '${_config.mediaMaxMb}'},
        variant: CToastVariant.error,
      );
      return null;
    }
    return photo;
  }

  Future<void> _privatePhoto() async {
    final source = await showAttachSheet(context, canSellPrivate: false);
    if (source == null || !context.mounted) return;
    final photo = await _pick(camera: source == ChatAttach.camera);
    if (photo == null || !context.mounted) return;
    final price = await askPrivatePhotoPrice(context, _config.privatePhotos);
    if (price == null) return;
    controller.sendPrivatePhoto(photo.path, price);
    ChatEvents.privatePhotoSent(price);
  }

  /// 402: nothing was saved. A text goes back in the box, and the
  /// recharge sheet says the message is ready to send.
  Future<void> _onRefused(OutboxRefused r) async {
    final e = r.entry;
    final type = e.type.wire;
    final code = r.refusal.code ?? r.error.type.name;
    ChatEvents.messageFailed(type: type, reason: code);
    if (r.failure != OutboxFailure.lowBalance) {
      const changed = {
        ChatCodes.hostOff,
        ChatCodes.blocked,
        ChatCodes.replyOnly,
        ChatCodes.disabled,
        ChatCodes.hostsOnly,
        ChatCodes.notAvailable,
      };
      // Not available (company-only chat): the calm notice says it, no
      // error on top.
      if (code == ChatCodes.notAvailable) {
        ChatOutbox.instance.discard(e.clientId);
        if (e.type == ChatMessageType.text && text.text.trim().isEmpty) {
          text.text = e.text ?? '';
        }
      } else if (code == ChatCodes.lowEarnings || changed.contains(code)) {
        CToast.error(r.error);
      }
      // The composer swaps for the right notice.
      if (changed.contains(code)) {
        if (code == ChatCodes.disabled) invalidateChatConfig();
        unawaited(controller.refreshOpen());
      }
      return;
    }
    if (e.type == ChatMessageType.text && text.text.trim().isEmpty) {
      ChatOutbox.instance.discard(e.clientId);
      text.value = TextEditingValue(
        text: e.text ?? '',
        selection: TextSelection.collapsed(offset: (e.text ?? '').length),
      );
    }
    await recharge(r.refusal, source: 'send');
  }

  /// Short of money: the app's own wallet (as the call balance gate's
  /// "Add" does), the missing amount filled in (never below the wallet's
  /// minimum top-up), with "Your message is ready to send" on top. Back
  /// from the wallet is this chat.
  Future<void> recharge(ChatRefusal refusal, {required String source}) async {
    if (_recharging || !context.mounted) return;
    _recharging = true;
    try {
      final gap = ChatLowBalance.gap(
        required: refusal.required,
        balance: refusal.balance ?? controller.balance.value,
      );
      final amount = topUpSuggestion(
        gap: gap,
        minAmountToAdd: currentRuntimeConfig().pricing.minAmountToAddWallet,
      );
      ChatEvents.addMoney(source);
      CToast.show(
        '${context.t('chat:recharge.title')}\n${context.t('chat:recharge.ready')}',
        translate: false,
        duration: const Duration(seconds: 4),
      );
      await openWallet(context, amount: amount);
    } finally {
      _recharging = false;
    }
  }

  /// The existing wallet route (`/wallet`, `amount` pre-filled when known).
  static Future<void> openWallet(BuildContext context, {int? amount}) =>
      context.push(
        Uri(
          path: AppRoutes.wallet,
          queryParameters: {'amount': ?amount?.toString(), 'reason': 'chat'},
        ).toString(),
      );

  // ── Bubbles ────────────────────────────────────────────────────────────

  @override
  Future<void> onFailedTap(ChatMessage m) async {
    final action = await showFailedActions(context);
    if (action == null) return;
    ChatEvents.failedAction(type: m.type.wire, action: action.name);
    switch (action) {
      case FailedAction.retry:
        controller.retry(m);
      case FailedAction.remove:
        controller.discard(m);
    }
  }

  @override
  void onCopy(ChatMessage m) {
    final t = m.text;
    if (t == null || t.isEmpty) return;
    unawaited(Clipboard.setData(ClipboardData(text: t)));
    CToast.show('chat:bubble.copied', variant: CToastVariant.success);
  }

  @override
  void onOpenPhoto(ChatMessage m) {
    final url = m.media?.url;
    if (url == null) return;
    unawaited(
      openChatPhoto(context, url: url, secure: _config.screenshotProtection),
    );
  }

  @override
  Future<void> onUnlock(ChatMessage m) async {
    final p = m.privatePhoto;
    if (p == null || m.isLocal) return;
    ChatEvents.privatePhotoUnlock(step: 'asked', price: p.price);
    final ok = await confirmUnlock(
      context,
      price: p.price,
      balance: controller.balance.value,
      from: _open?.peer.name ?? '',
      minutes: _config.privatePhotos.accessMinutes,
    );
    if (!ok || !context.mounted) return;
    ChatEvents.privatePhotoUnlock(step: 'confirmed', price: p.price);
    try {
      final paid = await controller.unlock(m);
      ChatEvents.privatePhotoUnlock(step: 'paid', price: p.price);
      unawaited(HapticFeedback.mediumImpact());
      if (context.mounted) await onOpenPrivate(paid);
    } on ApiException catch (e) {
      final refusal = ChatRefusal.of(e);
      ChatEvents.privatePhotoUnlock(
        step: 'failed',
        price: p.price,
        error: refusal.code ?? Analytics.errorCode(e),
      );
      if (refusal.isLowBalance) {
        await recharge(refusal, source: 'unlock');
      } else {
        CToast.error(e);
      }
    }
  }

  @override
  Future<void> onOpenPrivate(ChatMessage m) async {
    final until = m.privatePhoto?.expiresAt;
    if (until == null || !m.privatePhoto!.canOpenAt(DateTime.now())) {
      CToast.show('chat:private.cannot_open');
      return;
    }
    await openPrivatePhoto(
      context,
      messageId: m.id,
      until: until,
      viewSeconds: _config.privatePhotos.viewSeconds,
      secure: _config.screenshotProtection,
    );
  }
}
