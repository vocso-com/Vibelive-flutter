import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/api/chat/chat_queries.dart';
import 'package:vibelive/app/api/listingflow/listing_models.dart';
import 'package:vibelive/app/callscreen/helper/push/app_update_push.dart';
import 'package:vibelive/app/callscreen/helper/push/chat_push.dart';
import 'package:vibelive/app/callscreen/helper/push/push_envelope.dart';
import 'package:vibelive/app/callscreen/helper/push/notification_tap_router.dart';
import 'package:vibelive/app/chatscreen/components/message_bubble.dart';
import 'package:vibelive/app/chatscreen/conversation/chat_screen.dart';
import 'package:vibelive/app/chatscreen/conversation/private_photo_viewer.dart';
import 'package:vibelive/app/chatscreen/helper/chat_outbox.dart';
import 'package:vibelive/app/chatscreen/helper/chat_screen_guard.dart';
import 'package:vibelive/app/chatscreen/list/chat_tab.dart';
import 'package:vibelive/app/chatscreen/list/chats_view.dart';
import 'package:vibelive/app/component/pressable.dart';
import 'package:vibelive/app/homescreen/home_screen.dart';
import 'package:vibelive/app/listingflow/profile/host_profile_sheet.dart';
import 'package:vibelive/app/listingflow/profile/profile_call_actions.dart';
import 'package:vibelive/app/navbar/bottombar/bottom_navbar.dart';
import 'package:vibelive/app/paymentscreen/wallet/wallet_screen.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/network/network_status.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/query/query_persist.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/theme_controller.dart';
import 'package:vibelive/core/utils/scale.dart';
import 'package:vibelive/main.dart';

import '../perf/perf_harness.dart';

/// A 1×1 PNG (the private photo's bytes).
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// The chat API (backend docs/chat_api.md §4) with switches for each case.
/// Me: user 1. The other person: host 7, conversation c1.
class _Backend implements HttpClientAdapter {
  /// `/chats/config`: an HTTP status, or `malformed` / `offline`.
  Object config = 200;
  bool hostTakesChats = true;
  bool offline = false;

  /// Company-only chat with someone who isn't a company account.
  bool notAvailable = false;
  bool sendNotAvailable = false;

  /// The next sends answer 500 / 402.
  int failNextSends = 0;
  bool lowBalanceNext = false;

  /// Server messages, newest first.
  final messages = <Map<String, Object?>>[];
  final sent = <Map<String, Object?>>[];
  final receipts = <Object?>[];
  final paths = <String>[];
  final messageReads = <Map<String, dynamic>>[];
  var unlocked = false;

