import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/events/chat_events.dart';
import '../../../core/session/session_store.dart';
import '../../api/chat/chat_models.dart';
import '../../api/listingflow/listing_models.dart';
import '../../api/listingflow/listing_queries.dart';
import '../../listingflow/profile/helper/call_start.dart';
import '../../listingflow/profile/helper/host_profile_controller.dart';
import '../../listingflow/profile/helper/host_profile_rules.dart';
import '../../listingflow/profile/safety_prompt.dart';
import '../components/chat_header.dart';

/// The host behind a chat peer (rates, presence, the profile), from the
/// session's index at once or one read. Null while unknown or not a host.
HostCard? useChatHost(ChatPeer? peer) {
  final id = peer != null && peer.isHost && !peer.deleted ? peer.userId : null;
  final known = useMemoized(() => id == null ? null : peekHost(userId: id), [
    id,
  ]);
  final host = useState<HostCard?>(known);
  useEffect(() {
    if (id == null || known != null) return null;
    var live = true;
    ensureProfile(userId: id).then((h) {
      if (live) host.value = h;
    }, onError: (Object _) {});
    return () => live = false;
  }, [id]);
  return id == null ? null : (host.value ?? known);
}

/// Voice / video buttons in the header for the paying side, for the call
/// types the host has rates for. Calls go through the profile's own checks
/// (signed in, profile complete, balance gate, safety notice).
class ChatCallButtons extends HookWidget {
  const ChatCallButtons({super.key, required this.host});

  final HostCard host;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    final calls = useMemoized(
      () => HostProfileController(
        source: 'chat',
        close: () {},
        navigate: (path) {
          if (router != null) unawaited(router.push(path));
        },
        confirmStart: (video) => showSafetyPrompt(context, video: video),
        handOff: (target, video) =>
            startOutgoingCall(context, host: target, video: video),
      ),
    );
    useEffect(() => calls.dispose, [calls]);
    final busy = useValueListenable(calls.preparingCall);

    void call(bool video) {
      ChatEvents.callTapped(video ? 'video' : 'audio');
      calls.pendingVideo = video;
      unawaited(
        calls.placeCall(
          host,
          video: video,
          isMe: false,
          isCompany: HostProfileRules.isCompanyUser(
            SessionStore.instance.value.user,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (host.aPrice > 0)
          ChatCallButton(
            video: false,
            busy: busy && !calls.pendingVideo,
            onTap: () => call(false),
          ),
        if (host.vPrice > 0)
          ChatCallButton(
            video: true,
            busy: busy && calls.pendingVideo,
            onTap: () => call(true),
          ),
      ],
    );
  }
}
