import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../../core/analytics/events/app_events.dart';
import '../../../../core/analytics/screen_tracker.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/router/external_open.dart';
import '../../../../core/utils/log.dart';
import '../../../api/authscreen/push_api.dart';
import '../../../api/authscreen/push_queries.dart';
import '../../../authscreen/helper/deep_links.dart';
import '../call_signals.dart';
import 'call_push_classifier.dart';
import 'campaign_push.dart';
import 'push_classifier.dart';
import 'push_envelope.dart';
import 'verification_notifications.dart';
import 'wallet_notifications.dart';

/// Where a notification tap goes.
enum TapDestination {
  campaign,
  ongoingCall,
  incomingCall,
  callHistory,
  callback,
  hostProfile,
  wallet,
  verification,
  referral,
  route,
  link,
  none,
}

@immutable
class TapTarget {
  const TapTarget(this.destination, [this.location]);
  final TapDestination destination;

  /// Route ([TapDestination.route]), URL ([TapDestination.link]), or the host's
  /// user documentId ([TapDestination.hostProfile]).
  final String? location;

  @override
  bool operator ==(Object other) =>
      other is TapTarget &&
      other.destination == destination &&
      other.location == location;

  @override
  int get hashCode => Object.hash(destination, location);

  @override
  String toString() => 'TapTarget($destination, $location)';
}

/// Routes a TAP on a non-call or call notification, in every app state
/// (spec_call_native §4.7). Delivery never navigates; only taps do.
///
/// Order: campaign → call-like → wallet (explicit) → verification (explicit)
/// → wallet (keywords) → verification (keywords) → referral → `route` →
/// link. An explicit type beats a keyword scan (CE correction), and a
/// campaign titled "Your wallet is low" goes to the campaign (memory).
abstract final class NotificationTapRouter {
  static const dedupeWindow = Duration(seconds: 2);
  static const referralTypes = {
    'referral',
    'invite',
    'referral_reward',
    'referral_bonus',
    'referral_joined',
  };

  static String? _lastKey;
  static DateTime? _lastAt;

  /// `onMessageOpenedApp` / `getInitialMessage`.
  static Future<bool> handleRemote(RemoteMessage message) =>
      handle(PushEnvelope.fromRemote(message));

  /// A tap on one of our own notifications.
  static Future<bool> handleLocal(NotificationResponse response) async {
    final m = PushEnvelope.fromPayload(response.payload);
    return m == null ? false : handle(m);
  }

  /// Where [m] goes (pure).
  static TapTarget route(PushEnvelope m) {
    if (PushClassifier.isCampaign(m)) {
      return const TapTarget(TapDestination.campaign);
    }
    if (PushClassifier.isCall(m)) {
      if (CallPushClassifier.isOngoingTap(m)) {
        return const TapTarget(TapDestination.ongoingCall);
      }
      if (CallPushClassifier.isMissedTap(m)) {
        return const TapTarget(TapDestination.callHistory, AppRoutes.explore);
      }
      return switch (CallPushClassifier.classify(m)) {
        CallPushKind.pingClient => const TapTarget(TapDestination.callback),
        CallPushKind.invite => const TapTarget(TapDestination.incomingCall),
        // Everything else belongs to the live call flow.
        _ => const TapTarget(TapDestination.none),
      };
    }
    // A host the user favourited or looked at is reachable again. An explicit
    // type, so it is settled before any keyword scan; after the call block on
    // purpose, because a ringing or ongoing call is the more urgent thing on the
    // device and a nudge can wait.
    if (m.type == 'host_online') {
      final open = m.data['openUserId']?.trim();
      if (open != null && open.isNotEmpty) {
        return TapTarget(TapDestination.hostProfile, open);
      }
      // No host to open. Falls through rather than navigating somewhere
      // arbitrary: the specific host IS the point of this notification.
    }
    if (WalletClassifier.isExplicitTap(m)) {
      return const TapTarget(TapDestination.wallet, AppRoutes.wallet);
    }
    if (VerificationNotifications.isExplicit(m)) {
      return const TapTarget(
        TapDestination.verification,
        AppRoutes.personalInfo,
      );
    }
    if (WalletClassifier.matchesTapKeywords(m)) {
      return const TapTarget(TapDestination.wallet, AppRoutes.wallet);
    }
    if (VerificationNotifications.matchesKeywords(m)) {
      return const TapTarget(
        TapDestination.verification,
        AppRoutes.personalInfo,
      );
    }
    if (referralTypes.contains(m.type)) {
      return const TapTarget(TapDestination.referral, AppRoutes.referral);
    }
    final route = m.data['route']?.trim();
    if (route != null && route.startsWith('/')) {
      return TapTarget(TapDestination.route, route);
    }
    final link = m.data['url']?.trim() ?? m.deeplink;
    if (link != null && link.isNotEmpty) {
      return TapTarget(TapDestination.link, link);
    }
    return const TapTarget(TapDestination.none);
  }

