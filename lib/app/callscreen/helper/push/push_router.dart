import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/analytics/events/app_events.dart';
import '../../../../core/utils/log.dart';
import '../../../api/authscreen/push_api.dart';
import '../../../api/authscreen/push_queries.dart';
import '../call_controller.dart';
import '../call_signals.dart';
import 'app_update_push.dart';
import 'call_push_handler.dart';
import 'campaign_push.dart';
import 'heartbeat_handler.dart';
import 'local_notifier.dart';
import 'milestone_queue.dart';
import 'notification_channels.dart';
import 'push_classifier.dart';
import 'push_dedupe.dart';
import 'push_envelope.dart';
import 'push_session.dart';
import 'push_strings.dart';
import 'verification_notifications.dart';
import 'wallet_notifications.dart';

/// Decides what an incoming FCM data message does (spec_call_native §4.4,
/// §4.5). Never navigates: only taps do (`NotificationTapRouter`). Never
/// throws.
abstract final class PushRouter {
  static const _tag = 'PushRouter';

  /// `FirebaseMessaging.onMessage` (UI isolate, app in front).
  static Future<void> handleForeground(RemoteMessage message) async {
    try {
      await _foreground(PushEnvelope.fromRemote(message));
    } catch (e, st) {
      Log.e(_tag, e, st);
    }
  }

  /// `onBackgroundMessage`, in its own isolate (killed / backgrounded).
  /// [prepare] readies the isolate (local notifications, call background
  /// handler); injected so this file stays free of the native layer.
  static Future<void> handleBackground(
    RemoteMessage message, {
    Future<void> Function()? prepare,
  }) async {
    try {
      await LocalNotifier.init();
      await NotificationChannels.ensure(LocalNotifier.plugin);
      await prepare?.call();
      await _background(
        PushEnvelope.fromRemote(message),
        alreadyShownByOs: message.notification != null,
      );
    } catch (e, st) {
      Log.e(_tag, e, st);
    }
  }

  static Future<void> _foreground(PushEnvelope m) async {
    trackPushEvent(PushEvent.delivered, m.raw);
    if (await PushDedupe.isDuplicate(m)) return;
    final kind = PushClassifier.classify(m);
    Log.d(_tag, 'foreground ${kind.name} type=${m.type}');
    switch (kind) {
      case PushKind.heartbeat:
        await HeartbeatHandler.send(via: 'foreground_push');
        return;
      case PushKind.appUpdate:
        AppUpdatePush.onUpdate(m.type);
        return;
      case PushKind.call:
        await CallPushHandler.handle(
          m,
          source: CallPushSource.fcm,
          foreground: _appInFront(),
        );
        return;
      default:
        break;
    }
    _logReceived(kind, m, foreground: true);
    // Nothing is drawn over a live call (CE); a wallet screen under it still
    // gets its refresh.
    if (CallController.instance.isOnCall) {
      if (kind == PushKind.wallet) {
        await WalletNotifications.requestRefresh(background: false);
      }
      return;
    }
    if (kind == PushKind.milestone) {
      MilestoneQueue.addFromPush(m.raw);
      return;
    }
    if (!PushSession.isSignedIn || PushDedupe.isTooOld(m)) return;
    await PushStrings.ensure();
    await _draw(kind, m, background: false);
  }

  static Future<void> _background(
    PushEnvelope m, {
    required bool alreadyShownByOs,
  }) async {
    trackPushEvent(PushEvent.delivered, m.raw);
    if (await PushDedupe.isDuplicate(m)) return;
    final kind = PushClassifier.classify(m);
    Log.d(_tag, 'background ${kind.name} type=${m.type}');
    switch (kind) {
      case PushKind.heartbeat:
        await HeartbeatHandler.send(via: 'background_push');
        return;
      // Silent: the app reloads all of it when it comes back to the front.
      case PushKind.appUpdate:
        return;
      case PushKind.call:
        // iOS: data-only FCM rarely reaches here, and never rings (VoIP owns
        // ringing). Android: the ringer is shown from here.
        await CallPushHandler.handle(
          m,
          source: CallPushSource.fcm,
          foreground: false,
          background: true,
        );
        return;
      default:
        break;
    }
    _logReceived(kind, m, foreground: false);
    if (alreadyShownByOs) {
      // Never redraw what the OS drew; the balance is still stale.
      if (kind == PushKind.wallet) {
        await WalletNotifications.requestRefresh(background: true);
      }
      return;
    }
    if (!PushSession.isSignedIn || PushDedupe.isTooOld(m)) return;
    await PushStrings.ensure();
    await _draw(kind, m, background: true);
  }

  /// Analytics: a non-call push arrived (calls: CallAnalytics).
  static void _logReceived(
    PushKind kind,
    PushEnvelope m, {
    required bool foreground,
  }) => AppEvents.pushReceived(
    kind: kind.name,
    type: m.type,
    campaignId: AppEvents.campaignIdOf(m.data),
    foreground: foreground,
    hasDeeplink: m.deeplink != null,
  );

  static Future<void> _draw(
    PushKind kind,
    PushEnvelope m, {
    required bool background,
  }) async {
    final drawn = switch (kind) {
      PushKind.heartbeat || PushKind.call => false,
      PushKind.general ||
      PushKind.milestone => m.title != null || m.body != null,
      _ => true,
    };
    if (drawn) {
      AppEvents.pushShown(
        kind: kind.name,
        type: m.type,
        campaignId: AppEvents.campaignIdOf(m.data),
        background: background,
      );
    }
    switch (kind) {
      case PushKind.campaign:
        await CampaignPush.present(m);
      case PushKind.wallet:
        await WalletNotifications.present(m, background: background);
      case PushKind.verification:
        await VerificationNotifications.present(m);
      case PushKind.general:
      case PushKind.milestone:
        if (m.title == null && m.body == null) return;
        final id =
            'general_${m.messageId ?? DateTime.now().millisecondsSinceEpoch}';
        await LocalNotifier.show(
          id: id,
          title: m.title ?? PushStrings.appName,
          body: m.body,
          envelope: m,
          channelId: NotificationChannels.general,
        );
      case PushKind.heartbeat:
      case PushKind.call:
      case PushKind.appUpdate:
        return;
    }
  }

  /// onMessage does not imply the app is in front: on Android a message
  /// during a lifecycle transition (screen locking) must still ring
  /// natively, and on iOS `.inactive` (CallKit UI up, unlocking, the app
  /// switcher) already has CallKit ringing for the same call, so the in-app
  /// screen must not ring on top of it. Only `resumed` is in front.
  static bool _appInFront() {
    try {
      final state = WidgetsBinding.instance.lifecycleState;
      return state == null || state == AppLifecycleState.resumed;
    } catch (_) {
      return true;
    }
  }
}
