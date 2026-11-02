import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fquery/fquery.dart' show CacheProvider;
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/core/query/query_persist.dart';
import 'package:vibelive/app/api/host_status/vibe_previews.dart';
import 'package:vibelive/app/homescreen/statuses/status_story_viewer.dart';
import 'package:vibelive/app/api/host_status/vibe_video_cache.dart';
import 'package:vibelive/app/listingflow/profile/profile_gallery.dart';
import 'package:vibelive/app/listingflow/profile/gallery_video.dart';
import 'package:vibelive/app/api/listingflow/listing_models.dart';
import 'package:vibelive/app/authscreen/helper/link_parser.dart';
import 'package:vibelive/app/callscreen/helper/call_permissions.dart';
import 'package:vibelive/app/listingflow/profile/host_profile_sheet.dart';
import 'package:vibelive/app/listingflow/profile/profile_skeleton.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/utils/scale.dart';

/// A populated `/expert-profiles` row (what Discover and links carry).
Map<String, Object?> _fullHost() => {
  'id': 7,
  'documentId': 'exp7',
  'handler': 'meera',
  'tagline': 'Let us talk',
  'descriptions': 'Listener and coach.',
  'averageRating': 4.5,
  'isActive': true,
  'rates': {'videoCallRate': 30, 'voiceCallRate': 20},
  'language': [
    {'languageNames': 'Hindi'},
  ],
  'service_area_selections': [
    _answer('support_topic', 'Breakup'),
    _answer('gender', 'Female'),
    _answer('language', 'English'),
  ],
  'host_profile_images': <Object>[],
  'user': {
    'id': 70,
    'documentId': 'usr7',
    'name': 'Meera',
    'district': {'name': 'Pune'},
  },
};

Map<String, Object?> _answer(String question, String label) => {
  'snapshot': {
    'question': {'key': question},
    'option': {'label': label, 'value': label.toLowerCase()},
  },
};

Map<String, Object?> _me(String documentId, {String? email = 'a@b.co'}) => {
  'id': 1,
  'documentId': documentId,
  'name': 'Asha',
  'email': email,
  'mobile': '9999999999',
};

/// RN-sized category list: chips wrap over several rows.
const _moreCategories = [
  'Harassment or bullying',
  'Inappropriate content',
  'Fake profile',
  'Scam or fraud',
  'Other',
];

/// The call layer's permission gate without the plugin channel.
class _Granted implements CallPermissionBackend {
  @override
  Future<CallAccess> check({required bool video}) async => CallAccess.granted;

  @override
  Future<CallAccess> request({required bool video}) async => CallAccess.granted;

  @override
  Future<void> openSettings() async {}
}

class _Backend implements HttpClientAdapter {
  bool profileComplete = true;

