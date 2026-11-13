import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_camera/vibe_camera.dart';
import 'package:video_player/video_player.dart' show VideoPlayer;
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/fakes.dart';

void main() {
  late FakeSession session;
  late FakeExporter exporter;

  setUp(() {
    VibeCameraLane.debugReset();
    session = FakeSession();
    exporter = FakeExporter();
    VideoPlayerPlatform.instance = FakeVideoPlatform();
  });

  Future<VibeCaptureSession> opener({
    required VibeLens lens,
    required int preferredFps,
    required bool enableAudio,
  }) async => session;

  Future<LauncherState> open(WidgetTester tester, VibeCameraConfig config, {VibeSessionOpener? using}) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Launcher(config: config, opener: using ?? opener)));
    await tester.tap(find.text('open'));
    await pumpFor(tester, 600);
    return tester.state<LauncherState>(find.byType(Launcher, skipOffstage: false));
  }

  /// The editor preview's horizontal scale: −1 flipped, 1 as recorded.
  double flipOf(WidgetTester tester) => tester
      .widget<Transform>(find.ancestor(of: find.byType(VideoPlayer), matching: find.byType(Transform)).first)
      .transform
      .storage[0];

  group('camera', () {
    testWidgets('live preview, no frame-rate badge, a look picked from the strip', (tester) async {
      await open(tester, VibeCameraConfig(exporter: exporter));
      expect(find.byKey(const ValueKey('fake-preview')), findsOneWidget);
      expect(find.textContaining('FPS'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('vibe-filter-warm')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Warm'), findsNWidgets(2), reason: 'its name flashes over the preview');
      final filtered = tester.widget<ColorFiltered>(find.byType(ColorFiltered).first);
      expect(filtered.colorFilter, ColorFilter.matrix(VibeFilters.byId('warm').matrix));
      await pumpFor(tester, 1200);
    });

    testWidgets('recording stops itself at the limit and hands the clip back', (tester) async {
      final launcher = await open(
        tester,
        VibeCameraConfig(exporter: exporter, edit: false, maxDuration: const Duration(seconds: 3)),
      );
      await tester.tap(find.byKey(const ValueKey('vibe-record')));
      await pumpFor(tester, 400);
      expect(session.recording, isTrue);
      expect(find.text('0:00 / 0:03'), findsOneWidget);
      await pumpFor(tester, 3300);
      await pumpFor(tester, 600);
      expect(session.stops, 1);
      expect(launcher.closed, isTrue);
      expect(launcher.result, isNotNull);
      expect(launcher.result!.fps, 120);
      expect(launcher.result!.duration, const Duration(seconds: 3));
      expect(File(launcher.result!.file.path).existsSync(), isTrue);
    });

    testWidgets('too short a clip is not kept', (tester) async {
      final launcher = await open(
        tester,
        VibeCameraConfig(exporter: exporter, edit: false, minDuration: const Duration(seconds: 2)),
      );
      await tester.tap(find.byKey(const ValueKey('vibe-record')));
      await pumpFor(tester, 500);
      await tester.tap(find.byKey(const ValueKey('vibe-record')));
      await pumpFor(tester, 200);
      expect(find.text('Record a little longer'), findsOneWidget);
      expect(launcher.closed, isFalse);
      await pumpFor(tester, 1200);
    });

    testWidgets('access refused: says so, offers settings', (tester) async {
      var settings = 0;
      await open(
        tester,
        VibeCameraConfig(exporter: exporter, onOpenSettings: () => settings++),
        using: ({required lens, required preferredFps, required enableAudio}) async =>
            throw const VibeCameraDenied('CameraAccessDenied'),
      );
      expect(find.text('Allow camera and microphone access to record.'), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      expect(settings, 1);
    });
  });

  // The record button got stuck when a camera call never answered: the iOS
  // plugin keeps one camera, closes it on any dispose, and then never
  // answers a start or stop. These are the ways that happened.
  group('the camera never sticks', () {
    late FakeCameras cameras;
    final record = find.byKey(const ValueKey('vibe-record'));
    final preview = find.byKey(const ValueKey('fake-preview'));
    const startFailed = "The camera couldn't start. Please try again.";
    const recordFailed = "The video didn't record. Please try again.";

    setUp(() => cameras = FakeCameras());

    Future<LauncherState> openCameras(WidgetTester tester, [VibeCameraConfig? config]) {
      // Lifecycle changes stay on the binding: put it back afterwards.
      addTearDown(() {
        final b = tester.binding;
        if (b.lifecycleState != AppLifecycleState.resumed) {
          for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
            b.handleAppLifecycleStateChanged(s);
          }
        }
      });
      return open(tester, config ?? VibeCameraConfig(exporter: exporter, edit: false), using: cameras.open);
    }

    void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
      for (final s in states) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
    }

    Future<void> recordFor(WidgetTester tester, int ms) async {
      await tester.tap(record);
      await pumpFor(tester, ms);
      await tester.tap(record);
      await pumpFor(tester, 400);
    }

    testWidgets('a start that never answers frees the button and opens a fresh camera', (tester) async {
      cameras.setUp = (s, i) => s.hangStart = i == 0;
      final launcher = await openCameras(tester);
      await tester.tap(record);
      await pumpFor(tester, 6200);
      expect(find.text(startFailed), findsOneWidget);
      await pumpFor(tester, 1000);
      expect(cameras.opens, 2);
      expect(cameras.sessions.first.disposed, isTrue);
      expect(cameras.maxOpenAtOnce, 1);
      await recordFor(tester, 1300);
      expect(launcher.result, isNotNull, reason: 'the button records again');
    });

    testWidgets('a stop that never answers says so, and a fresh camera records', (tester) async {
      cameras.setUp = (s, i) => s.hangStop = i == 0;
      final launcher = await openCameras(tester);
      await recordFor(tester, 1300);
      expect(launcher.closed, isFalse);
      await pumpFor(tester, 10000);
      expect(find.text(recordFailed), findsOneWidget);
      await pumpFor(tester, 1000);
      expect(cameras.opens, 2);
      expect(cameras.sessions.first.disposed, isTrue);
      expect(cameras.log.where((l) => l == 'cam1 stop'), hasLength(1), reason: 'not asked to stop twice');
      await recordFor(tester, 1300);
      expect(launcher.result, isNotNull);
    });

    testWidgets('a stop that fails, or an empty file, says so instead of handing it on', (tester) async {
      cameras.setUp = (s, i) {
        s.failStop = i == 0;
        s.emptyFile = i == 1;
      };
      final launcher = await openCameras(tester);
      await recordFor(tester, 1300);
      expect(find.text(recordFailed), findsOneWidget);
      await pumpFor(tester, 1000);
      await recordFor(tester, 1300);
      expect(find.text(recordFailed), findsOneWidget);
      expect(launcher.closed, isFalse);
      await pumpFor(tester, 1000);
      expect(cameras.opens, 3);
      await recordFor(tester, 1300);
      expect(launcher.result, isNotNull);
    });

    testWidgets('a permission prompt while opening opens one camera, not two', (tester) async {
      cameras.gate = Completer<void>();
      await openCameras(tester);
      lifecycle(tester, [AppLifecycleState.inactive]);
      await pumpFor(tester, 300);
      lifecycle(tester, [AppLifecycleState.resumed]);
      cameras.gate!.complete();
      cameras.gate = null;
      await pumpFor(tester, 300);
      expect(cameras.log.where((l) => l.startsWith('open')), hasLength(1));
      expect(preview, findsOneWidget);
    });

    testWidgets('the notification shade does not stop a recording', (tester) async {
      await openCameras(tester);
      await tester.tap(record);
      await pumpFor(tester, 600);
      lifecycle(tester, [AppLifecycleState.inactive]);
      await pumpFor(tester, 300);
      lifecycle(tester, [AppLifecycleState.resumed]);
      await pumpFor(tester, 300);
      expect(cameras.last.recording, isTrue);
      expect(cameras.opens, 1);
    });

    testWidgets('leaving mid-recording keeps the clip; the camera closes only after the stop', (tester) async {
      final launcher = await openCameras(tester);
      await tester.tap(record);
      await pumpFor(tester, 1300);
      lifecycle(tester, [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
      await pumpFor(tester, 400);
      expect(cameras.log, ['open front', 'cam1 start', 'cam1 stop', 'cam1 dispose']);
      expect(launcher.result, isNotNull);
    });

    testWidgets('leaving lets the camera go; coming back opens a fresh one', (tester) async {
      await openCameras(tester, VibeCameraConfig(exporter: exporter));
      lifecycle(tester, [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
      await pumpFor(tester, 200);
      expect(cameras.sessions.single.disposed, isTrue);
      lifecycle(tester, [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
      await pumpFor(tester, 300);
      expect(cameras.opens, 2);
      expect(cameras.maxOpenAtOnce, 1);
      expect(preview, findsOneWidget);
    });

    testWidgets('switching lenses twice while it opens never holds two cameras', (tester) async {
      await openCameras(tester);
      final flip = find.byIcon(Icons.flip_camera_ios_rounded);
      cameras.gate = Completer<void>();
      await tester.tap(flip);
      await pumpFor(tester, 100);
      await tester.tap(flip);
      await pumpFor(tester, 100);
      cameras.gate!.complete();
      cameras.gate = null;
      await pumpFor(tester, 400);
      expect(cameras.maxOpenAtOnce, 1);
      expect(cameras.openNow, 1);
      expect(cameras.last.lens, VibeLens.front, reason: 'flipped twice: back where it started');
      expect(preview, findsOneWidget);
    });

    testWidgets('closing mid-recording stops the recording before the camera closes', (tester) async {
      final launcher = await openCameras(tester);
      await tester.tap(record);
      await pumpFor(tester, 800);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await pumpFor(tester, 600);
      expect(launcher.closed, isTrue);
      expect(launcher.result, isNull);
      expect(cameras.log, ['open front', 'cam1 start', 'cam1 stop', 'cam1 dispose']);
    });

    testWidgets('no camera is held under the editor; a retake opens one again', (tester) async {
      exporter = FakeExporter(info: const VibeVideoInfo(duration: Duration(seconds: 2), size: Size(720, 1280)));
      await openCameras(tester, VibeCameraConfig(exporter: exporter, maxDuration: const Duration(seconds: 2)));
      await tester.tap(record);
      await pumpFor(tester, 3200);
      expect(find.byKey(const ValueKey('vibe-done')), findsOneWidget, reason: 'the editor is open');
      expect(cameras.sessions.single.disposed, isTrue);
      await tester.tap(find.text('Retake'));
      await pumpFor(tester, 600);
      expect(cameras.opens, 2);
      expect(preview, findsOneWidget);
      await tester.tap(record);
      await pumpFor(tester, 3200);
      expect(find.byKey(const ValueKey('vibe-done')), findsOneWidget, reason: 'and records again');
      expect(cameras.last.disposed, isTrue);
    });
  });

  group('editor', () {
    Future<LauncherState> recordAndEdit(WidgetTester tester) async {
      final launcher = await open(tester, VibeCameraConfig(exporter: exporter, maxDuration: const Duration(seconds: 2)));
      await tester.tap(find.byKey(const ValueKey('vibe-record')));
      await pumpFor(tester, 2400);
      await pumpFor(tester, 800);
      expect(find.byKey(const ValueKey('vibe-done')), findsOneWidget, reason: 'the editor is open');
      return launcher;
    }

    testWidgets('nothing changed: the recording comes back as it is', (tester) async {
      exporter = FakeExporter(info: const VibeVideoInfo(duration: Duration(seconds: 2), size: Size(720, 1280)));
      final launcher = await recordAndEdit(tester);
      await tester.tap(find.byKey(const ValueKey('vibe-done')));
      await pumpFor(tester, 600);
      expect(exporter.jobs, isEmpty, reason: 'no re-encode');
      expect(launcher.result!.edited, isFalse);
    });

    testWidgets('a recording that mirrors its preview is shown flipped and always saved flipped', (tester) async {
      session = FakeSession(mirrorRecording: true);
      exporter = FakeExporter(info: const VibeVideoInfo(duration: Duration(seconds: 2), size: Size(720, 1280)));
      final launcher = await recordAndEdit(tester);
      expect(flipOf(tester), -1, reason: 'the editor shows what the camera showed');
      await tester.tap(find.byKey(const ValueKey('vibe-done')));
      await pumpFor(tester, 800);
      expect(exporter.jobs, hasLength(1), reason: 'untouched, but the flip has to be baked in');
      expect(exporter.jobs.single.mirror, isTrue);
      expect(launcher.result!.edited, isTrue);
      expect(launcher.result!.file.path, contains('vibe_out_'));
    });

    testWidgets('a recording that already looks like its preview is not flipped', (tester) async {
      session = FakeSession(lens: VibeLens.back);
      await recordAndEdit(tester);
      expect(flipOf(tester), 1);
      await tester.tap(find.byKey(const ValueKey('vibe-edit-filter-warm')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('vibe-done')));
      await pumpFor(tester, 800);
      expect(exporter.jobs.single.mirror, isFalse);
    });

    testWidgets('look, crop and a caption are baked in on Done', (tester) async {
      final launcher = await recordAndEdit(tester);
      await tester.tap(find.byKey(const ValueKey('vibe-edit-filter-warm')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('vibe-tool-crop')));
      await tester.pump();
      // Every shape shows by name before any is picked.
      for (final name in ['Original', '9:16', '4:5', '1:1']) {
        expect(find.text(name), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('vibe-crop-square')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('vibe-tool-text')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('vibe-add-text')));
      await pumpFor(tester, 400);
      await tester.enterText(find.byKey(const ValueKey('vibe-text-field')), 'Hello Vibe');
      await tester.tap(find.byKey(const ValueKey('vibe-text-done')));
      await pumpFor(tester, 400);
      await tester.tap(find.byKey(const ValueKey('vibe-done')));
      await pumpFor(tester, 800);

      expect(exporter.jobs, hasLength(1));
      final job = exporter.jobs.single;
      expect(job.edit.filter.id, 'warm');
      expect(job.edit.aspect, VibeCropAspect.square);
      expect(job.outputSize, const Size(720, 720));
      expect(job.edit.texts.single.text, 'Hello Vibe');
      expect(launcher.result!.edited, isTrue);
      expect(launcher.result!.filterId, 'warm');
      expect(launcher.result!.size, const Size(720, 720));
    });

    testWidgets('the trim handles keep only the part chosen', (tester) async {
      await recordAndEdit(tester);
      await tester.tap(find.byKey(const ValueKey('vibe-tool-trim')));
      await tester.pump();
      await tester.drag(find.byKey(const ValueKey('vibe-trim-start')), const Offset(80, 0));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('vibe-done')));
      await pumpFor(tester, 800);
      final trim = exporter.jobs.single.edit.trim;
      expect(trim.start, greaterThan(Duration.zero));
      expect(trim.end, const Duration(seconds: 2), reason: 'capped at the clip limit');
    });

    testWidgets('a failed save says so and keeps the edit', (tester) async {
      exporter.fail = true;
      final launcher = await recordAndEdit(tester);
      await tester.tap(find.byKey(const ValueKey('vibe-edit-filter-vivid')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('vibe-done')));
      await pumpFor(tester, 600);
      expect(find.text("Couldn't save the video. Please try again."), findsOneWidget);
      expect(find.byKey(const ValueKey('vibe-done')), findsOneWidget, reason: 'still editing');
      expect(launcher.closed, isFalse);
      await pumpFor(tester, 4500);
    });
  });

  group('gallery', () {
    testWidgets('no picker given: record only, no gallery button', (tester) async {
      await open(tester, VibeCameraConfig(exporter: exporter));
      expect(find.byKey(const ValueKey('vibe-camera-gallery')), findsNothing);
      await pumpFor(tester, 600);
    });

    testWidgets('a picked video goes through the editor and comes back, never flipped', (tester) async {
      // Even while the open camera is one whose recordings get flipped.
      session = FakeSession(mirrorRecording: true);
      exporter = FakeExporter(info: const VibeVideoInfo(duration: Duration(seconds: 90), size: Size(720, 1280)));
      final picked = File('${Directory.systemTemp.path}/vibe_gallery_${DateTime.now().microsecondsSinceEpoch}.mp4')
        ..writeAsBytesSync([0, 0, 0]);
      var asked = 0;
      final launcher = await open(
        tester,
        VibeCameraConfig(
          exporter: exporter,
          maxDuration: const Duration(seconds: 30),
          pickFromGallery: () async {
            asked++;
            return picked;
          },
        ),
      );
      expect(find.text('Gallery'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('vibe-camera-gallery')));
      await pumpFor(tester, 800);
      expect(asked, 1);
      expect(find.byKey(const ValueKey('vibe-done')), findsOneWidget, reason: 'the editor is open');
      expect(flipOf(tester), 1);
      await tester.tap(find.byKey(const ValueKey('vibe-done')));
      await pumpFor(tester, 800);
      expect(exporter.jobs.single.mirror, isFalse);
      final result = launcher.result!;
      expect(result.duration, lessThanOrEqualTo(const Duration(seconds: 30)),
          reason: 'a long gallery video is trimmed to the limit');
    });

    testWidgets('closing the picker keeps the camera open', (tester) async {
      final launcher = await open(
        tester,
        VibeCameraConfig(exporter: exporter, pickFromGallery: () async => null),
      );
      await tester.tap(find.byKey(const ValueKey('vibe-camera-gallery')));
      await pumpFor(tester, 600);
      expect(launcher.result, isNull);
      expect(find.byKey(const ValueKey('vibe-camera-gallery')), findsOneWidget);
      await pumpFor(tester, 600);
    });
  });
}
