import 'dart:convert';
import 'dart:io';

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
import 'package:vibelive/app/hosthub/onboarding/helper/photo_picker.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/voice_recorder.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/network/strapi.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/utils/scale.dart';

/// One recorded call.
typedef Call = ({String method, String path, Map query, Object? data});

/// The signed-in user: Personal Info complete (Assam / Baksa).
JsonMap meUser({Map<String, Object?> extra = const {}}) => {
  'id': 1,
  'documentId': 'u1',
  'name': 'Aanya Sharma',
  'email': 'aanya@b.co',
  'mobile': '9999999999',
  'role': 'Client',
  'state': {'id': 4, 'documentId': 'st4', 'name': 'Assam'},
  'district': {'id': 9, 'documentId': 'd9', 'name': 'Baksa'},
  'address_JSON': {'state': 'Assam', 'district': 'Baksa', 'country': 'India'},
  ...extra,
};

Map<String, Object?> _option(String value, String label, [String emoji = '']) =>
    {
      'value': value,
      'label': label,
      'metadata': {'emoji': emoji},
    };

/// The live `/interests/form` shape (trimmed).
final interestForm = {
  'app': {'key': 'vibe_os', 'name': 'Vibe'},
  'questions': [
    {
      'key': 'gender_pref',
      'title': 'Who would you like to talk to?',
      'selectionMode': 'single',
      'required': true,
      'options': [
        _option('gender_pref_female', 'Female'),
        _option('gender_pref_any', 'No preference'),
      ],
    },
    {
      'key': 'user_gender',
      'title': 'How do you identify?',
      'selectionMode': 'single',
      'options': [
        _option('user_gender_female', 'Woman'),
        _option('user_gender_male', 'Man'),
        {
          ..._option('user_gender_prefer_not_say', 'Prefer not to say'),
          'isDefault': true,
        },
      ],
    },
    {
      'key': 'support_topic',
      'title': 'What do you need support with?',
      'selectionMode': 'multi',
      'required': true,
      'maxSelect': 5,
      'options': [
        _option('topic_dating_advice', 'Dating advice', '🌹'),
        _option('topic_self_love', 'Self-love & confidence', '🌟'),
        _option('topic_career_confusion', 'Career confusion', '🧭'),
        _option('topic_feeling_low', 'Feeling low', '🌧️'),
      ],
    },
    {
      'key': 'interaction_mode',
      'title': 'How do you prefer to connect?',
      'selectionMode': 'single',
      'required': true,
      'options': [
        {..._option('mode_audio', 'Voice call'), 'isDefault': true},
        _option('mode_video', 'Video call'),
      ],
    },
    {
      'key': 'expert_language',
      'title': 'Which languages should your expert speak?',
      'selectionMode': 'multi',
      'maxSelect': 3,
      'options': [
        {..._option('English', 'English'), 'isDefault': true},
        _option('lang_hindi', 'Hindi'),
      ],
    },
  ],
};

/// The backend of the flow and the host ME panel.
class HostBackend implements HttpClientAdapter {
  final calls = <Call>[];

  /// Handles the server already knows.
  final taken = <String>{'taken_name'};

  /// The host profile once created (and for the approved-host tests).
  JsonMap? expert;
  JsonMap user = meUser();
  Map<String, Object?> stats = {};

  /// `/expert-profile-approvals` rows.
  List<JsonMap> approvals = [];

  /// `/me/moderation-notes`: the team's messages, newest first.
  List<JsonMap> moderationNotes = [];

  /// `/instant-call/config` (Talk Now off unless set) and the
  /// `/instant-call/initiate` answer.
  JsonMap instantConfig = {'enabled': false};
  JsonMap instantInitiate = {
    'success': false,
    'message': 'No hosts are available right now.',
    'code': 'NO_HOSTS',
  };

  /// `'POST /api/expert-profiles'`-style calls that answer 500.
  final failing = <String>{};

  /// `'GET /api/host-statuses/feed'` → reply body: a test's own endpoints,
  /// checked before the built-in ones.
  final replies = <String, Object? Function(RequestOptions o)>{};

  /// `'POST /api/expert-profiles'` → status for its [replies] body (e.g. 409).
  final statuses = <String, int>{};

