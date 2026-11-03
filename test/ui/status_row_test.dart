import 'dart:typed_data';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/host_status/vibe_frames.dart';
import 'package:vibelive/app/api/host_status/vibe_previews.dart';
import 'package:vibelive/app/api/host_status/vibe_video_cache.dart';
import 'package:vibelive/app/api/host_status/host_status_models.dart';
import 'package:vibelive/app/api/host_status/host_status_queries.dart';
import 'package:vibelive/app/callscreen/helper/push/app_update_push.dart';
import 'package:vibelive/app/homescreen/statuses/status_circle.dart';
import 'package:vibelive/app/hosthub/approved/widgets/status_capture.dart';
import 'package:vibelive/app/homescreen/statuses/status_row.dart';
import 'package:vibe_camera/src/capture/capture_screen.dart';
import 'package:vibelive/core/network/strapi.dart';
import 'package:vibelive/core/query/query_persist.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'host_onboarding_support/harness.dart';

/// Every clip "plays" for [clip]: initialised at once, then half a second
/// further each time the controller polls the position (every 100 ms).
class _FakeVideo extends VideoPlayerPlatform {
  static const clip = Duration(seconds: 2);

  /// Like some phones: the position stops 100 ms short of the length and a
  /// `completed` event says it finished.
  bool stopShort = false;
  final _completed = <int>{};
  final _events = <int, StreamController<VideoEvent>>{};
  final _playing = <int>{};
  final opened = <String>[];
  int _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    final id = _next++;
    opened.add(dataSource.uri ?? '');
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    scheduleMicrotask(
      () => events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: clip,
          size: const Size(720, 1280),
        ),
      ),
    );
    return id;
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) =>
      create(options.dataSource);

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    _playing.remove(playerId);
    unawaited(_events.remove(playerId)?.close());
  }

  @override
  Future<void> play(int playerId) async => _playing.add(playerId);

  @override
  Future<void> pause(int playerId) async => _playing.remove(playerId);

  /// Half a second further on each time it is asked while playing.
  final _positions = <int, Duration>{};

  @override
  Future<Duration> getPosition(int playerId) async {
    final now = _positions[playerId] ?? Duration.zero;
    if (!_playing.contains(playerId)) return now;
    final next = now + const Duration(milliseconds: 500);
    if (stopShort) {
      final end = clip - const Duration(milliseconds: 100);
      if (next >= end && _completed.add(playerId)) {
        scheduleMicrotask(
          () => _events[playerId]?.add(
            VideoEvent(eventType: VideoEventType.completed),
          ),
        );
      }
      return _positions[playerId] = next > end ? end : next;
    }
    return _positions[playerId] = next > clip ? clip : next;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => const SizedBox.expand();

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
}

JsonMap _status(String id, {int hoursAgo = 1, bool seen = false}) => {
  'documentId': id,
  'media': 'https://cdn.example/$id.mp4',
  'recordedAt': DateTime.now()
      .subtract(Duration(hours: hoursAgo))
      .toUtc()
      .toIso8601String(),
  'visibleUntil': DateTime.now()
      .add(const Duration(hours: 12))
      .toIso8601String(),
  'seen': seen,
};

JsonMap _group(String id, String name, List<JsonMap> statuses) => {
  'host': {
    'documentId': id,
    'userDocumentId': 'u-$id',
    'name': name,
    'avatar': null,
    'online': true,
    'verified': false,
  },
  'statuses': statuses,
};

