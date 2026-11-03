import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/api/chat/chat_queries.dart';
import 'package:vibelive/app/api/listingflow/listing_models.dart';
import 'package:vibelive/app/component/pressable.dart';
import 'package:vibelive/app/listingflow/widgets/host_grid_card.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/utils/scale.dart';

/// The Discover card's bottom row: Call Now alone while chat is off; a
/// message button (¼) beside Call Now (¾) while it is on.
void main() {
  const chatKey = ValueKey('card-chat-button');

  setUpAll(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
    await AppPrefs.init();
  });

  setUp(() async {
    rootBundle.clear();
    ChatAvailability.instance.value = false;
    await SessionStore.instance.signIn(
      user: {'id': 1, 'documentId': 'u1', 'name': 'Asha'},
      accessToken: 'access',
    );
  });

  HostCard host({int userId = 7, bool? acceptsChats}) => HostCard.fromJson({
    'id': 70,
    'documentId': 'exp7',
    'handler': 'priya',
    'tagline': 'Let us talk',
    'isActive': true,
    'rates': {'videoCallRate': 30, 'voiceCallRate': 20},
    'host_profile_images': <Object>[],
    'user': {'id': userId, 'documentId': 'usr$userId', 'name': 'Priya'},
    'chat_enabled': ?acceptsChats,
  });

  Future<int Function()> pumpCard(
    WidgetTester tester,
    HostCard card, {
    double width = 170,
    double textScale = 1,
  }) async {
    Scale.update(const Size(390, 844));
    var calls = 0;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 280,
                child: HostGridCard(
                  host: card,
                  onTap: (_) {},
                  onCall: (_) => calls++,
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/chat/:userId',
          builder: (_, s) => Text('chat with ${s.pathParameters['userId']}'),
        ),
      ],
    );
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          locale: const Locale('en'),
          supportedLocales: AppI18n.supportedLocales,
          localizationsDelegates: [AppI18n.delegate],
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => calls;
  }

  // The Call Now bar: the innermost Pressable around its phone icon.
  Finder callNow() => find
      .ancestor(
        of: find.byIcon(LucideIcons.phoneCall),
        matching: find.byType(Pressable),
      )
      .first;

  testWidgets('chat off: Call Now alone, full width, as before chat', (
    tester,
  ) async {
    final calls = await pumpCard(tester, host());
    expect(find.byKey(chatKey), findsNothing);
    expect(callNow(), findsOneWidget);
    await tester.tap(callNow());
    expect(calls(), 1);
  });

  testWidgets('chat on: message ¼ beside Call Now ¾; a tap opens the chat', (
    tester,
  ) async {
    ChatAvailability.instance.value = true;
    final calls = await pumpCard(tester, host());
    expect(find.byKey(chatKey), findsOneWidget);
    final chatWidth = tester.getSize(find.byKey(chatKey)).width;
    final callWidth = tester.getSize(callNow()).width;
    expect(callWidth / chatWidth, closeTo(3, 0.05));

    await tester.tap(callNow());
    expect(calls(), 1, reason: 'Call Now still calls');

    await tester.tap(find.byKey(chatKey));
    await tester.pumpAndSettle();
    expect(find.text('chat with 7'), findsOneWidget);
  });

  testWidgets('chat switched on or off while the card shows: it follows', (
    tester,
  ) async {
    await pumpCard(tester, host());
    expect(find.byKey(chatKey), findsNothing);
    ChatAvailability.instance.value = true;
    await tester.pump();
    expect(find.byKey(chatKey), findsOneWidget);
    ChatAvailability.instance.value = false;
    await tester.pump();
    expect(find.byKey(chatKey), findsNothing);
  });

  testWidgets('no message button on a host who turned chats off', (
    tester,
  ) async {
    ChatAvailability.instance.value = true;
    await pumpCard(tester, host(acceptsChats: false));
    expect(find.byKey(chatKey), findsNothing);
    expect(callNow(), findsOneWidget);
  });

  testWidgets('no message button on my own card', (tester) async {
    ChatAvailability.instance.value = true;
    await pumpCard(tester, host(userId: 1));
    expect(find.byKey(chatKey), findsNothing);
  });

  testWidgets('a narrow card with large text: no overflow', (tester) async {
    ChatAvailability.instance.value = true;
    await pumpCard(tester, host(), width: 130, textScale: 1.4);
    expect(find.byKey(chatKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
