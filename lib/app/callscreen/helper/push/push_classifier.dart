import 'app_update_push.dart';
import '../../../api/authscreen/push_queries.dart';
import 'call_push_classifier.dart';
import 'push_envelope.dart';
import 'verification_notifications.dart';
import 'wallet_notifications.dart';

/// Which module owns a push.
enum PushKind {
  heartbeat,
  call,
  campaign,
  milestone,
  wallet,
  verification,

  /// A silent "banners / settings changed" (admin): reload, never shown.
  appUpdate,
  general,
}

/// Top-level push classifier. Order: heartbeat → call → campaign →
/// milestone → wallet → verification → general (spec_call_native §4.3).
abstract final class PushClassifier {
  static PushKind classify(PushEnvelope m) {
    if (isHeartbeat(m)) return PushKind.heartbeat;
    if (isCall(m)) return PushKind.call;
    if (AppUpdatePush.matches(m.type)) return PushKind.appUpdate;
    if (isCampaign(m)) return PushKind.campaign;
    if (m.type == 'milestone_unlocked') return PushKind.milestone;
    if (WalletClassifier.isWallet(m)) return PushKind.wallet;
    if (VerificationNotifications.matches(m)) return PushKind.verification;
    return PushKind.general;
  }

  /// RN probe check + CE `isHeartbeat`.
  static bool isHeartbeat(PushEnvelope m) =>
      m.type == 'expert_presence_probe' ||
      m.type == 'heartbeat' ||
      m.type == 'ping' ||
      m.data['triggerHeartbeat'] == 'true' ||
      m.data['heartbeat'] == 'true' ||
      (m.data['action'] ?? '').toLowerCase() == 'expert_presence_probe';

  /// The call-like gate: only these ever reach the call classifier (a payment
  /// push with status "completed" must never read as a call end).
  static bool isCall(PushEnvelope m) {
    final d = m.data;
    if (m.flag('__isOngoingCall')) return true;
    if (CallPushTokens.allTypes.contains(m.type)) return true;
    if (CallPushTokens.allSignals.contains(m.signal)) return true;
    if (m.flag('dismissNotification')) return true;
    if ((d['channelName'] ?? '').isNotEmpty &&
        ((d['token'] ?? '').isNotEmpty ||
            (d['receiverToken'] ?? '').isNotEmpty)) {
      return true;
    }
    if (m.callId != null && !WalletClassifier.isWalletLike(m)) return true;
    return false;
  }

  /// RN `isCampaignPush`: owned by the campaign handler. The legacy keyword
  /// matchers (wallet "wallet" / "balance", verification) must skip these, or
  /// a campaign is double-navigated (campaign memory).
  static bool isCampaign(PushEnvelope m) {
    final d = m.data;
    if ((d['deeplink'] ?? '').isEmpty &&
        pushTrackingIdOf(d) == null &&
        d['__vibePush'] != '1') {
      return false;
    }
    if (d['callId'] != null ||
        d['call_id'] != null ||
        d['CallId'] != null ||
        d['__isOngoingCall'] != null) {
      return false;
    }
    if (RegExp(
      r'call|ringing|presence|ping_client',
      caseSensitive: false,
    ).hasMatch(d['type'] ?? '')) {
      return false;
    }
    // Wallet transfers / top-ups keep their own coin-sound notification.
    if (WalletClassifier.matchesTransferTrigger(m)) return false;
    return true;
  }
}