void main() {
  late _FakeVideo video;

  setUpAll(() async {
    await setUpHostHarness();
  });

  setUp(() async {
    video = _FakeVideo();
    VideoPlayerPlatform.instance = video;
    // No file system or database in tests: clips always stream.
    VibeVideoCache.enabled = false;
    VibePreviews.enabled = false;
    VibePreviews.files.value = const {};
    // The saved app-config of the test before must not switch statuses on.
    await QueryPersist.clearAll();
  });

  /// Statuses switched on in the admin (app-config's hostMedia block).
  void statusesOn(HostBackend backend, {bool on = true, int perDay = 3}) {
    backend.replies['GET /api/app-config'] = (_) => {
      'data': {
        'hostMedia': {'statusEnabled': on, 'statusMaxPerDay': perDay},
      },
    };
  }

  Future<void> open(
    WidgetTester tester, {
    bool Function(StatusHost)? include,
  }) async {
    phone(tester);
    await pumpRoutes(
      tester,
      Scaffold(
        body: Column(children: [StatusRow(include: include)]),
      ),
    );
    await pumpFor(tester, 600);
  }

  StatusCircle circle(WidgetTester tester, String id) =>
      tester.widget<StatusCircle>(find.byKey(ValueKey('status-$id')));

  test('the feed reads one circle per host, oldest status first', () {
    final groups = StatusGroup.listFrom({
      'results': [
        _group('e1', 'Asha', [
          _status('s1', hoursAgo: 3, seen: true),
          _status('s2'),
        ]),
        _group('e2', 'Meera', []),
        {'host': null, 'statuses': []},
      ],
    });
    expect(groups, hasLength(1), reason: 'nothing playable is dropped');
    final asha = groups.single;
    expect(asha.host.name, 'Asha');
    expect(asha.statuses.map((s) => s.documentId), ['s1', 's2']);
    expect(asha.seenWith(const {}), isFalse);
    expect(asha.firstUnseen(const {}), 1, reason: 'resumes where they left');
    expect(asha.seenWith(const {'s2'}), isTrue);
  });

  testWidgets('a client sees every host with a status; none to post', (
    tester,
  ) async {
    final backend = await resetHost();
    statusesOn(backend);
    backend.replies['GET /api/host-statuses/feed'] = (_) => {
      'results': [
        _group('e1', 'Asha', [_status('s1')]),
        _group('e2', 'Meera', [_status('m1', seen: true)]),
      ],
    };
    await open(tester);
    expect(find.byKey(const ValueKey('status-row')), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Meera'), findsOneWidget);
    expect(find.text('Add Vibe'), findsNothing, reason: 'a client');
    expect(circle(tester, 'e1').ring, StatusRing.fresh);
    expect(circle(tester, 'e2').ring, StatusRing.seen);
    await finishHost(tester);
  });

  testWidgets('watching plays them in order, reports each, greys the ring', (
    tester,
  ) async {
    final backend = await resetHost();
    statusesOn(backend);
    backend.replies['GET /api/host-statuses/feed'] = (_) => {
      'results': [
        _group('e1', 'Asha', [_status('s1', hoursAgo: 2), _status('s2')]),
        _group('e2', 'Meera', [_status('m1')]),
      ],
    };
    await open(tester);
    await tester.tap(find.text('Asha'));
    await pumpFor(tester, 300);
    expect(find.byKey(const ValueKey('status-visit-profile')), findsOneWidget);

    // Each clip ends, the next starts; after the last host it closes.
    await pumpFor(tester, 4000);
    expect(video.opened, [
      'https://cdn.example/s1.mp4',
      'https://cdn.example/s2.mp4',
      'https://cdn.example/m1.mp4',
    ]);
    expect(
      find.byKey(const ValueKey('status-visit-profile')),
      findsNothing,
      reason: 'closed',
    );
    final views = backend.sent('POST', '/host-media-views');
    expect(
      [for (final v in views) (v.data as Map)['statusDocumentId']],
      ['s1', 's2', 'm1'],
    );
    expect((views.first.data as Map)['hostDocumentId'], 'e1');
    expect((views.first.data as Map)['kind'], 'status');
    expect(circle(tester, 'e1').ring, StatusRing.seen);
    expect(circle(tester, 'e2').ring, StatusRing.seen);
    await finishHost(tester);
  });

  testWidgets('Visit profile closes the viewer and looks the host up', (
    tester,
  ) async {
    final backend = await resetHost();
    statusesOn(backend);
    backend.replies['GET /api/host-statuses/feed'] = (_) => {
      'results': [
        _group('e1', 'Asha', [_status('s1')]),
      ],
    };
    await open(tester);
    await tester.tap(find.text('Asha'));
    await pumpFor(tester, 300);
    // The ↗ under the Vibe.
    await tester.tap(find.byKey(const ValueKey('status-visit-profile')));
    await pumpFor(tester, 600);
    expect(find.byKey(const ValueKey('status-visit-profile')), findsNothing);
    expect(
      backend.calls.where((c) => c.path == '/api/expert-profiles'),
      isNotEmpty,
    );
    tester.takeException(); // the profile sheet's own reads are not faked
    await finishHost(tester);
  });

  testWidgets("the tab and filters decide whose circles show", (tester) async {
    final backend = await resetHost();
    statusesOn(backend);
    backend.replies['GET /api/host-statuses/feed'] = (_) => {
      'results': [
        _group('e1', 'Asha', [_status('s1')]),
        _group('e2', 'Meera', [_status('m1')]),
      ],
    };
    await open(tester, include: (h) => h.expertDocumentId == 'e2');
    expect(find.text('Asha'), findsNothing);
    expect(find.text('Meera'), findsOneWidget);
    await finishHost(tester);

    // Nobody passes and nothing to post: no row at all.
    final again = await resetHost();
    statusesOn(again);
    again.replies['GET /api/host-statuses/feed'] =
        backend.replies['GET /api/host-statuses/feed']!;
    await open(tester, include: (_) => false);
    expect(find.byKey(const ValueKey('status-row')), findsNothing);
    await finishHost(tester);
  });

  testWidgets('a host gets their own circle first, with a "+"', (tester) async {
    const expert = {'id': 9, 'documentId': 'e9', 'isApproved': true};
    var backend = await resetHost(expert: expert);
    statusesOn(backend);
    backend.replies['GET /api/host-statuses/mine'] = (_) => {'results': []};
    await open(tester);
    expect(find.text('Add Vibe'), findsOneWidget);
    expect(find.byType(StatusAddBadge), findsOneWidget);
    expect(circle(tester, 'mine').ring, StatusRing.none);
    await finishHost(tester);

    // One waiting for a reviewer.
    backend = await resetHost(expert: expert);
    statusesOn(backend);
    backend.replies['GET /api/host-statuses/mine'] = (_) => {
      'results': [
        {'documentId': 'p1', 'status': 'pending', 'state': 'pending'},
      ],
    };
    await open(tester);
    expect(find.text('In review'), findsOneWidget);
    await finishHost(tester);

    // One live: theirs in a ring; tapping plays it, with no Visit profile.
    backend = await resetHost(expert: expert);
    statusesOn(backend);
    backend.replies['GET /api/host-statuses/mine'] = (_) => {
      'results': [
        {
          'documentId': 'v1',
          'media': 'https://cdn.example/v1.mp4',
          'thumbnail': 'https://cdn.example/v1.jpg',
          'status': 'approved',
          'state': 'visible',
          'views': 7,
        },
      ],
    };
    await open(tester);
    expect(find.text('Your Vibe'), findsOneWidget);
    expect(circle(tester, 'mine').ring, StatusRing.fresh);
    expect(circle(tester, 'mine').previewUrl, 'https://cdn.example/v1.jpg');
    await tester.tap(find.text('Your Vibe'));
    await pumpFor(tester, 300);
    expect(video.opened, ['https://cdn.example/v1.mp4']);
    // Their own: only how many watched it.
    expect(find.text('7 views'), findsOneWidget);
    expect(find.byKey(const ValueKey('status-visit-profile')), findsNothing);
    expect(find.byKey(const ValueKey('status-call-audio')), findsNothing);
    expect(backend.sent('POST', '/host-media-views'), isEmpty);
    // The counts are read fresh when the host opens their own.
    expect(backend.sent('GET', '/host-statuses/mine').length, greaterThan(1));
    await tester.tap(find.byKey(const ValueKey('status-close')));
    await pumpFor(tester, 400);
    await finishHost(tester);
  });

  testWidgets('switched off: no row, no request', (tester) async {
    const expert = {'id': 9, 'documentId': 'e9', 'isApproved': true};
    final backend = await resetHost(expert: expert);
    statusesOn(backend, on: false);
    await open(tester);
    expect(find.byKey(const ValueKey('status-row')), findsNothing);
    expect(backend.sent('GET', '/host-statuses/feed'), isEmpty);
    await finishHost(tester);
  });

  test('a status watched is greyed for this user only', () {
    StatusSeen.forUser('a');
    StatusSeen.mark('s1');
    expect(StatusSeen.ids.value, {'s1'});
    expect(StatusSeen.forUser('b'), isEmpty, reason: 'another account');
  });

  testWidgets("today's allowance used: told before recording", (tester) async {
    const expert = {'id': 9, 'documentId': 'e9', 'isApproved': true};
    final backend = await resetHost(expert: expert);
    statusesOn(backend, perDay: 2);
    final now = DateTime.now().toUtc();
    backend.replies['GET /api/host-statuses/mine'] = (_) => {
      'results': [
        for (final h in [1, 3])
          {
            'documentId': 'p$h',
            'status': 'pending',
            'state': 'pending',
            'recordedAt': now.subtract(Duration(hours: h)).toIso8601String(),
          },
      ],
    };
    await open(tester);
    await tester.tap(find.byType(StatusAddBadge));
    await pumpFor(tester, 300);
    expect(find.textContaining('posted all your Vibes'), findsOneWidget);
    await pumpFor(tester, 4000); // the toast leaves
    await finishHost(tester);
  });

  test('posted today counts a rolling 24 hours', () {
    final now = DateTime.utc(2026, 11, 2, 12);
    HostOwnStatus at(int hoursAgo) => HostOwnStatus(
      documentId: 'x$hoursAgo',
      recordedAt: now.subtract(Duration(hours: hoursAgo)),
    );
    expect(postedToday([at(1), at(23), at(25)], now: now), 2);
    expect(postedToday(const [], now: now), 0);
  });

  testWidgets('an admin switching Vibes on reaches an open app at once', (
    tester,
  ) async {
    final backend = await resetHost();
    statusesOn(backend, on: false);
    backend.replies['GET /api/host-statuses/feed'] = (_) => {
      'results': [
        _group('e1', 'Asha', [_status('s1')]),
      ],
    };
    await open(tester);
    expect(find.byKey(const ValueKey('status-row')), findsNothing);
    statusesOn(backend);
    AppUpdatePush.onUpdate('config_updated'); // the silent push
    await pumpFor(tester, 800);
    expect(find.byKey(const ValueKey('status-row')), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);
    await finishHost(tester);
  });

  testWidgets("the + opens the app's own camera, in the app's language", (
    tester,
  ) async {
    const expert = {'id': 9, 'documentId': 'e9', 'isApproved': true};
    final backend = await resetHost(expert: expert);
    statusesOn(backend);
    backend.replies['GET /api/host-statuses/mine'] = (_) => {'results': []};
    await open(tester);
    await tester.tap(find.byType(StatusAddBadge));
    await pumpFor(tester, 800);
    // Our camera (a test has no real one, so it stays on its spinner), with
    // the app's own words.
    expect(find.byType(VibeCaptureScreen), findsOneWidget);
    expect(find.text('Tap to record'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close'));
    await pumpFor(tester, 600);
    expect(find.byType(VibeCaptureScreen), findsNothing);
    await finishHost(tester);
  });

  testWidgets('a host still in review gets no "+"', (tester) async {
    const expert = {'id': 9, 'documentId': 'e9', 'isApproved': false};
    final backend = await resetHost(expert: expert);
    statusesOn(backend);
    backend.replies['GET /api/host-statuses/mine'] = (_) => {'results': []};
    backend.replies['GET /api/host-statuses/feed'] = (_) => {
      'results': [
        _group('e1', 'Asha', [_status('s1')]),
      ],
    };
    await open(tester);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Add Vibe'), findsNothing);
    expect(find.byType(StatusAddBadge), findsNothing);
    await finishHost(tester);
  });

  testWidgets("a circle shows the newest Vibe's still, else the photo", (
    tester,
  ) async {
    final backend = await resetHost();
    statusesOn(backend);
    backend.replies['GET /api/host-statuses/feed'] = (_) => {
      'results': [
        {
          ..._group('e1', 'Asha', [_status('s1')]),
          'preview': 'https://cdn.example/s1.jpg',
        },
        _group('e2', 'Meera', [_status('m1')]),
      ],
    };
    await open(tester);
    expect(circle(tester, 'e1').previewUrl, 'https://cdn.example/s1.jpg');
    expect(circle(tester, 'e2').previewUrl, isNull);
    await finishHost(tester);
  });

  testWidgets('a client gets the profile\'s Audio / Video Call and a ↗ to '
      'the profile under a Vibe', (tester) async {
    final backend = await resetHost();
    statusesOn(backend);
    backend.replies['GET /api/host-statuses/feed'] = (_) => {
      'results': [
        _group('e1', 'Asha', [_status('s1')]),
      ],
    };
    // The host's rates, for the call buttons.
    backend.replies['GET /api/expert-profiles'] = (_) => {
      'data': [
        {
          'id': 1,
          'documentId': 'e1',
          'handler': 'asha',
          'isActive': true,
          'rates': {'voiceCallRate': 20, 'videoCallRate': 30},
          'user': {'id': 5, 'documentId': 'u-e1', 'name': 'Asha'},
        },
      ],
    };
    await open(tester);
    await tester.tap(find.text('Asha'));
    await pumpFor(tester, 600);
    expect(find.byKey(const ValueKey('status-call-audio')), findsOneWidget);
    expect(find.byKey(const ValueKey('status-call-video')), findsOneWidget);
    expect(find.byKey(const ValueKey('status-visit-profile')), findsOneWidget);
    expect(find.byKey(const ValueKey('status-views')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('status-call-video')));
    await pumpFor(tester, 600);
    // The viewer closed; the profile's call checks take over.
    expect(find.byKey(const ValueKey('status-call-video')), findsNothing);
    tester.takeException(); // the call checks' own reads are not faked
    await finishHost(tester);
  });

  testWidgets('master switch: posting off still shows Vibes; hidden shows none', (
    tester,
  ) async {
    const expert = {'id': 9, 'documentId': 'e9', 'isApproved': true};
    var backend = await resetHost(expert: expert);
    backend.replies['GET /api/app-config'] = (_) => {
      'data': {
        'hostMedia': {
          'statusVisible': true,
          'statusEnabled': false,
          'statusMaxPerDay': 3,
        },
      },
    };
    backend.replies['GET /api/host-statuses/mine'] = (_) => {'results': []};
    backend.replies['GET /api/host-statuses/feed'] = (_) => {
      'results': [
        _group('e1', 'Asha', [_status('s1')]),
      ],
    };
    await open(tester);
    expect(find.text('Asha'), findsOneWidget, reason: 'approved ones keep showing');
    expect(find.byType(StatusAddBadge), findsNothing, reason: 'no posting');
    await finishHost(tester);
    await QueryPersist.clearAll(); // a fresh app: no saved config from above

    backend = await resetHost(expert: expert);
    backend.replies['GET /api/app-config'] = (_) => {
      'data': {
        'hostMedia': {
          'statusVisible': false,
          'statusEnabled': false,
          'statusMaxPerDay': 3,
        },
      },
    };
    await open(tester);
    expect(find.byKey(const ValueKey('status-row')), findsNothing);
    expect(backend.sent('GET', '/host-statuses/feed'), isEmpty);
    await finishHost(tester);
  });

  testWidgets('the host deletes their own Vibe from the ⋮ menu', (tester) async {
    const expert = {'id': 9, 'documentId': 'e9', 'isApproved': true};
    final backend = await resetHost(expert: expert);
    statusesOn(backend);
    backend.replies['GET /api/host-statuses/mine'] = (_) => {
      'results': [
        {
          'documentId': 'v1',
          'media': 'https://cdn.example/v1.mp4',
          'status': 'approved',
          'state': 'visible',
          'views': 2,
        },
      ],
    };
    backend.replies['DELETE /api/host-statuses/mine/v1'] = (_) => {
      'data': {'deleted': true, 'documentId': 'v1'},
    };
    await open(tester);
    await tester.tap(find.text('Your Vibe'));
    await pumpFor(tester, 300);
    await tester.tap(find.byKey(const ValueKey('status-more')));
    await pumpFor(tester, 400);
    expect(find.text('Report'), findsNothing, reason: 'nothing to report on your own');
    await tester.tap(find.byKey(const ValueKey('status-menu-delete')));
    await pumpFor(tester, 400);
    expect(find.text('Delete this Vibe?'), findsOneWidget);
    await tester.tap(find.text('DELETE VIBE'));
    await pumpFor(tester, 800);
    expect(backend.sent('DELETE', '/host-statuses/mine/v1'), hasLength(1));
    // It was the only one: the viewer closes.
    expect(find.byKey(const ValueKey('status-more')), findsNothing);
    await finishHost(tester);
  });

  testWidgets('a client gets Report in the ⋮ menu, never Delete', (tester) async {
    final backend = await resetHost();
    statusesOn(backend);
    backend.replies['GET /api/host-statuses/feed'] = (_) => {
      'results': [
        _group('e1', 'Asha', [_status('s1')]),
      ],
    };
    backend.replies['GET /api/report-categories'] = (_) => {
      'data': [
        {'id': 1, 'documentId': 'rc1', 'name': 'Inappropriate'},
      ],
    };
    await open(tester);
    await tester.tap(find.text('Asha'));
    await pumpFor(tester, 300);
    await tester.tap(find.byKey(const ValueKey('status-more')));
    await pumpFor(tester, 400);
    expect(find.byKey(const ValueKey('status-menu-delete')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('status-menu-report')));
    await pumpFor(tester, 600);
    // The usual report sheet, about this host.
    expect(find.text('Reporting Asha'), findsOneWidget);
    tester.takeException();
    await finishHost(tester);
  });

  testWidgets('a clip that stops just short of its end still moves on', (
    tester,
  ) async {
    video.stopShort = true;
    final backend = await resetHost();
    statusesOn(backend);
    backend.replies['GET /api/host-statuses/feed'] = (_) => {
      'results': [
        _group('e1', 'Asha', [_status('s1')]),
        _group('e2', 'Meera', [_status('m1')]),
      ],
    };
    await open(tester);
    await tester.tap(find.text('Asha'));
    await pumpFor(tester, 3000);
    // Asha's only clip finished: Meera's plays next, like WhatsApp.
    expect(video.opened, [
      'https://cdn.example/s1.mp4',
      'https://cdn.example/m1.mp4',
    ]);
    // Meera's was the last: the viewer closed by itself.
    await pumpFor(tester, 2500);
    expect(find.byKey(const ValueKey('status-close')), findsNothing);
    await finishHost(tester);
  });

  testWidgets('no still from the server: a frame made on the phone shows', (
    tester,
  ) async {
    final backend = await resetHost();
    statusesOn(backend);
    backend.replies['GET /api/host-statuses/feed'] = (_) => {
      'results': [
        _group('e1', 'Asha', [_status('s1'), _status('s2')]),
      ],
    };
    // What VibePreviews publishes once it took a frame from the newest clip.
    VibePreviews.files.value = {'s2': File('/tmp/s2.jpg')};
    await open(tester);
    expect(circle(tester, 'e1').previewUrl, isNull);
    expect(circle(tester, 'e1').previewFile?.path, '/tmp/s2.jpg');
    await finishHost(tester);
  });

  group('the steadiest frame', () {
    Uint8List frame(int Function(int i) luma) {
      final px = Uint8List(48 * 48 * 4);
      for (var i = 0; i < 48 * 48; i++) {
        final v = luma(i).clamp(0, 255);
        px[i * 4] = v;
        px[i * 4 + 1] = v;
        px[i * 4 + 2] = v;
        px[i * 4 + 3] = 255;
      }
      return px;
    }

    test('detail beats a flat frame; black and white frames lose', () {
      final detailed = VibeFrames.scorePixels(
        frame((i) => (i % 48) * 5 + 20),
      );
      final flat = VibeFrames.scorePixels(frame((_) => 128));
      final black = VibeFrames.scorePixels(frame((i) => i % 2 * 20));
      final white = VibeFrames.scorePixels(frame((i) => 240 + i % 2 * 15));
      expect(detailed, greaterThan(flat));
      expect(flat, greaterThan(black));
      expect(flat, greaterThan(white));
    });
  });
}
