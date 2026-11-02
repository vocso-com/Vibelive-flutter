import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_camera/vibe_camera.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/fakes.dart';

void main() {
  late FakeSession session;
  late FakeExporter exporter;

  setUp(() {
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

    testWidgets('a picked video goes through the editor and comes back', (tester) async {
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
      await tester.tap(find.byKey(const ValueKey('vibe-done')));
      await pumpFor(tester, 800);
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