  List<Call> sent(String method, String path) => [
    for (final c in calls)
      if (c.method == method && c.path == '/api$path') c,
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    calls.add((
      method: o.method,
      path: o.path,
      query: o.queryParameters,
      data: o.data is FormData ? null : o.data,
    ));
    if (failing.contains('${o.method} ${o.path}')) {
      return ResponseBody.fromString(
        jsonEncode({
          'error': {'status': 500, 'message': 'Server is down'},
        }),
        500,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(_reply(o)),
      statuses['${o.method} ${o.path}'] ?? 200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  Object _reply(RequestOptions o) {
    final own = replies['${o.method} ${o.path}'];
    if (own != null) return own(o) ?? const {};
    final q = o.queryParameters;
    final body = o.data is Map ? o.data as Map : const {};
    switch ('${o.method} ${o.path}') {
      case 'POST /api/upload':
        return [
          {'id': 801, 'url': '/uploads/voice_intro.m4a'},
        ];
      case 'GET /api/public-users/u1':
        return {'data': user};
      case 'PUT /api/public-users/u1':
        return {'data': user};
      case 'GET /api/interests/form':
        return interestForm;
      case 'GET /api/me/interests':
        return {
          'app': {'key': 'vibe_os'},
          'selections': {
            'user_gender': ['user_gender_female'],
          },
        };
      case 'GET /api/languages':
        return {
          'data': [
            {'id': 5, 'documentId': 'l5', 'name': 'English'},
            {'id': 22, 'documentId': 'l22', 'name': 'हिंदी'},
          ],
        };
      case 'GET /api/states':
        return {
          'data': [
            {'id': 4, 'documentId': 'st4', 'name': 'Assam'},
            {'id': 6, 'documentId': 'st6', 'name': 'Bihar'},
          ],
        };
      case 'GET /api/districts':
        return {
          'data': [
            {'id': 9, 'documentId': 'd9', 'name': 'Baksa'},
          ],
        };
      case 'GET /api/pricing-config':
        return {
          'data': {
            'Minimum_voiceCall_Rate': 7,
            'Minimum_videoCall_Rate': 12,
            'VoiceCall_Percentage_Commission': 40,
            'VideoCall_Percentage_Commission': 40,
            'Minimum_VoiceCall_Commission_Fixed': 3,
            'Minimum_videoCall_Commission_Fixed': 5,
            'Referral_VoiceCall_Percentage_Commission': 30,
            'Referral_VideoCall_Percentage_Commission': 30,
            'Referral_Minimum_VoiceCall_Commission_Fixed': 1,
            'Referral_Minimum_videoCall_Commission_Fixed': 1,
          },
        };
      case 'GET /api/expert-profiles':
        final handle = q['filters[handler][\$eqi]'];
        if (handle != null) {
          return {
            'data': [
              if (taken.contains(handle))
                {'id': 99, 'documentId': 'other', 'handler': handle},
            ],
          };
        }
        return {
          'data': [?expert],
        };
      case 'POST /api/expert-profiles':
        expert = {
          'id': 50,
          'documentId': 'exp50',
          ...Map<String, dynamic>.from(body['data'] as Map)..remove('language'),
        };
        return {'data': expert};
      case 'PUT /api/me/service-areas':
        return {
          'message': 'Service areas saved',
          'savedCount': 3,
          'selections': body['selections'],
        };
      case 'GET /api/expert-profile-approvals':
        return {'data': approvals};
      case 'GET /api/me/moderation-notes':
        return {'results': moderationNotes};
      case 'GET /api/instant-call/config':
        return instantConfig;
      case 'POST /api/instant-call/initiate':
        return instantInitiate;
      case 'POST /api/expert-profile-approvals':
        return {
          'data': {'id': 1, 'documentId': 'ap1', 'status': 'pending'},
        };
      case 'GET /api/user-statistics':
        return {
          'data': [
            if (stats.isNotEmpty) {'id': 1, ...stats},
          ],
        };
      case 'POST /api/notify-admin-expert-onboarded':
        return {'ok': true};
    }
    final id = expert?['documentId'];
    if (id != null && o.path == '/api/expert-profiles/$id') {
      if (o.method == 'PUT') {
        final data = Map<String, dynamic>.from(body['data'] as Map);
        data.removeWhere((k, v) => v is Map && v.containsKey('set'));
        expert = {...?expert, ...data};
      }
      return {'data': expert};
    }
    return {'data': <Object>[]};
  }

  @override
  void close({bool force = false}) {}
}

/// image_picker and the upload, faked.
class FakePhotoPicker extends HostPhotoPicker {
  int picks = 0;
  int nextId = 77;

  @override
  Future<String?> pick(HostPhotoOrigin origin) async {
    picks++;
    return '/tmp/host_photo_$picks.jpg';
  }

  @override
  Future<JsonMap> upload(String path) async => {'id': nextId++};
}

/// The microphone, faked: each recording is a small real temp file.
class FakeVoiceRecorder extends HostVoiceRecorder {
  static int made = 0;
  static bool allow = true;
  String? _path;

  @override
  Future<bool> hasPermission() async => allow;

  @override
  Future<String> start() async {
    final path = '${Directory.systemTemp.path}/host_voice_${made++}.m4a';
    File(path).writeAsBytesSync([1, 2, 3]);
    return _path = path;
  }

  @override
  Future<String?> stop() async => _path;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

Future<void> setUpHostHarness() async {
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
}

/// Fresh backend, cache and session for each test.
Future<HostBackend> resetHost({JsonMap? user, JsonMap? expert}) async {
  rootBundle.clear();
  queryCache.clear();
  for (final k in AppPrefs.keysWithPrefix('hostflow_draft')) {
    await AppPrefs.remove(k);
  }
  final backend = HostBackend();
  if (user != null) backend.user = user;
  backend.expert = expert;
  // "My profile" carries the expert, as the real `/public-users` read does.
  if (expert != null) backend.user = {...backend.user, 'expert': expert};
  ApiClient.dio.httpClientAdapter = backend;
  HostPhotoPicker.instance = FakePhotoPicker();
  HostVoiceRecorder.create = FakeVoiceRecorder.new;
  HostVoiceRecorder.upload = (_) async => {'id': 801};
  FakeVoiceRecorder.allow = true;
  await SessionStore.instance.signIn(
    user: {...backend.user}..remove('expert'),
    expert: expert,
    accessToken: 'access',
  );
  return backend;
}

Future<void> pumpFor(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Sets the phone size (logical px) and safe areas.
void phone(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double top = 0,
  double bottom = 0,
}) {
  final pad = FakeViewPadding(top: top * 3, bottom: bottom * 3);
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3
    ..padding = pad
    ..viewPadding = pad;
  addTearDown(tester.view.reset);
  Scale.update(size);
}

/// [home] at '/', plus the routes the flow leaves to.
Future<GoRouter> pumpRoutes(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('en'),
  ThemeMode theme = ThemeMode.light,
}) async {
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, state) => Scaffold(
          body: Text('HOME ${state.uri.queryParameters['tab'] ?? ''}'),
        ),
      ),
      for (final r in [
        AppRoutes.hostSchedule,
        AppRoutes.hostRates,
        AppRoutes.hostOnboarding,
        AppRoutes.professionalDetails,
      ])
        GoRoute(
          path: r,
          builder: (_, _) => Scaffold(body: Text('ROUTE $r')),
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
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: theme,
        locale: locale,
        supportedLocales: AppI18n.supportedLocales,
        localizationsDelegates: [
          AppI18n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
      ),
    ),
  );
  await pumpFor(tester, 400);
  return router;
}

