import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/callscreen/helper/push/call_push_classifier.dart';
import 'package:vibelive/app/callscreen/helper/push/push_classifier.dart';
import 'package:vibelive/app/callscreen/helper/push/push_envelope.dart';
import 'package:vibelive/app/callscreen/helper/push/wallet_notifications.dart';

PushEnvelope env(
  Map<String, Object?> data, {
  String? title,
  String? body,
  bool notification = false,
}) => PushEnvelope.fromMap(
  {
    for (final e in data.entries)
      if (e.value != null) e.key: e.value,
  },
  title: title,
  body: body,
  hasNotification: notification,
);

CallPushKind kind(Map<String, Object?> data) =>
    CallPushClassifier.classify(env(data));

PushKind top(Map<String, Object?> data, {String? title, String? body}) =>
    PushClassifier.classify(env(data, title: title, body: body));

/// A genuine ring's join credentials (backend P1).
const join = {'channelName': 'call_7_9_1729500000000', 'token': '006abc'};

/// Backend payloads, spec_call_native Appendix A / spec_call_logic §B.4.
final invite = <String, Object?>{
  'type': 'voiceCall',
  'timestamp': '1729500000000',
  'callerName': 'Sharad Singh',
  'channelName': 'call_7_9_1729500000000',
  'roomId': 'call_7_9_1729500000000',
  'category': '12',
  'categoryName': 'Astrology',
  'token': '006abc+def',
  'callerId': '7',
  'receiverId': '9',
  'callId': '8500',
  'receiverDocID': 'rdoc',
  'calleridDocID': 'cdoc',
  'ProfilePic': 'https://cdn.test/p.png',
  'role': 'Client',
  'is_company_account': 'false',
};

