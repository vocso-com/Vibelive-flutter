import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/chat_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/strapi.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/chat/chat_queries.dart';
import '../../api/listingflow/listing_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// Ways into a chat from elsewhere in the app.
abstract final class ChatEntry {
  /// The host takes chats: their "Accept chats" switch
  /// (`expert-profile.chat_enabled`), on when the profile does not say.
  static bool hostAcceptsChats(HostCard host) {
    final raw = host.raw;
    final expert = Strapi.map(raw['expert']);
    final flag = raw['chat_enabled'] ?? expert?['chat_enabled'];
    return flag == null || J.boolean(flag);
  }

  /// `/chat/:userId` for a host card (its public user), or null.
  static String? routeFor(HostCard host) {
    final id = host.receiverId;
    return id == null ? null : AppRoutes.chatWith('$id');
  }

  /// The host's name as they wrote it ("Priya", not the card's "PRIYA"):
  /// the public user's name, else the handle, else the card's name.
  static String displayName(HostCard host) {
    final user = Strapi.map(host.raw['user']);
    for (final v in [user?['name'], host.raw['handler'], host.name]) {
      final s = v?.toString().trim() ?? '';
      if (s.isNotEmpty && s != 'null') return s;
    }
    return '';
  }

  /// A host card can show a chat action: the host takes chats, has a public
  /// user, and is not the person looking at it.
  static bool canChatWith(HostCard host) =>
      routeFor(host) != null &&
      hostAcceptsChats(host) &&
      host.receiverId != SessionStore.instance.value.userId;
}

/// A Discover card's bottom row: Call Now (three quarters of the width)
/// with a message button after it (a quarter, on the right; mirrored in
/// Urdu) while chat is on for this account and the host takes chats.
/// Otherwise Call Now alone, exactly as before chat.
class ChatCallSplit extends StatelessWidget {
  const ChatCallSplit({
    super.key,
    required this.host,
    required this.call,
    this.source = 'discover',
  });

  final HostCard host;

  /// The card's Call Now button.
  final Widget call;

  /// Analytics source of a tap.
  final String source;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ChatAvailability.instance,
    child: call,
    builder: (context, on, call) {
      final route = ChatEntry.routeFor(host);
      if (!on || route == null || !ChatEntry.canChatWith(host)) return call!;
      return Row(
        children: [
          Expanded(flex: 3, child: call!),
          SizedBox(width: 6.ms),
          Expanded(
            child: _CardChatButton(
              onPressed: () {
                ChatEvents.entryTapped(
                  source: source,
                  peerId: '${host.receiverId}',
                );
                unawaited(context.push(route));
              },
            ),
          ),
        ],
      );
    },
  );
}

/// The message button on a card's photo: frosted white beside the solid
/// white Call Now, so the call stays the main action.
class _CardChatButton extends StatelessWidget {
  const _CardChatButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Pressable(
    key: const ValueKey('card-chat-button'),
    activeOpacity: 0.8,
    semanticLabel: context.t('chat:profile.chat'),
    onPressed: onPressed,
    child: Container(
      height: 32.ms,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.whiteA(0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.whiteA(0.5)),
      ),
      child: Icon(
        LucideIcons.messageCircle,
        size: 15.ms,
        color: AppColors.white,
      ),
    ),
  );
}

/// "Chat with Priya" under the call buttons on a host's profile, full
/// width in the outlined call button's style (the call row keeps its two
/// buttons, lined up). Only while chat is on, the host takes chats, and it
/// is not the viewer's own profile. No price (only the chat menu's Prices
/// sheet shows chat prices).
class ProfileChatButton extends StatelessWidget {
  const ProfileChatButton({
    super.key,
    required this.host,
    required this.isMe,
    required this.open,
  });

  final HostCard host;
  final bool isMe;

  /// Opens a route (the profile's own navigation).
  final void Function(String route) open;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ChatAvailability.instance,
    builder: (context, on, _) =>
        on ? _button(context) : const SizedBox.shrink(),
  );

  Widget _button(BuildContext context) {
    final route = ChatEntry.routeFor(host);
    if (isMe || route == null || !ChatEntry.hostAcceptsChats(host)) {
      return const SizedBox.shrink();
    }
    final c = context.colors;
    final dark = c.isDark;
    final name = ChatEntry.displayName(host);
    return Padding(
      padding: EdgeInsets.only(top: 10.ms),
      child: Pressable(
        key: const ValueKey('profile-chat-button'),
        activeOpacity: 0.85,
        semanticLabel: context.t(
          name.isEmpty ? 'chat:profile.chat' : 'chat:profile.chat_with',
          variables: {'name': name},
        ),
        onPressed: () {
          ChatEvents.entryTapped(
            source: 'profile',
            peerId: '${host.receiverId}',
          );
          open(route);
        },
        child: Container(
          height: 50.ms,
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16.ms),
          decoration: BoxDecoration(
            color: dark ? AppColors.whiteA(0.08) : AppColors.blackA(0.04),
            borderRadius: BorderRadius.circular(20.ms),
            border: Border.all(
              width: 1.5.ms,
              color: dark ? AppColors.whiteA(0.2) : AppColors.blackA(0.15),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.messageCircle, size: 19.ms, color: c.text),
              SizedBox(width: 8.ms),
              Flexible(
                child: CText(
                  name.isEmpty ? 'chat:profile.chat' : 'chat:profile.chat_with',
                  variables: {'name': name},
                  size: 14,
                  weight: FontWeight.w800,
                  color: c.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