  /// Routes [m]. False for a duplicate tap or nothing to open.
  static Future<bool> handle(PushEnvelope m, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final key = tapKey(m);
    if (key != null) {
      final last = _lastAt;
      if (_lastKey == key &&
          last != null &&
          at.difference(last) < dedupeWindow) {
        return false;
      }
      _lastKey = key;
      _lastAt = at;
    }
    final target = route(m);
    Log.d('NotificationTap', '${m.type} → $target');
    _logOpened(target, m);
    try {
      return await _open(target, m);
    } catch (e, st) {
      Log.e('NotificationTap', e, st);
      return false;
    }
  }

  /// Analytics: every tap (calls included: a missed-call tap opens History).
  static void _logOpened(TapTarget target, PushEnvelope m) {
    ExternalOpen.mark('push');
    final location = target.location;
    final destination = switch (target.destination) {
      TapDestination.ongoingCall => 'ongoing_call',
      TapDestination.incomingCall => 'incoming_call',
      TapDestination.callHistory => 'call_history',
      final d => d.name,
    };
    AppEvents.pushOpened(
      destination: destination,
      type: m.type,
      campaignId: AppEvents.campaignIdOf(m.data),
      screen: location != null && location.startsWith('/')
          ? ScreenTracker.nameFor(Uri.parse(location))
          : null,
      hasDeeplink: m.deeplink != null,
    );
  }

  /// One tap reaches several listeners: `trackingId|deeplink`, else the
  /// message id, else our notification id.
  static String? tapKey(PushEnvelope m) {
    final tracking = pushTrackingIdOf(m.data);
    if (tracking != null || m.deeplink != null) {
      return '${tracking ?? ''}|${m.deeplink ?? ''}';
    }
    return m.messageId ?? m.notificationId;
  }

  static Future<bool> _open(TapTarget target, PushEnvelope m) async {
    if (target.destination != TapDestination.campaign) {
      trackPushEvent(PushEvent.opened, m.raw); // tracked pushes only
    }
    switch (target.destination) {
      case TapDestination.campaign:
        CampaignPush.open(m);
        return true;
      case TapDestination.ongoingCall:
        // The logic routes a live call to /call (never over itself).
        await CallSignals.onAppResumed();
        return true;
      case TapDestination.incomingCall:
        // The logic drops a stale or ended invite.
        await CallSignals.onInvite(
          m.raw,
          foreground: true,
          source: CallPushSource.notificationTap,
        );
        return true;
      case TapDestination.callback:
        // Home first: a sheet shown before that navigation would be
        // dropped with the page it sat on.
        DeepLinks.instance.queueRoute(AppRoutes.home);
        CallSignals.onCallbackRequest(m.raw);
        return true;
      case TapDestination.hostProfile:
        // The id first, then Home: the profile sheet is opened by the Home shell
        // watching DeepLinks.openUser, so setting it before navigating is what
        // makes the sheet appear with the page rather than after it.
        DeepLinks.instance.setOpenUser(target.location!);
        DeepLinks.instance.queueRoute(AppRoutes.home);
        return true;
      case TapDestination.wallet:
        await WalletNotifications.requestRefresh(background: false);
        DeepLinks.instance.queueRoute(target.location!);
        return true;
      case TapDestination.callHistory:
      case TapDestination.verification:
      case TapDestination.referral:
      case TapDestination.route:
        DeepLinks.instance.queueRoute(target.location!);
        return true;
      case TapDestination.link:
        await DeepLinks.instance.handle(target.location!, fromPush: true);
        return true;
      case TapDestination.none:
        return false;
    }
  }

  @visibleForTesting
  static void debugReset() {
    _lastKey = null;
    _lastAt = null;
  }
}