  int _seq = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    paths.add('${o.method} ${o.path}');
    if (o.path == '/api/chats/config') {
      if (config == 'offline') throw _offline(o);
      if (config == 'malformed') {
        return ResponseBody.fromString('{not json', 200, headers: _json);
      }
      if (config == 'off') return _reply({'enabled': false}, 200);
      if (config != 200) {
        return _reply({
          'error': {'status': config, 'message': 'Not Found'},
        }, config as int);
      }
      return _reply({
        'enabled': true,
        'textPrice': 2,
        'imagePrice': 3,
        'voice': {
          'shortSec': 10,
          'shortPrice': 2,
          'longSec': 30,
          'longPrice': 4,
          'stepSec': 20,
          'stepPrice': 1,
          'maxSeconds': 120,
        },
        'minBalance': {'text': 0, 'image': 0, 'voice': 0},
        'maxMessageLength': 1000,
        'lowBalanceMessages': 10,
        'pollSeconds': 20,
        'screenshotProtection': true,
        'mediaMaxMb': 10,
        'hostMediaPercent': 50,
        'privatePhotos': {
          'enabled': true,
          'minPrice': 10,
          'maxPrice': 2000,
          'hostSharePercent': 70,
          'accessMinutes': 10,
          'viewSeconds': 300,
        },
      }, 200);
    }
    if (o.path == '/api/chats/messages/m9/photo') {
      return ResponseBody.fromBytes(
        _png,
        200,
        headers: {
          Headers.contentTypeHeader: ['image/png'],
        },
      );
    }
    final status = _status(o); // before the body counts the failure down
    return _reply(_body(o), status);
  }

  int _status(RequestOptions o) {
    if (o.method == 'POST' && o.path == '/api/chats/messages') {
      if (sendNotAvailable) return 403;
      if (lowBalanceNext) return 402;
      if (failNextSends > 0) return 500;
      return 201;
    }
    return 200;
  }

  Object _body(RequestOptions o) {
    final q = o.queryParameters;
    switch ('${o.method} ${o.path}') {
      case 'GET /api/chats/unread':
        return {'unreadTotal': 3};
      case 'GET /api/chats/conversations':
        return {
          'items': [
            {
              'id': 'c1',
              'mySide': 'payer',
              'peer': _peer,
              'lastMessage': {
                'type': 'text',
                'text': 'Hello there',
                'senderId': '7',
                'at': DateTime.now().toUtc().toIso8601String(),
              },
              'unread': 3,
              'updatedAt': DateTime.now().toUtc().toIso8601String(),
            },
          ],
          'unreadTotal': 3,
          'next': null,
        };
      case 'GET /api/chats/with/7':
        return {
          'conversationId': 'c1',
          'mySide': 'payer',
          'peer': _peer,
          'chatEnabled': hostTakesChats && !notAvailable,
          'reason': notAvailable ? 'CHAT_NOT_AVAILABLE' : null,
          'pricePerMessage': 2,
          'imagePrice': 3,
          'balance': 100,
        };
      case 'GET /api/chats/with/8':
        return {
          'conversationId': null,
          'mySide': 'payer',
          'peer': {..._peer, 'userId': '8', 'name': 'Meera'},
          'chatEnabled': true,
          'reason': null,
          'pricePerMessage': 2,
          'imagePrice': 3,
          'balance': 100,
        };
      case 'GET /api/chats/conversations/c1/messages':
        messageReads.add(Map.of(q));
        final after = q['after'];
        final items = after == null
            ? messages
            : messages.takeWhile((m) => m['id'] != after).toList();
        return {'items': items, 'hasMore': false};
      case 'POST /api/chats/conversations/c1/read':
        return {'ok': true};
      case 'POST /api/chats/messages':
        final body = Map<String, Object?>.from(o.data as Map);
        sent.add(body);
        if (offline) throw _offline(o);
        if (sendNotAvailable) {
          notAvailable = true;
          return {
            'error': {
              'status': 403,
              'name': 'ForbiddenError',
              'message': 'Chat is not available with this person',
              'details': {'code': 'CHAT_NOT_AVAILABLE'},
            },
          };
        }
        if (lowBalanceNext) {
          lowBalanceNext = false;
          return {
            'error': {
              'status': 402,
              'name': 'PaymentRequiredError',
              'message': 'Recharge your wallet to keep chatting',
              'details': {
                'code': 'CHAT_LOW_BALANCE',
                'required': 2,
                'balance': 0.5,
              },
            },
          };
        }
        if (failNextSends > 0) {
          failNextSends--;
          return {
            'error': {'status': 500, 'message': 'Internal Server Error'},
          };
        }
        final saved = _message(
          'm${100 + _seq++}',
          sender: '1',
          text: body['text'] as String?,
          clientId: body['clientId'] as String?,
        );
        messages.insert(0, saved);
        return {'message': saved, 'charged': 2, 'balance': 98};
      case 'POST /api/chats/messages/m9/unlock':
        unlocked = true;
        return {'message': _privatePhoto(unlocked: true), 'balance': 1};
      case 'POST /api/chats/receipts':
        receipts.addAll((o.data as Map)['receipts'] as List);
        return {'ok': true};
      case 'GET /api/chats/settings':
        return {'acceptChats': null, 'notify': true};
      case 'GET /api/wallets':
        return {
          'data': [
            {'id': 1, 'balance': 100},
          ],
        };
      default:
        return {'data': <Object>[]};
    }
  }

  static final _peer = {
    'userId': '7',
    'name': 'Priya',
    'avatar': null,
    'verified': true,
    'isHost': true,
    'online': true,
    'busy': false,
    'deleted': false,
  };

  static Map<String, Object?> _message(
    String id, {
    String sender = '7',
    String? text,
    String? clientId,
    DateTime? at,
  }) => {
    'id': id,
    'conversationId': 'c1',
    'senderId': sender,
    'type': 'text',
    'text': text ?? 'text $id',
    'clientId': clientId,
    'createdAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
  };

  static Map<String, Object?> _privatePhoto({bool unlocked = false}) => {
    'id': 'm9',
    'conversationId': 'c1',
    'senderId': '7',
    'type': 'private_image',
    'createdAt': DateTime.now()
        .subtract(const Duration(minutes: 1))
        .toUtc()
        .toIso8601String(),
    'private': {
      'price': 99,
      'preview': {'url': null, 'width': 300, 'height': 400},
      'unlocked': unlocked,
      'expiresAt': unlocked
          ? DateTime.now()
                .add(const Duration(minutes: 10))
                .toUtc()
                .toIso8601String()
          : null,
    },
  };

  static final _json = {
    Headers.contentTypeHeader: ['application/json'],
  };

  static ResponseBody _reply(Object body, int status) =>
      ResponseBody.fromString(jsonEncode(body), status, headers: _json);

  static DioException _offline(RequestOptions o) =>
      DioException(requestOptions: o, type: DioExceptionType.connectionError);

  @override
  void close({bool force = false}) {}
}

