import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/callscreen/helper/push/notification_tap_router.dart';
import 'package:vibelive/app/callscreen/helper/push/push_envelope.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/storage/app_prefs.dart';

PushEnvelope env(
  Map<String, Object?> data, {
  String? title,
  String? body,
  String? notificationId,
  String? messageId,
}) => PushEnvelope.fromMap(
  {
    for (final e in data.entries)
      if (e.value != null) e.key: e.value,
  },
  title: title,
  body: body,
  messageId: messageId,
).copyWith(notificationId: notificationId);

TapTarget route(
  Map<String, Object?> data, {
  String? title,
  String? body,
  String? notificationId,
}) => NotificationTapRouter.route(
  env(data, title: title, body: body, notificationId: notificationId),
);

void main() {
  setUpAll(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await AppPrefs.init();
  });

  group('tap routing order (spec §4.7)', () {
    test('a campaign titled "Your wallet is low" opens the campaign', () {
      expect(
        route(
          {
            'deeplink': 'vibecalling://expert-profile.php?userid=abc',
            'notificationTrackingId': 't-1',
          },
          title: 'Your wallet is low',
          body: 'Recharge your balance and talk to experts',
        ),
        const TapTarget(TapDestination.campaign),
      );
    });

    test('a campaign mentioning verification still opens the campaign', () {
      expect(
        route(
          {'trackingId': 's-1', 'deeplink': 'vibecalling://home'},
          title: 'Get verified',
          body: 'Your verification badge awaits',
        ).destination,
        TapDestination.campaign,
      );
    });

    test('call-like taps: ongoing, missed, ping, invite, others ignored', () {
      expect(
        route({'callId': '1', 'type': 'CallTimer'}, title: 'Ongoing Call'),
        const TapTarget(TapDestination.ongoingCall),
      );
      expect(
        route({'callId': '1', 'type': 'MISSED_CALL_HISTORY'}),
        const TapTarget(TapDestination.callHistory, AppRoutes.explore),
      );
      expect(
        route({'callId': '1', 'type': 'CALL_ENDED', 'status': 'missed'}),
        const TapTarget(TapDestination.callHistory, AppRoutes.explore),
      );
      expect(
        route({'type': 'PING_CLIENT', 'expertDocId': 'e'}).destination,
        TapDestination.callback,
      );
      expect(
        route({
          'type': 'voiceCall',
          'callId': '1',
          'channelName': 'c',
          'token': 't',
        }).destination,
        TapDestination.incomingCall,
      );
      expect(
        route({
          'type': 'CALL_ENDED',
          'callId': '1',
          'dismissNotification': 'true',
        }).destination,
        TapDestination.none,
      );
    });

    test('wallet: our notification ids and explicit types', () {
      expect(
        route({}, notificationId: 'wallet_topup_latest').destination,
        TapDestination.wallet,
      );
      expect(
        route({}, notificationId: 'wallet_transfer_credit_1').destination,
        TapDestination.wallet,
      );
      expect(
        route({'type': 'wallet_transfer_debit', 'direction': 'debit'}),
        const TapTarget(TapDestination.wallet, AppRoutes.wallet),
      );
      expect(
        route({'type': 'money_received'}).destination,
        TapDestination.wallet,
      );
    });

    test('an explicit verification type beats a wallet keyword', () {
      expect(
        route(
          {'type': 'expert_profile_approved'},
          title: 'Approved',
          body: 'Your payment of the badge fee was received, wallet updated',
        ),
        const TapTarget(TapDestination.verification, AppRoutes.personalInfo),
      );
    });

    test('keyword fallbacks: wallet first, then verification', () {
      expect(
        route(
          {},
          title: 'Low balance',
          body: 'Your wallet balance is low',
        ).destination,
        TapDestination.wallet,
      );
      expect(
        route(
          {},
          title: 'Great news',
          body: 'Your profile is now live',
        ).destination,
        TapDestination.verification,
      );
    });

    test('referral, explicit route, link, nothing', () {
      expect(
        route({'type': 'referral'}),
        const TapTarget(TapDestination.referral, AppRoutes.referral),
      );
      expect(
        route({'route': '/me/favourites'}),
        const TapTarget(TapDestination.route, '/me/favourites'),
      );
      expect(
        route({'url': 'https://vibelive.angrymamba.com/abc'}),
        const TapTarget(
          TapDestination.link,
          'https://vibelive.angrymamba.com/abc',
        ),
      );
      expect(route({}, title: 'Hi').destination, TapDestination.none);
    });
  });

  group('duplicate taps', () {
    setUp(NotificationTapRouter.debugReset);

    test('the same tap twice within 2 s opens once', () async {
      final now = DateTime(2026, 10, 21, 12);
      final m = env({'type': 'wallet_topup'}, messageId: 'm-1');
      expect(await NotificationTapRouter.handle(m, now: now), isTrue);
      expect(
        await NotificationTapRouter.handle(
          m,
          now: now.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(
        await NotificationTapRouter.handle(
          m,
          now: now.add(const Duration(seconds: 3)),
        ),
        isTrue,
      );
    });

    test('keys: tracking id + deeplink, else message id, else our id', () {
      expect(
        NotificationTapRouter.tapKey(
          env({'trackingId': 't', 'deeplink': 'vibecalling://home'}),
        ),
        't|vibecalling://home',
      );
      expect(NotificationTapRouter.tapKey(env({}, messageId: 'm')), 'm');
      expect(NotificationTapRouter.tapKey(env({}, notificationId: 'n')), 'n');
      expect(NotificationTapRouter.tapKey(env({})), isNull);
    });
  });

  group('host came online', () {
    test('a host-online nudge opens that host profile', () {
      final t = route({
        'type': 'HOST_ONLINE',
        'openUserId': 'usr_abc',
        'expertProfileId': '42',
      });
      expect(t.destination, TapDestination.hostProfile);
      expect(t.location, 'usr_abc');
    });

    test('the type is matched case-insensitively, as the envelope lowercases it', () {
      final t = route({'type': 'host_online', 'openUserId': 'usr_abc'});
      expect(t.destination, TapDestination.hostProfile);
    });

    test('a nudge with no openUserId has nothing to open', () {
      // Better to fall through than to navigate somewhere arbitrary: the whole
      // point of the nudge is the specific host.
      final t = route({'type': 'HOST_ONLINE'});
      expect(t.destination, isNot(TapDestination.hostProfile));
    });

    test('an empty openUserId is treated as absent', () {
      final t = route({'type': 'HOST_ONLINE', 'openUserId': '   '});
      expect(t.destination, isNot(TapDestination.hostProfile));
    });

    test('a live call still wins over a nudge', () {
      // A ringing or ongoing call is the more urgent thing on the device.
      final t = route({
        'type': 'HOST_ONLINE',
        'openUserId': 'usr_abc',
        'callId': '7',
        'callStatus': 'ongoing',
      });
      expect(t.destination, isNot(TapDestination.hostProfile));
    });
  });
}