  /// Vibes on the profile: the admin switch and the host's clips.
  bool vibesOn = false;
  List<Map<String, Object?>> vibes = const [];
  double cash = 1000;
  final requests = <String>[];
  final reviewPages = <int>[];
  final posted = <String, Object?>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requests.add('${o.method} ${o.path}');
    if (o.method == 'POST') posted[o.path] = o.data;
    // The full-profile read is slow enough to see its skeleton.
    if (o.path == '/api/expert-profiles') {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return ResponseBody.fromString(
      jsonEncode(_reply(o)),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  Object _reply(RequestOptions o) {
    final q = o.queryParameters;
    switch ('${o.method} ${o.path}') {
      case 'GET /api/expert-profiles':
        return {
          'data': [_fullHost()],
        };
      case 'GET /api/reviews':
        final page = int.parse('${q['pagination[page]'] ?? 1}');
        reviewPages.add(page);
        return {
          'data': [
            for (var i = page == 1 ? 1 : 11; i <= (page == 1 ? 10 : 12); i++)
              {
                'id': i,
                'rating': 4,
                'comments': 'Review $i',
                'createdAt': '2026-10-0${1 + i % 9}T10:00:00.000Z',
                'user': {'id': 100 + i, 'name': 'Fan $i'},
              },
          ],
          'meta': {
            'pagination': {'page': page, 'pageCount': 2, 'total': 12},
          },
        };
      case 'GET /api/public-users/u1':
        return {'data': _me('u1', email: profileComplete ? 'a@b.co' : null)};
      case 'GET /api/wallets':
        return {
          'data': [
            {'id': 1, 'wallet_type': 'CASH_WALLET', 'balance': cash},
          ],
        };
      case 'GET /api/app-config':
        return {
          'data': {
            'hostMedia': {'statusVisible': vibesOn, 'statusEnabled': vibesOn},
          },
        };
      case 'GET /api/host-statuses/host/exp7':
        return {'results': vibes};
      case 'GET /api/report-categories':
        return {
          'data': [
            {'id': 1, 'documentId': 'cat1', 'category': 'Spam'},
            {'id': 2, 'documentId': 'cat2', 'category': 'Abuse'},
            for (final (i, name) in _moreCategories.indexed)
              {'id': 3 + i, 'documentId': 'cat${3 + i}', 'category': name},
          ],
        };
      default:
        return {'data': <Object>[]};
    }
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _pump(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The test font is wider than the real one: scroll the target into view.
Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
}

/// Raises the keyboard over 10 frames; returns how often each widget type
/// rebuilt meanwhile.
Future<Map<String, int>> _keyboardFrames(WidgetTester tester) async {
  final counts = <String, int>{};
  debugOnRebuildDirtyWidget = (e, _) {
    final n = e.widget.runtimeType.toString();
    counts[n] = (counts[n] ?? 0) + 1;
  };
  try {
    for (var k = 1; k <= 10; k++) {
      tester.view.viewInsets = FakeViewPadding(bottom: k * 90.0);
      await tester.pump(const Duration(milliseconds: 16));
    }
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return counts;
}

/// What iOS reports while the keyboard is up: the keyboard as the bottom
/// view inset and no bottom padding (it covers the home indicator); the
/// status bar stays.
void _raiseKeyboard(WidgetTester tester, double keyboard, {double top = 0}) {
  tester.view
    ..viewInsets = FakeViewPadding(bottom: keyboard * 3)
    ..padding = FakeViewPadding(top: top * 3);
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
    CallPermissions.backend = _Granted();
  });

  Future<void> signIn(String documentId) => SessionStore.instance.signIn(
    user: _me(documentId),
    accessToken: 'access',
  );

  setUp(() async {
    rootBundle.clear();
    queryCache.clear();
    ApiClient.dio.httpClientAdapter = backend = _Backend();
    await signIn('u1');
  });

  /// A page with an OPEN button, plus the routes the profile can leave to.
  /// [settle]: wait for the sheet and its data. [size] is the phone in
  /// logical pixels.
  Future<void> open(
    WidgetTester tester, {
    Map<String, Object?>? row,
    bool settle = true,
    Size size = const Size(390, 844),
    Locale locale = const Locale('en'),
    EdgeInsets safeArea = EdgeInsets.zero,
  }) async {
    final insets = FakeViewPadding(
      top: safeArea.top * 3,
      bottom: safeArea.bottom * 3,
    );
    tester.view
      ..physicalSize = size * 3
      ..devicePixelRatio = 3
      ..padding = insets
      ..viewPadding = insets;
    addTearDown(tester.view.reset);
    Scale.update(size);
    final host = HostCard.fromJson(row ?? _fullHost());
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showHostProfile(context, host),
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
        for (final (path, label) in const [
          (AppRoutes.personalInfo, 'PERSONAL INFO PAGE'),
          (AppRoutes.wallet, 'WALLET PAGE'),
        ])
          GoRoute(
            path: path,
            builder: (_, _) => Scaffold(body: Text(label)),
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      CacheProvider(
        cache: queryCache,
        child: MaterialApp.router(
          routerConfig: router,
          scaffoldMessengerKey: scaffoldMessengerKey,
          theme: AppTheme.dark(),
          locale: locale,
          supportedLocales: AppI18n.supportedLocales,
          localizationsDelegates: [
            AppI18n.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
        ),
      ),
    );
    await _pump(tester, 300);
    await tester.tap(find.text('OPEN'));
    if (settle) await _pump(tester, 800);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  }

  final list = find.byType(Scrollable).first;

  testWidgets('renders the card, then the reviews page by page', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('MEERA'), findsOneWidget);
    expect(find.text('PUNE'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('₹20/min'), findsOneWidget);
    expect(find.text('₹30/min'), findsOneWidget);
    expect(find.text('"Let us talk"'), findsOneWidget);
    expect(find.text('Listener and coach.'), findsOneWidget);
    // Demographic answers are dropped; the host's own languages win over a
    // language-looking answer (no extra "English" from the tag).
    await tester.scrollUntilVisible(find.text('HINDI'), 200, scrollable: list);
    expect(find.text('Breakup'), findsOneWidget);
    expect(find.text('ENGLISH'), findsNothing);
    expect(find.text('Female'), findsNothing);
    // A complete card is not fetched again.
    expect(backend.requests, isNot(contains('GET /api/expert-profiles')));

    await tester.scrollUntilVisible(
      find.text('REVIEWS (12)'),
      200,
      scrollable: list,
    );
    await _pump(tester, 200);
    expect(find.text('Fan 1'), findsOneWidget);
    expect(backend.reviewPages, [1]);

    final row = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('SEE MORE'),
      300,
      scrollable: row,
    );
    await tester.tap(find.text('SEE MORE'));
    await _pump(tester, 300);
    expect(backend.reviewPages, [1, 2]);
    await tester.scrollUntilVisible(find.text('Fan 12'), 300, scrollable: row);
    expect(find.text('SEE MORE'), findsNothing);
    await finish(tester);
  });

  testWidgets('a summary card shows a skeleton, then the full profile', (
    tester,
  ) async {
    await open(
      tester,
      row: {
        'id': 70,
        'documentId': 'usr7',
        'name': 'Meera',
        'mobile': '1234567890',
        'expert': {'id': 7, 'documentId': 'exp7'},
      },
      settle: false,
    );
    await _pump(tester, 150);
    expect(find.text('MEERA'), findsOneWidget);
    expect(find.byType(ProfileBodySkeleton), findsOneWidget);
    expect(find.text('₹20/min'), findsNothing);

    await _pump(tester, 600);
    expect(find.byType(ProfileBodySkeleton), findsNothing);
    expect(find.text('₹20/min'), findsOneWidget);
    expect(find.text('PUNE'), findsOneWidget);
    expect(backend.requests, contains('GET /api/expert-profiles'));
    await finish(tester);
  });

  testWidgets('incomplete profile: alert, then Personal Info', (tester) async {
    backend.profileComplete = false;
    await open(tester);

    await _tap(tester, find.text('₹20/min'));
    await _pump(tester, 400);
    expect(find.text('Profile Incomplete'), findsOneWidget);

    await tester.tap(find.text('UPDATE PROFILE'));
    await _pump(tester, 800);
    expect(find.text('PERSONAL INFO PAGE'), findsOneWidget);
    expect(find.text('MEERA'), findsNothing);
    await finish(tester);
  });

  testWidgets('low balance: progress sheet, then the wallet', (tester) async {
    backend.cash = 10; // 5 min at Rs 20 needs Rs 100
    await open(tester);

    await _tap(tester, find.text('₹20/min'));
    await _pump(tester, 400);
    expect(find.text('₹10'), findsOneWidget);
    expect(find.text('of ₹100'), findsOneWidget);
    expect(find.text('Add ₹90 to call MEERA'), findsOneWidget);
    expect(find.text('Calls start with 5 minutes at ₹20/min'), findsOneWidget);

    await tester.tap(find.text('ADD ₹90'));
    await _pump(tester, 800);
    expect(find.text('WALLET PAGE'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('checks pass: safety notice, then the call hand-off', (
    tester,
  ) async {
    await open(tester);

    await _tap(tester, find.text('₹30/min'));
    await _pump(tester, 400);
    expect(find.text('Before you connect'), findsOneWidget);
    expect(find.text('CONNECTING...'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await _pump(tester, 800);
    expect(find.text('MEERA'), findsNothing); // the sheet closed
    // The call layer took over (RN `handleInitiateCall`): a video call to
    // the host's user id with RN's fallback category.
    final body = backend.posted['/api/initiateCall'] as Map?;
    expect(body?['callerId'], 1);
    expect(body?['receiverId'], 70);
    expect(body?['type'], 'videoCall');
    expect(body?['categoryId'], 'dcybx2ez5hjaqshrfpqg39on');
    // This fake answers nothing joinable: RN's invalid-response alert.
    expect(find.text('Call failed'), findsOneWidget);
    expect(find.text('Invalid response from call server.'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('own profile: no menu, and calling yourself is refused', (
    tester,
  ) async {
    await signIn('usr7');
    await open(tester);

    expect(find.text('THIS IS YOUR PROFILE'), findsOneWidget);
    expect(find.bySemanticsLabel('More options'), findsNothing);
    await _tap(tester, find.text('₹20/min'));
    await _pump(tester, 400);
    expect(find.text('🪞 This is Your Profile'), findsOneWidget);
    expect(backend.requests, isNot(contains('GET /api/wallets')));
    await finish(tester);
  });

  testWidgets('a company sees the rate above Audio / Video Call', (
    tester,
  ) async {
    await SessionStore.instance.signIn(
      user: {..._me('u1'), 'is_company_account': true},
      accessToken: 'access',
    );
    await open(tester);

    expect(find.text('Company Account • Free Calling'), findsOneWidget);
    expect(find.text('Audio Call'), findsOneWidget);
    expect(find.text('Video Call'), findsOneWidget);
    expect(find.text('₹20/min'), findsOneWidget);
    expect(find.text('₹30/min'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('share copies the profile link', (tester) async {
    String? copied;
    final channel = tester.binding.defaultBinaryMessenger;
    channel.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = call.arguments['text'];
      return null;
    });
    addTearDown(
      () => channel.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await open(tester);

    await tester.tap(find.bySemanticsLabel('Share profile'));
    await _pump(tester, 400);
    expect(find.text('SHARE PROFILE'), findsOneWidget);
    await tester.tap(find.text('Copy Link'));
    await _pump(tester, 600);
    expect(copied, LinkParser.shareLink('meera'));
    expect(find.text('Profile link copied to clipboard!'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('share via opens the OS sheet with the RN message', (
    tester,
  ) async {
    String? shared;
    const share = MethodChannel('dev.fluttercommunity.plus/share');
    final channel = tester.binding.defaultBinaryMessenger;
    channel.setMockMethodCallHandler(share, (call) async {
      if (call.method == 'share') shared = call.arguments['text'];
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
    addTearDown(() => channel.setMockMethodCallHandler(share, null));
    await open(tester);

    await tester.tap(find.bySemanticsLabel('Share profile'));
    await _pump(tester, 400);
    await tester.tap(find.text('Share via…'));
    await _pump(tester, 600);
    expect(shared, 'Check out MEERA on Vibe: ${LinkParser.shareLink('meera')}');
    await finish(tester);
  });

  testWidgets('an approved video intro is the first slide, with only a sound '
      'button; photos follow', (tester) async {
    VibeVideoCache.enabled = false;
    GalleryVideo.muted.value = false;
    await open(
      tester,
      row: {
        ..._fullHost(),
        'video_intro': {'url': 'https://cdn.example.com/intro.mp4'},
        'video_intro_status': 'approved',
        'host_profile_images': [
          {
            'status_enum': 'approved',
            'image': {'url': 'https://cdn.example.com/p1.jpg'},
          },
        ],
      },
    );
    final video = tester.widget<GalleryVideo>(find.byType(GalleryVideo));
    expect(video.url, 'https://cdn.example.com/intro.mp4');
    expect(video.active, isTrue, reason: 'plays by itself');
    expect(find.byKey(const ValueKey('gallery-video-mute')), findsOneWidget);
    // The one control: sound off, remembered.
    await tester.tap(find.byKey(const ValueKey('gallery-video-mute')));
    await _pump(tester, 100);
    expect(GalleryVideo.muted.value, isTrue);
    GalleryVideo.muted.value = false;
    // On to the photo: the video pauses (stays loaded), the button goes.
    final gallery = find.byType(ProfileGallery);
    final box = tester.getRect(gallery);
    await tester.tapAt(Offset(box.right - 20, box.center.dy));
    await _pump(tester, 300);
    expect(
      tester.widget<GalleryVideo>(find.byType(GalleryVideo, skipOffstage: false)).active,
      isFalse,
    );
    expect(find.byKey(const ValueKey('gallery-video-mute')), findsNothing);
    tester.takeException(); // no video plugin in tests
    await finish(tester);

    // Not approved yet: no video slide at all.
    await open(
      tester,
      row: {
        ..._fullHost(),
        'video_intro': {'url': 'https://cdn.example.com/intro.mp4'},
        'video_intro_status': 'pending',
      },
    );
    expect(find.byType(GalleryVideo, skipOffstage: false), findsNothing);
    await finish(tester);
  });

  testWidgets('Vibes on the profile open the Home viewer on the tapped clip',
      (tester) async {
    VibeVideoCache.enabled = false;
    VibePreviews.enabled = false;
    await QueryPersist.clearAll();
    backend
      ..vibesOn = true
      ..vibes = [
        for (final (id, h) in const [('new', 1), ('old', 3)])
          {
            'documentId': id,
            'media': 'https://cdn.example.com/$id.mp4',
            'thumbnail': 'https://cdn.example.com/$id.jpg',
            'recordedAt': DateTime.now()
                .subtract(Duration(hours: h))
                .toUtc()
                .toIso8601String(),
          },
      ];
    await open(tester);
    expect(find.byKey(const ValueKey('profile-vibe-new')), findsOneWidget);
    // Posting order in the row too: the older one comes first.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('profile-vibe-old'))).dx,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('profile-vibe-new'))).dx,
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('profile-vibe-old')));
    await _pump(tester, 400);
    final viewer = tester.widget<StatusStoryViewer>(
      find.byType(StatusStoryViewer),
    );
    // Posting order, as on Home: the first posted plays first.
    expect(viewer.groups.single.statuses.map((s) => s.documentId), [
      'old',
      'new',
    ]);
    expect(viewer.initialItem, 0);
    expect(viewer.showVisit, isFalse, reason: 'already on this profile');
    expect(find.byKey(const ValueKey('status-visit-profile')), findsNothing);
    // This profile's own Audio / Video Call buttons, with its rates.
    expect(find.byKey(const ValueKey('status-call-audio')), findsOneWidget);
    expect(find.byKey(const ValueKey('status-call-video')), findsOneWidget);
    expect(find.byKey(const ValueKey('status-more')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('status-close')));
    await _pump(tester, 400);
    tester.takeException(); // no video plugin in tests
    backend
      ..vibesOn = false
      ..vibes = const [];
    await finish(tester);
  });

  testWidgets('voice intro shows only when approved', (tester) async {
    await open(
      tester,
      row: {
        ..._fullHost(),
        'audio_intro': {'url': 'https://cdn.example.com/intro.mp3'},
        'audio_intro_status': 'approved',
      },
    );
    expect(find.text('HEAR THEIR VOICE'), findsOneWidget);
    await finish(tester);

    await open(
      tester,
      row: {
        ..._fullHost(),
        'audio_intro': {'url': 'https://cdn.example.com/intro.mp3'},
        'audio_intro_status': 'pending',
      },
    );
    expect(find.text('HEAR THEIR VOICE'), findsNothing);
    await finish(tester);
  });

  testWidgets('block from the menu', (tester) async {
    await open(tester);

    await tester.tap(find.bySemanticsLabel('More options'));
    await _pump(tester, 400);
    await tester.tap(find.text('Block this Expert'));
    await _pump(tester, 400);
    expect(find.text('Block this Expert?'), findsOneWidget);
    await tester.tap(find.text('BLOCK'));
    await _pump(tester, 800);

    expect(backend.posted['/api/user-blocks'], {'targetUserId': 'usr7'});
    expect(find.text('Expert blocked.'), findsOneWidget);
    expect(find.text('MEERA'), findsNothing);
    await finish(tester);
  });

  testWidgets('report: a category is required, then it is sent', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.bySemanticsLabel('More options'));
    await _pump(tester, 400);
    await tester.tap(find.text('Report this User'));
    await _pump(tester, 600);
    expect(find.text('REPORT PROFILE'), findsOneWidget);
    expect(find.text('Reporting MEERA'), findsOneWidget);

    await _tap(tester, find.text('SUBMIT REPORT'));
    await _pump(tester, 400);
    expect(find.text('Please select a report category.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await _pump(tester, 400);

    await tester.tap(find.text('Spam'));
    await tester.enterText(find.byType(TextField), 'Rude on call');
    await _pump(tester, 100);
    expect(find.text('12/600'), findsOneWidget);
    await _tap(tester, find.text('SUBMIT REPORT'));
    await _pump(tester, 600);

    expect(backend.posted['/api/reports'], {
      'data': {
        'reported_by_user': 'u1',
        'reported_to_user': 'usr7',
        'report_category': 'cat1',
        'note': 'Rude on call',
        'report_status': 'new',
      },
    });
    expect(
      find.text('Report submitted. Our team will review it.'),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('dragging the profile down closes it', (tester) async {
    await open(tester);
    expect(find.text('MEERA'), findsOneWidget);

    await tester.fling(find.text('MEERA'), const Offset(0, 500), 1500);
    await _pump(tester, 1000);
    expect(find.text('MEERA'), findsNothing);
    expect(find.text('OPEN'), findsOneWidget);
    await finish(tester);
  });

  for (final (size, keyboard, safeArea) in const [
    (Size(375, 667), 300.0, EdgeInsets.only(top: 20)), // iPhone SE
    (Size(430, 932), 336.0, EdgeInsets.only(top: 59, bottom: 34)), // Pro Max
  ]) {
    testWidgets('report with the keyboard up on ${size.width.toInt()}x'
        '${size.height.toInt()}: the note and SUBMIT stay visible', (
      tester,
    ) async {
      await open(tester, size: size, safeArea: safeArea);
      await tester.tap(find.bySemanticsLabel('More options'));
      await _pump(tester, 400);
      await tester.tap(find.text('Report this User'));
      await _pump(tester, 600);
      await tester.tap(find.text('Other'));
      await tester.enterText(find.byType(TextField), 'Other: ${'x' * 300}');
      _raiseKeyboard(tester, keyboard, top: safeArea.top);
      await _pump(tester, 400);

      expect(tester.takeException(), isNull); // no "bottom overflowed"
      final keyboardTop = size.height - keyboard;
      final submit = tester.getRect(find.text('SUBMIT REPORT'));
      final field = tester.getRect(find.byType(TextField));
      expect(submit.bottom, lessThanOrEqualTo(keyboardTop));
      expect(field.top, greaterThanOrEqualTo(safeArea.top));
      expect(field.top, lessThan(submit.top)); // the note is on screen
      // The sheet stays under the status bar.
      expect(
        tester.getRect(find.text('REPORT PROFILE')).top,
        greaterThanOrEqualTo(safeArea.top),
      );

      await tester.tap(find.text('SUBMIT REPORT'));
      await _pump(tester, 600);
      expect(
        (backend.posted['/api/reports'] as Map)['data'],
        containsPair('report_category', 'cat7'),
      );
      await finish(tester);
    });
  }

  testWidgets('share sheet: Show QR Code opens the profile QR', (tester) async {
    await open(tester);
    await tester.tap(find.bySemanticsLabel('Share profile'));
    await _pump(tester, 400);
    expect(find.text('Share via…'), findsOneWidget);
    expect(find.text('Copy Link'), findsOneWidget);
    await tester.tap(find.text('Show QR Code'));
    await _pump(tester, 600);
    expect(find.text('SHARE PROFILE'), findsNothing);
    expect(find.text('Profile QR Code'), findsOneWidget);
    expect(find.text('@meera'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('320 wide, Hindi, long name and big rates: no overflow', (
    tester,
  ) async {
    final row = _fullHost();
    await open(
      tester,
      size: const Size(320, 667),
      locale: const Locale('hi'),
      row: {
        ...row,
        'averageRating': 4.75,
        'rates': {'videoCallRate': 125000, 'voiceCallRate': 99999.5},
        'tagline': 'A very long tagline ' * 8,
        'user': {
          ...(row['user']! as Map<String, Object?>),
          'name': 'Venkata Lakshmi Narasimha Subrahmanyam Chakravarthy',
          'district': {'name': 'Thiruvananthapuram Rural North District'},
        },
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('₹125000/मिनट'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('(12)'),
      200,
      scrollable: list,
    );
    await _pump(tester, 200);
    expect(tester.takeException(), isNull);

    // The safety notice and the menu fit too.
    await tester.tap(find.bySemanticsLabel('और विकल्प'));
    await _pump(tester, 400);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('a rising keyboard rebuilds only its inset, not the sheets', (
    tester,
  ) async {
    await open(tester, size: const Size(375, 667));
    await tester.tap(find.bySemanticsLabel('More options'));
    await _pump(tester, 400);
    await tester.tap(find.text('Report this User'));
    await _pump(tester, 600);
    await tester.enterText(find.byType(TextField), 'note');
    await _pump(tester, 100);

    final built = await _keyboardFrames(tester);
    expect(built['KeyboardInset'], greaterThan(0));
    for (final name in ['_ReportSheet', '_ProfileView', 'ProfileHeader']) {
      expect(built[name], isNull, reason: name);
    }
    await finish(tester);
  });

  testWidgets('notch: back, share and ⋮ sit below the status bar; the '
      'reviews end above the home indicator', (tester) async {
    const safe = EdgeInsets.only(top: 59, bottom: 34);
    await open(tester, size: const Size(393, 852), safeArea: safe);
    for (final label in ['Back', 'Share profile', 'More options']) {
      expect(
        tester.getRect(find.bySemanticsLabel(label)).top,
        greaterThanOrEqualTo(safe.top),
        reason: label,
      );
    }
    await tester.fling(list, const Offset(0, -4000), 4000);
    await _pump(tester, 1200);
    final reviews = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.horizontal,
    );
    expect(
      tester.getRect(reviews).bottom,
      lessThanOrEqualTo(852 - safe.bottom),
    );
    await finish(tester);
  });
}