/// A full host row (rates + topics: the profile needs no further read).
Map<String, Object?> _host() => {
  'id': 7,
  'documentId': 'exp7',
  'handler': 'priya',
  'tagline': 'Let us talk',
  'isActive': true,
  'rates': {'videoCallRate': 30, 'voiceCallRate': 20},
  'service_area_selections': [
    {
      'snapshot': {
        'question': {'key': 'support_topic'},
        'option': {'label': 'Breakup', 'value': 'breakup'},
      },
    },
  ],
  'host_profile_images': <Object>[],
  'user': {'id': 7, 'documentId': 'usr7', 'name': 'Priya'},
};

Future<void> _pump(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late _Backend backend;

  setUpAll(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Vibe Live',
      packageName: 'com.angrymamba.vibelive',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await AppPrefs.init();
    ApiClient.dio.interceptors.removeWhere((i) => i is PrettyDioLogger);
  });

  setUp(() async {
    rootBundle.clear();
    queryCache.clear();
    await QueryPersist.clearAll();
    ChatAvailability.instance.value = false;
    ChatOutbox.instance.debugReset();
    ChatScreenGuard.instance.debugReset();
    NotificationTapRouter.debugReset();
    NetworkStatus.instance.value = true;
    ApiClient.dio.httpClientAdapter = backend = _Backend();
    await SessionStore.instance.signIn(
      user: {
        'id': 1,
        'documentId': 'u1',
        'name': 'Asha',
        'email': 'a@b.co',
        'mobile': '9999999999',
      },
      accessToken: 'access',
    );
  });

  Future<void> openApp(WidgetTester tester, {String? location}) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Scale.update(const Size(390, 844));
    await tester.pumpWidget(
      VibeLiveApp(
        themeController: ThemeController(ThemeMode.dark),
        localeController: LocaleController(const Locale('en')),
      ),
    );
    appRouter.go(AppRoutes.home);
    await _pump(tester, 600);
    if (location != null) {
      unawaited(appRouter.push(location));
      await _pump(tester, 800);
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  }

  Finder dockItems() => find.descendant(
    of: find.byType(BottomNavbar),
    matching: find.byType(Pressable),
  );

  Future<void> openProfile(WidgetTester tester) async {
    final context = tester.element(find.byType(HomeScreen));
    // ignore: use_build_context_synchronously
    unawaited(showHostProfile(context, HostCard.fromJson(_host())));
    await _pump(tester, 900);
  }

  group('chat not on the server (today\'s live backend)', () {
    for (final failure in <Object>[404, 403, 500, 'malformed', 'offline']) {
      testWidgets('config $failure: three dock tabs, no chat buttons, '
          'no toast', (tester) async {
        backend.config = failure;
        await openApp(tester);
        expect(dockItems(), findsNWidgets(3));
        expect(find.byType(ChatUnreadBadge), findsNothing);
        expect(find.byIcon(LucideIcons.messageCircle), findsNothing);
        expect(backend.paths, isNot(contains('GET /api/chats/unread')));

        await openProfile(tester);
        expect(find.byType(ProfileCallButton), findsWidgets);
        expect(find.byKey(const ValueKey('profile-chat-button')), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        await finish(tester);
      });
    }

    testWidgets('chat appears by itself once the server has it (resume)', (
      tester,
    ) async {
      backend.config = 404;
      await openApp(tester);
      expect(dockItems(), findsNWidgets(3));
      backend.config = 200;
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await _pump(tester, 600);
      expect(dockItems(), findsNWidgets(4));
      await finish(tester);
    });
  });

  testWidgets('chat on: a Chats tab with the unread badge; the list opens '
      'the chat', (tester) async {
    backend.messages.add(_Backend._message('m1', text: 'Hello there'));
    await openApp(tester);
    expect(dockItems(), findsNWidgets(4));
    expect(find.byKey(const ValueKey('chat-unread-badge')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chat-unread-badge')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavbar),
        matching: find.byIcon(LucideIcons.messageCircle),
      ),
    );
    await _pump(tester, 600);
    expect(find.byType(ChatsTopBar), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Hello there'), findsOneWidget);

    await tester.tap(find.text('Priya'));
    await _pump(tester, 900);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('Hello there'), findsWidgets);
    // Price before sending.
    expect(find.text('Message ₹2 · Photo ₹3 · Voice from ₹2'), findsOneWidget);
    expect(backend.paths, contains('POST /api/chats/conversations/c1/read'));
    await finish(tester);
  });

  testWidgets('the profile has a Chat button next to the calls', (
    tester,
  ) async {
    await openApp(tester);
    await openProfile(tester);
    expect(find.byKey(const ValueKey('profile-chat-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-chat-button')));
    await _pump(tester, 900);
    expect(find.byType(ChatScreen), findsOneWidget);
    await finish(tester);
  });

  testWidgets('sending: an optimistic bubble, saved with its clientId', (
    tester,
  ) async {
    await openApp(tester, location: AppRoutes.chatWith('7'));
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'Hi Priya',
    );
    await tester.pump();
    expect(find.text('₹2 to send this message'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pump();
    expect(find.text('Hi Priya'), findsOneWidget); // at once
    await _pump(tester, 400);
    expect(backend.sent, hasLength(1));
    expect(backend.sent.single['text'], 'Hi Priya');
    expect(backend.sent.single['clientId'], isA<String>());
    expect(find.text('Hi Priya'), findsOneWidget); // one bubble, now saved
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a failed send is retried with the same clientId', (
    tester,
  ) async {
    backend.failNextSends = 1;
    await openApp(tester, location: AppRoutes.chatWith('7'));
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'Are you there?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await _pump(tester, 400);
    expect(find.text('Not sent · tap to retry'), findsOneWidget);

    await tester.tap(find.text('Are you there?'));
    await _pump(tester, 400);
    await tester.tap(find.text('Send again'));
    await _pump(tester, 600);
    expect(backend.sent, hasLength(2));
    expect(backend.sent[1]['clientId'], backend.sent[0]['clientId']);
    expect(find.text('Not sent · tap to retry'), findsNothing);
    expect(find.text('Are you there?'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('402: the text goes back in the box; the app\'s wallet opens '
      'with the missing amount and "ready to send"', (tester) async {
    backend.lowBalanceNext = true;
    await openApp(tester, location: AppRoutes.chatWith('7'));
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'One more',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await _pump(tester, 800);
    expect(
      find.textContaining('Your message is ready to send.'),
      findsOneWidget,
    );
    expect(find.byType(WalletScreen), findsOneWidget);
    final wallet = tester.widget<WalletScreen>(find.byType(WalletScreen));
    // ₹2 needed, ₹0.50 there: the wallet's minimum top-up (₹20) instead.
    expect(wallet.prefillAmount, 20);

    // Back from the wallet (its add-money screen opens with the amount):
    // the chat, the text ready in the box.
    for (
      var i = 0;
      i < 3 && find.byType(WalletScreen).evaluate().isNotEmpty;
      i++
    ) {
      await rootNavigatorKey.currentState!.maybePop();
      await _pump(tester, 600);
    }
    expect(find.byType(ChatScreen), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-composer-field')),
    );
    expect(field.controller!.text, 'One more');
    // Nothing was saved: no failed bubble left behind.
    expect(find.text('Not sent · tap to retry'), findsNothing);
    await finish(tester);
  });

  testWidgets('a host with chats off: "Not taking chats right now", no '
      'composer', (tester) async {
    backend.hostTakesChats = false;
    await openApp(tester, location: AppRoutes.chatWith('7'));
    expect(find.text('Not taking chats right now'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-composer-field')), findsNothing);
    await finish(tester);
  });

  testWidgets('private photo: unlock, then the viewer holds the photo', (
    tester,
  ) async {
    backend.messages.add(_Backend._privatePhoto());
    await openApp(tester, location: AppRoutes.chatWith('7'));
    expect(find.text('Unlock · ₹99'), findsOneWidget);
    await tester.tap(find.text('Unlock · ₹99'));
    await _pump(tester, 500);
    expect(find.text('Unlock this photo?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-unlock-confirm')));
    await _pump(tester, 900);
    expect(backend.unlocked, isTrue);
    expect(find.byType(PrivatePhotoViewer), findsOneWidget);
    expect(backend.paths, contains('GET /api/chats/messages/m9/photo'));
    expect(find.byKey(const ValueKey('chat-viewer-left')), findsOneWidget);
    expect(ChatScreenGuard.instance.isSecure, isTrue);
    await tester.tap(find.bySemanticsLabel('Close'));
    await _pump(tester, 500);
    expect(find.byType(PrivatePhotoViewer), findsNothing);
    expect(find.text('Tap to view'), findsOneWidget);
    await finish(tester);
    // Every chat screen gone: protection cleared.
    expect(ChatScreenGuard.instance.isSecure, isFalse);
  });

  testWidgets('a push is a hint: the open chat reads what is new, the '
      'receipt is posted, nothing is drawn', (tester) async {
    backend.messages.add(_Backend._message('m2', text: 'First'));
    await openApp(tester, location: AppRoutes.chatWith('7'));
    expect(find.text('First'), findsOneWidget);
    backend.messages.insert(0, _Backend._message('m3', text: 'Second'));

    unawaited(
      ChatPush.onForeground(
        PushEnvelope.fromMap({
          'type': 'CHAT_MESSAGE',
          'conversationId': 'c1',
          'messageId': 'm3',
          'senderId': '7',
          'senderName': 'Priya',
          'messageType': 'text',
          'preview': 'Second',
          'receipt': 'm3.sig',
          'silent': '0',
        }),
      ),
    );
    await _pump(tester, 600);
    expect(find.text('Second'), findsOneWidget);
    expect(backend.messageReads.last['after'], 'm2');
    expect(backend.receipts, ['m3.sig']);
    await finish(tester);
  });

  group('a chat notification tap opens that person\'s chat', () {
    PushEnvelope tap(String sender, String id) => PushEnvelope.fromMap({
      'type': 'CHAT_MESSAGE',
      'conversationId': sender == '7' ? 'c1' : 'c$sender',
      'messageId': id,
      'senderId': sender,
      'senderName': 'Someone',
      'messageType': 'text',
      'preview': 'Hi',
      'receipt': '$id.sig',
      'silent': '0',
    });
    Finder chats() => find.byType(ChatScreen, skipOffstage: false);
    String here() =>
        appRouter.routerDelegate.currentConfiguration.last.matchedLocation;

    testWidgets('from Home: the sender\'s chat over Home; Back is Home', (
      tester,
    ) async {
      await openApp(tester);
      await NotificationTapRouter.handle(tap('7', 't1'));
      await _pump(tester, 900);
      expect(chats(), findsOneWidget);
      expect(here(), AppRoutes.chatWith('7'));

      appRouter.pop();
      await _pump(tester, 600);
      expect(chats(), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      await finish(tester);
    });

    testWidgets('that chat already open: no second copy of it', (
      tester,
    ) async {
      await openApp(tester, location: AppRoutes.chatWith('7'));
      await NotificationTapRouter.handle(tap('7', 't2'));
      await _pump(tester, 900);
      expect(chats(), findsOneWidget);
      expect(here(), AppRoutes.chatWith('7'));
      await finish(tester);
    });

    testWidgets('another chat open: swapped for the sender\'s, not stacked', (
      tester,
    ) async {
      await openApp(tester, location: AppRoutes.chatWith('7'));
      await NotificationTapRouter.handle(tap('8', 't3'));
      await _pump(tester, 900);
      expect(chats(), findsOneWidget);
      expect(here(), AppRoutes.chatWith('8'));
      expect(find.text('Meera'), findsWidgets);

      appRouter.pop();
      await _pump(tester, 600);
      expect(chats(), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      await finish(tester);
    });
  });

  testWidgets('a malformed chat push is ignored safely', (tester) async {
    await openApp(tester);
    unawaited(
      ChatPush.onForeground(PushEnvelope.fromMap({'type': 'CHAT_SYNC'})),
    );
    unawaited(
      ChatPush.onBackground(
        PushEnvelope.fromMap({'type': 'CHAT_MESSAGE'}),
        alreadyShownByOs: false,
      ),
    );
    await _pump(tester, 300);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('offline: the message waits, then goes once the network is '
      'back, with the same clientId', (tester) async {
    await openApp(tester, location: AppRoutes.chatWith('7'));
    backend.offline = true;
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'Later',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await _pump(tester, 400);
    expect(find.byIcon(LucideIcons.clock3), findsOneWidget);
    expect(find.text('Not sent · tap to retry'), findsNothing);

    backend.offline = false;
    NetworkStatus.instance.value = false;
    NetworkStatus.instance.value = true;
    await _pump(tester, 600);
    expect(backend.sent.length, greaterThanOrEqualTo(2));
    expect(backend.sent.map((b) => b['clientId']).toSet(), hasLength(1));
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a new message builds its own row, not every bubble', (
    tester,
  ) async {
    final base = DateTime.now().subtract(const Duration(hours: 1));
    for (var i = 10; i >= 1; i--) {
      backend.messages.add(
        _Backend._message(
          'm$i',
          text: 'line $i',
          at: base.add(Duration(minutes: i * 10)),
        ),
      );
    }
    await openApp(tester, location: AppRoutes.chatWith('7'));
    backend.messages.insert(0, _Backend._message('m11', text: 'line 11'));
    final rebuilt = await countRebuilds(() async {
      unawaited(
        ChatPush.onForeground(
          PushEnvelope.fromMap({
            'type': 'CHAT_SYNC',
            'conversationId': 'c1',
            'event': 'message',
          }),
        ),
      );
      await _pump(tester, 400);
    });
    expect(find.text('line 11'), findsOneWidget);
    // The new row, and the newest old one (it lost its tail) at most.
    expect(rebuilt['ChatMessageRow'] ?? 0, lessThanOrEqualTo(2));
    await finish(tester);
  });

  testWidgets('company-only chat with a non-company host: a calm "not '
      'available" notice, no composer, no toast', (tester) async {
    backend.notAvailable = true;
    await openApp(tester, location: AppRoutes.chatWith('7'));
    expect(
      find.text("Chat isn't available with this person yet"),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-composer-field')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await finish(tester);
  });

  testWidgets('a send refused as not available: the notice replaces the '
      'composer, the text is kept, no toast', (tester) async {
    backend.sendNotAvailable = true;
    await openApp(tester, location: AppRoutes.chatWith('7'));
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'Hello',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await _pump(tester, 800);
    expect(
      find.text("Chat isn't available with this person yet"),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-composer-field')), findsNothing);
    expect(find.text('Not sent · tap to retry'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await finish(tester);
  });

  testWidgets('chat switched off while a chat is open: the chat and its '
      'sheet close, the tab and badge go, protection is cleared', (
    tester,
  ) async {
    await openApp(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavbar),
        matching: find.byIcon(LucideIcons.messageCircle),
      ),
    );
    await _pump(tester, 600);
    await tester.tap(find.text('Priya'));
    await _pump(tester, 900);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(ChatScreenGuard.instance.isSecure, isTrue);
    // The ⋮ menu open on top.
    await tester.tap(find.bySemanticsLabel('More options'));
    await _pump(tester, 500);
    expect(find.text('Prices'), findsOneWidget);

    backend.config = 'off';
    AppUpdatePush.onUpdate('config_updated', scope: 'chat');
    await _pump(tester, 900);
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.text('Prices'), findsNothing);
    expect(dockItems(), findsNWidgets(3));
    expect(find.byType(ChatUnreadBadge), findsNothing);
    expect(find.byType(ChatsTopBar), findsNothing);
    expect(ChatScreenGuard.instance.isSecure, isFalse);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('a narrow phone with large text: no overflow', (tester) async {
    backend.messages.add(_Backend._message('m1', text: 'A' * 300));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view
      ..physicalSize = const Size(320, 568) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Scale.update(const Size(320, 568));
    await tester.pumpWidget(
      VibeLiveApp(
        themeController: ThemeController(ThemeMode.light),
        localeController: LocaleController(const Locale('ur')),
      ),
    );
    appRouter.go(AppRoutes.home);
    await _pump(tester, 600);
    unawaited(appRouter.push(AppRoutes.chatWith('7')));
    await _pump(tester, 900);
    expect(find.byType(ChatMessageRow), findsWidgets);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