void main() {
  group('backend payloads (Appendix A)', () {
    test('P1 FCM invite (voice + video) is a call invite', () {
      expect(top(invite), PushKind.call);
      expect(kind(invite), CallPushKind.invite);
      expect(kind({...invite, 'type': 'videoCall'}), CallPushKind.invite);
    });

    test('P2 VoIP invite (uuid = channelName, hasVideo "0") is an invite', () {
      final voip = {
        ...invite,
        'uuid': invite['channelName'],
        'handle': 'Sharad+Singh',
        'hasVideo': '0',
      };
      expect(top(voip), PushKind.call);
      expect(kind(voip), CallPushKind.invite);
    });

    test('CALL_RINGING / CALL_RINGING_LEGACY are caller-side, never rings', () {
      for (final type in ['CALL_RINGING', 'CALL_RINGING_LEGACY']) {
        final d = {
          'type': type,
          'callId': '8500',
          'callerId': '7',
          'receiverId': '9',
          'channelName': 'call_7_9_1',
        };
        expect(top(d), PushKind.call);
        expect(kind(d), CallPushKind.remoteRinging, reason: type);
      }
    });

    test(
      'CallTimer (notification + data) is ongoing: no ring, no teardown',
      () {
        final d = {
          'type': 'CallTimer',
          'callerName': 'Sharad',
          'category': '',
          'callerId': '7',
          'receiverId': '9',
          'callId': '8500',
          'receiverDocID': 'Null',
          'calleridDocID': 'cdoc',
          'ProfilePic': '',
        };
        expect(top(d), PushKind.call);
        expect(kind(d), CallPushKind.ongoing);
      },
    );

    test('CALL_ANSWERED_ELSEWHERE wins over its dismissNotification', () {
      final d = {
        'type': 'CALL_ANSWERED_ELSEWHERE',
        'callId': '8500',
        'dismissNotification': 'true',
      };
      expect(top(d), PushKind.call);
      expect(kind(d), CallPushKind.answeredElsewhere);
    });

    test('CALL_ENDED in every variant is ended', () {
      for (final status in [
        null,
        'missed',
        'declined',
        'force_complete_by_admin',
      ]) {
        final d = {
          'type': 'CALL_ENDED',
          'callId': '8500',
          'dismissNotification': 'true',
          'status': status,
        };
        expect(top(d), PushKind.call);
        expect(kind(d), CallPushKind.ended, reason: '$status');
      }
    });

    test('MISSED_CALL_HISTORY is a record, not an end', () {
      final d = {
        'type': 'MISSED_CALL_HISTORY',
        'callId': '8500',
        'ProfilePic': '',
        'categoryName': 'Astrology',
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        'status': 'missed',
      };
      expect(top(d), PushKind.call);
      expect(kind(d), CallPushKind.missedHistory);
    });

    test('PING_CLIENT (FCM and VoIP) is a callback request', () {
      final fcm = {
        'type': 'PING_CLIENT',
        'expertName': 'Asha',
        'expertId': '11',
        'expertDocId': 'edoc',
        'expertPic': '',
        'ProfilePic': '',
        'categoryName': 'Tarot',
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      };
      final voip = {
        'uuid': 'ping_11_9_abc123',
        'type': 'PING_CLIENT',
        'callerName': 'Asha',
        'handle': 'Asha',
        'handleType': 'generic',
        'hasVideo': '0',
        'expertName': 'Asha',
        'expertId': '11',
        'expertDocId': 'edoc',
        'expertPic': '',
        'status': 'ping',
      };
      for (final d in [fcm, voip]) {
        expect(top(d), PushKind.call);
        expect(kind(d), CallPushKind.pingClient);
      }
    });

    test('EXPERT_PRESENCE_PROBE (FCM and VoIP) is a heartbeat', () {
      expect(
        top({
          'type': 'EXPERT_PRESENCE_PROBE',
          'triggerHeartbeat': 'true',
          'timestamp': '1',
        }),
        PushKind.heartbeat,
      );
      expect(
        top({
          'type': 'EXPERT_PRESENCE_PROBE',
          'triggerHeartbeat': 'true',
          'timestamp': '1',
          'status': 'presence_probe',
        }),
        PushKind.heartbeat,
      );
    });

    test('low balance and document pushes reach the call flow as "other"', () {
      for (final type in [
        'LOW_BALANCE_WARNING',
        'CALL_ENDED_LOW_BALANCE',
        'CALL_DOC_UPLOAD_ENABLED',
        'CALL_DOC_UPLOADED',
      ]) {
        final d = {'type': type, 'callId': '8500', 'channelName': 'c'};
        expect(top(d), PushKind.call, reason: type);
        expect(kind(d), CallPushKind.other, reason: type);
      }
    });

    test('wallet transfer debit / credit are wallet pushes', () {
      for (final dir in ['debit', 'credit']) {
        final d = {
          'type': 'wallet_transfer_$dir',
          'direction': dir,
          'transactionId': '1',
          'fromWalletId': '2',
          'toWalletId': '3',
          'amount': '30',
          'balance': '100',
          'method': 'walletTowallet',
        };
        expect(top(d), PushKind.wallet);
        expect(WalletClassifier.classify(env(d)), WalletPushKind.transfer);
      }
    });

    test('CONNECTIVITY_CHECK is nothing to draw', () {
      expect(
        top({'type': 'CONNECTIVITY_CHECK', 'timestamp': '1'}),
        PushKind.general,
      );
    });
  });

  group('top-level gate', () {
    test('a payment with status "completed" is never a call end', () {
      expect(
        top({'type': 'payment', 'status': 'completed'}),
        isNot(PushKind.call),
      );
    });

    test('generic words need a call id first (referral "invite")', () {
      for (final type in ['invite', 'update', 'end', 'accepted', 'ringing']) {
        expect(
          PushClassifier.isCall(env({'type': type})),
          isFalse,
          reason: type,
        );
        expect(
          PushClassifier.isCall(env({'type': type, 'callId': '1'})),
          isTrue,
          reason: type,
        );
      }
    });

    test('every call-specific type is call-like on its own', () {
      for (final type in CallPushTokens.allTypes) {
        expect(
          PushClassifier.isCall(env({'type': type})),
          isTrue,
          reason: type,
        );
      }
    });

    test('call-like signals, dismiss flag, ongoing flag, join creds', () {
      expect(PushClassifier.isCall(env({'action': 'call_ended'})), isTrue);
      expect(
        PushClassifier.isCall(env({'dismissNotification': 'true'})),
        isTrue,
      );
      expect(PushClassifier.isCall(env({'__isOngoingCall': 'true'})), isTrue);
      expect(PushClassifier.isCall(env({...join})), isTrue);
    });

    test('a wallet push carrying a call id stays a wallet push', () {
      final d = {'type': 'wallet', 'callId': '8500', 'balance': '10'};
      expect(PushClassifier.isCall(env(d)), isFalse);
      expect(top(d), PushKind.wallet);
    });

    test('heartbeat spellings', () {
      for (final d in <Map<String, Object?>>[
        {'type': 'heartbeat'},
        {'type': 'ping'},
        {'heartbeat': 'true'},
        {'triggerHeartbeat': 'true'},
        {'action': 'EXPERT_PRESENCE_PROBE'},
      ]) {
        expect(top(d), PushKind.heartbeat, reason: '$d');
      }
    });

    test('campaign: deeplink / tracking id / marker, never call-like', () {
      expect(top({'deeplink': 'vibecalling://wallet'}), PushKind.campaign);
      expect(top({'notificationTrackingId': 't'}), PushKind.campaign);
      expect(top({'trackingId': 't'}), PushKind.campaign);
      expect(top({'__vibePush': '1'}), PushKind.campaign);
      expect(
        top({'deeplink': 'vibecalling://home', 'callId': '1'}),
        PushKind.call,
      );
      expect(
        PushClassifier.isCampaign(
          env({'deeplink': 'x', 'type': 'PRESENCE_UPDATE'}),
        ),
        isFalse,
      );
      // A top-up keeps its coin-sound notification.
      expect(
        top({'deeplink': 'vibecalling://wallet', 'type': 'wallet_topup'}),
        PushKind.wallet,
      );
    });

    test('"Your wallet is low" campaign is a campaign, not a wallet push', () {
      expect(
        top(
          {
            'deeplink': 'vibecalling://expert-profile.php?userid=abc',
            'notificationTrackingId': 't-1',
          },
          title: 'Your wallet is low',
          body: 'Top up your balance now',
        ),
        PushKind.campaign,
      );
    });

    test('milestone, verification, general', () {
      expect(top({'type': 'milestone_unlocked'}), PushKind.milestone);
      expect(top({'type': 'EXPERT_PROFILE_APPROVED'}), PushKind.verification);
      expect(
        top({}, title: 'Host Profile', body: 'Your profile is now live'),
        PushKind.verification,
      );
      expect(top({}, title: 'Hello', body: 'News'), PushKind.general);
    });
  });

  group('call kinds: every token row (spec §4.3)', () {
    Map<String, Object?> call(Map<String, Object?> d) => {'callId': '1', ...d};

    test('answered elsewhere: type, signal or status; beats dismiss', () {
      for (final t in CallPushTokens.elsewhere) {
        for (final field in ['type', 'action', 'event', 'status']) {
          expect(
            kind(call({field: t.toUpperCase(), 'dismissNotification': 'true'})),
            CallPushKind.answeredElsewhere,
            reason: '$field=$t',
          );
        }
      }
    });

    test('missed history (type only)', () {
      for (final t in CallPushTokens.missedHistory) {
        expect(kind(call({'type': t})), CallPushKind.missedHistory, reason: t);
      }
    });

    test('ended: type, signal, status, ended statuses, dismiss flag', () {
      for (final t in CallPushTokens.ended) {
        for (final field in ['type', 'action', 'eventType', 'callStatus']) {
          expect(
            kind(call({field: t})),
            CallPushKind.ended,
            reason: '$field=$t',
          );
        }
      }
      for (final s in CallPushTokens.endedStatus) {
        expect(kind(call({'status': s})), CallPushKind.ended, reason: s);
      }
      expect(kind(call({'dismissNotification': 'true'})), CallPushKind.ended);
    });

    test('remote ringing (caller side)', () {
      for (final t in CallPushTokens.remoteRinging) {
        for (final field in ['type', 'action', 'status']) {
          expect(
            kind(call({field: t, ...join})),
            CallPushKind.remoteRinging,
            reason: '$field=$t',
          );
        }
      }
    });

    test('ongoing: tokens and flags, even with join credentials', () {
      for (final t in CallPushTokens.ongoing) {
        for (final field in ['type', 'action', 'status']) {
          expect(
            kind(call({field: t, ...join})),
            CallPushKind.ongoing,
            reason: '$field=$t',
          );
        }
      }
      expect(
        kind(call({'__isOngoingCall': 'true', ...join})),
        CallPushKind.ongoing,
      );
      expect(kind(call({'isOngoing': 'true'})), CallPushKind.ongoing);
    });

    test('invite: needs join credentials AND an invite type / signal', () {
      for (final t in CallPushTokens.invite) {
        expect(
          kind(call({'type': t, ...join})),
          CallPushKind.invite,
          reason: t,
        );
        expect(
          kind(call({'type': t})),
          CallPushKind.other,
          reason: '$t no creds',
        );
      }
      for (final s in CallPushTokens.inviteSignals) {
        expect(
          kind(call({'type': 'whatever', 'event': s, ...join})),
          CallPushKind.invite,
          reason: s,
        );
      }
      expect(kind(call({...join})), CallPushKind.invite, reason: 'untyped');
      expect(kind(call({'type': 'call', ...join})), CallPushKind.invite);
      expect(kind(call({'type': 'mystery', ...join})), CallPushKind.other);
      expect(
        kind({'type': 'voiceCall', ...join}),
        CallPushKind.other,
        reason: 'no call id',
      );
      expect(
        kind(call({'type': 'voiceCall', 'roomId': 'r', 'receiverToken': 't'})),
        CallPushKind.invite,
        reason: 'alias keys',
      );
    });

    test('other tokens', () {
      expect(kind(call({'type': 'ping_client'})), CallPushKind.pingClient);
      for (final t in CallPushTokens.other.where((t) => t != 'ping_client')) {
        expect(kind(call({'type': t})), CallPushKind.other, reason: t);
      }
    });

    test('category is never read (the backend puts an id there)', () {
      expect(
        kind(call({'type': 'voiceCall', 'category': 'call_ended', ...join})),
        CallPushKind.invite,
      );
    });
  });

  group('tap helpers + envelope', () {
    test('ongoing and missed taps', () {
      expect(
        CallPushClassifier.isOngoingTap(
          env({'callId': '1'}, title: 'Ongoing Call'),
        ),
        isTrue,
      );
      expect(
        CallPushClassifier.isOngoingTap(env({'type': 'CallTimer'})),
        isTrue,
      );
      expect(CallPushClassifier.isMissedTap(env({'status': 'missed'})), isTrue);
    });

    test('timestamps: ms kept, seconds promoted, missing = unknown', () {
      expect(
        PushEnvelope.timestampOf({'timestamp': '1729500000000'}),
        DateTime.fromMillisecondsSinceEpoch(1729500000000),
      );
      expect(
        PushEnvelope.timestampOf({'ts': '1729500000'}),
        DateTime.fromMillisecondsSinceEpoch(1729500000000),
      );
      expect(PushEnvelope.timestampOf({}), isNull);
    });

    test('payload round trip keeps data, title and the notification id', () {
      final m = env({
        'type': 'wallet_topup',
        'n': 1,
      }, title: 'T').copyWith(notificationId: 'wallet_topup_latest');
      final back = PushEnvelope.fromPayload(m.toPayload())!;
      expect(back.data, {'type': 'wallet_topup', 'n': '1'});
      expect(back.title, 'T');
      expect(back.notificationId, 'wallet_topup_latest');
    });
  });

  test(
    'an admin banner or settings change is silent, never a notification',
    () {
      expect(
        top({'type': 'BANNERS_UPDATED', 'reason': 'banner_updated', 'at': '1'}),
        PushKind.appUpdate,
      );
      expect(
        top({'type': 'CONFIG_UPDATED', 'reason': 'host_media'}),
        PushKind.appUpdate,
      );
      expect(top({'type': 'banner'}), PushKind.general);
    },
  );
}