Future<void> finishHost(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 6));
}

/// Scrolls [target] into view (the test font is wide), then taps it.
Future<void> tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
}

/// Taps the sticky Continue / Submit button.
Future<void> tapContinue(WidgetTester tester, {int settle = 500}) async {
  await tester.tap(find.byKey(const ValueKey('hostflow-continue')));
  await pumpFor(tester, settle);
}

/// The saved draft (after its debounce), or null.
Map<String, dynamic>? savedDraft([String user = 'u1']) {
  final raw = AppPrefs.getString('hostflow_draft_v1:$user');
  return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
}

/// The flow is flat: no box shadows, no elevation, no blur, anywhere on
/// screen (sheets included).
void expectFlat(WidgetTester tester, String reason) {
  final offenders = <String>[];
  for (final e in find.byType(DecoratedBox).evaluate()) {
    final d = (e.widget as DecoratedBox).decoration;
    final shadows = d is BoxDecoration
        ? d.boxShadow
        : (d is ShapeDecoration ? d.shadows : null);
    if (shadows != null && shadows.isNotEmpty) offenders.add('$e');
  }
  for (final e in find.byType(Material).evaluate()) {
    if ((e.widget as Material).elevation > 0) offenders.add('$e');
  }
  for (final e in find.byType(PhysicalModel).evaluate()) {
    if ((e.widget as PhysicalModel).elevation > 0) offenders.add('$e');
  }
  for (final e in find.byType(PhysicalShape).evaluate()) {
    if ((e.widget as PhysicalShape).elevation > 0) offenders.add('$e');
  }
  if (find.byType(BackdropFilter).evaluate().isNotEmpty) {
    offenders.add('BackdropFilter');
  }
  expect(offenders, isEmpty, reason: '$reason: shadow / elevation / blur');
}

/// A complete draft parked on [step]; [extra] overrides fields.
Future<void> parkDraft(String step, {Map<String, Object?> extra = const {}}) =>
    AppPrefs.setString(
      'hostflow_draft_v1:u1',
      jsonEncode({
        'step': step,
        'started': true,
        'seeded': true,
        'languagesSeeded': true,
        'topicsSeeded': true,
        'name': 'Aanya Sharma',
        'handle': 'aanyatalks',
        'tagline': 'Good conversations, music and everyday stories.',
        'bio': 'I love meeting new people and having real conversations.',
        'gender': 'Female',
        'languages': [
          {'id': 5, 'documentId': 'l5', 'label': 'English'},
        ],
        'state': {'id': 4, 'documentId': 'st4', 'name': 'Assam'},
        'district': {'id': 9, 'documentId': 'd9', 'name': 'Baksa'},
        'topics': [
          {'value': 'topic_feeling_low', 'label': 'Feeling low', 'emoji': ''},
        ],
        'photos': [
          {'key': 'm77', 'mediaId': 77},
        ],
        ...extra,
      }),
    );
