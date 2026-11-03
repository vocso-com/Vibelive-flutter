import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_camera/vibe_camera.dart';
import 'package:vibe_camera/src/capture/camera_session.dart';
import 'package:camera/camera.dart' show ResolutionPreset;

List<double> px(List<double> m, double r, double g, double b) =>
    VibeColorMatrix.apply(m, [r, g, b, 255]);

void main() {
  group('colour matrix', () {
    test('identity changes nothing; chaining applies in order', () {
      expect(px(VibeColorMatrix.identity, 10, 20, 30), [10, 20, 30, 255]);
      final up = VibeColorMatrix.brightness(0.5); // +40
      final double2 = VibeColorMatrix.tint(2, 2, 2);
      // +40 then ×2 ≠ ×2 then +40.
      expect(px(VibeColorMatrix.concat(up, double2), 10, 10, 10)[0], 100);
      expect(px(VibeColorMatrix.concat(double2, up), 10, 10, 10)[0], 60);
      expect(px(VibeColorMatrix.chain([up, double2]), 10, 10, 10)[0], 100);
    });

    test('brightness, contrast, saturation, warmth move colour the right way', () {
      expect(px(VibeColorMatrix.brightness(1), 100, 100, 100)[0], greaterThan(100));
      expect(px(VibeColorMatrix.brightness(-1), 100, 100, 100)[0], lessThan(100));
      // Contrast pushes away from mid-grey; mid-grey stays.
      expect(px(VibeColorMatrix.contrast(1), 200, 200, 200)[0], greaterThan(200));
      expect(px(VibeColorMatrix.contrast(1), 128, 128, 128)[0], closeTo(128, 0.01));
      final grey = px(VibeColorMatrix.saturation(0), 255, 0, 0);
      expect(grey[0], closeTo(grey[1], 0.01));
      final warm = px(VibeColorMatrix.warmth(1), 128, 128, 128);
      expect(warm[0], greaterThan(warm[2]));
      expect(VibeColorMatrix.isIdentity(VibeColorMatrix.mix(VibeColorMatrix.sepia, 0)), isTrue);
    });
  });

  group('filters and adjustments', () {
    test('ids are unique; Normal is no change; unknown ids fall back', () {
      final ids = VibeFilters.all.map((f) => f.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(VibeFilters.normal.isNone, isTrue);
      expect(VibeFilters.byId('noir').id, 'noir');
      expect(VibeFilters.byId('nope'), VibeFilters.normal);
      for (final f in VibeFilters.all.skip(1)) {
        expect(f.isNone, isFalse, reason: f.id);
        expect(f.matrix, hasLength(20));
      }
    });

    test('adjustments clamp and compose after the filter', () {
      const a = VibeAdjustments();
      expect(a.isNone, isTrue);
      expect(VibeColorMatrix.isIdentity(a.matrix), isTrue);
      final b = a.copyWith(brightness: 3);
      expect(b.brightness, 1);
      final edit = VibeEdit(
        trim: const VibeTrim(Duration.zero, Duration(seconds: 5)),
        filter: VibeFilters.byId('mono'),
        adjustments: const VibeAdjustments(brightness: 0.5),
      );
      final out = px(edit.matrix, 255, 0, 0);
      expect(out[0], closeTo(out[1], 0.01), reason: 'still grey');
      expect(out[0], greaterThan(px(VibeFilters.byId('mono').matrix, 255, 0, 0)[0]));
    });
  });

  group('crop', () {
    const portrait = Size(720, 1280);
    test('the largest frame of the shape, centred, in even pixels', () {
      expect(VibeCrop.rect(portrait, VibeCropAspect.original), const Rect.fromLTWH(0, 0, 720, 1280));
      expect(VibeCrop.rect(portrait, VibeCropAspect.square), const Rect.fromLTWH(0, 280, 720, 720));
      final fourFive = VibeCrop.rect(portrait, VibeCropAspect.fourFive);
      expect(fourFive.width, 720);
      expect(fourFive.height, 900);
      final odd = VibeCrop.rect(const Size(721, 1279), VibeCropAspect.square);
      expect(odd.width % 2, 0);
      expect(odd.top % 2, 0);
    });

    test('moving the frame stops at the picture edge', () {
      final top = VibeCrop.rect(portrait, VibeCropAspect.square, center: const Offset(0.5, 0));
      expect(top.top, 0);
      final bottom = VibeCrop.rect(portrait, VibeCropAspect.square, center: const Offset(0.5, 1));
      expect(bottom.bottom, 1280);
      expect(VibeCrop.isFull(portrait, VibeCrop.rect(portrait, VibeCropAspect.original)), isTrue);
      expect(VibeCrop.isFull(portrait, top), isFalse);
    });
  });

  group('trim', () {
    const ten = Duration(seconds: 10);
    test('inside the clip, in order, never under the minimum nor over the maximum', () {
      final t = VibeTrim.clamp(start: const Duration(seconds: -2), end: const Duration(seconds: 20), duration: ten);
      expect(t, const VibeTrim(Duration.zero, ten));
      final tight = VibeTrim.clamp(start: const Duration(seconds: 9, milliseconds: 800), end: ten, duration: ten);
      expect(tight.length, const Duration(seconds: 1));
      expect(tight.end, ten);
      final capped = VibeTrim.clamp(start: Duration.zero, end: ten, duration: ten, max: const Duration(seconds: 6));
      expect(capped.end, const Duration(seconds: 6));
      final swapped = VibeTrim.clamp(start: const Duration(seconds: 5), end: const Duration(seconds: 2), duration: ten);
      expect(swapped.length, const Duration(seconds: 1));
      expect(VibeTrim.full(ten, max: const Duration(seconds: 4)).end, const Duration(seconds: 4));
      expect(const VibeTrim(Duration.zero, ten).isFull(ten), isTrue);
    });
  });

  group('edit', () {
    test('untouched only when nothing would change the video', () {
      const ten = Duration(seconds: 10);
      final edit = VibeEdit(trim: VibeTrim.full(ten));
      expect(edit.isUntouched(ten), isTrue);
      expect(edit.copyWith(filter: VibeFilters.byId('warm')).isUntouched(ten), isFalse);
      expect(edit.copyWith(aspect: VibeCropAspect.square).isUntouched(ten), isFalse);
      expect(edit.copyWith(trim: const VibeTrim(Duration(seconds: 1), ten)).isUntouched(ten), isFalse);
      expect(
        edit.copyWith(texts: [const VibeTextOverlay(id: 'a', text: 'hi')]).isUntouched(ten),
        isFalse,
      );
      expect(edit.copyWith(adjustments: const VibeAdjustments(warmth: 0.2)).isUntouched(ten), isFalse);
    });

    test('captions clamp to the frame; text colour suits its box', () {
      const t = VibeTextOverlay(id: 'a', text: 'hi');
      expect(t.copyWith(position: const Offset(2, -1)).position, Offset.zero.translate(1, 0));
      expect(t.copyWith(size: 1).size, 0.14);
      expect(VibeTextOverlay.onColor(const Color(0xFFFFFFFF)), const Color(0xFF111111));
      expect(VibeTextOverlay.onColor(const Color(0xFF111111)), const Color(0xFFFFFFFF));
    });
  });

  group('export job', () {
    test('the output is the crop, or the whole frame', () {
      const info = VibeVideoInfo(duration: Duration(seconds: 5), size: Size(720, 1280), fps: 120);
      VibeExportJob job(VibeCropAspect a) => VibeExportJob(
        source: _file,
        edit: VibeEdit(trim: VibeTrim.full(info.duration), aspect: a),
        info: info,
        quality: VibeExportQuality.p720,
        maxFps: 120,
      );
      expect(job(VibeCropAspect.original).outputSize, const Size(720, 1280));
      expect(job(VibeCropAspect.square).outputSize, const Size(720, 720));
      expect(job(VibeCropAspect.square).bitrate, 5000000);
    });

    test('a crop framed on the flipped preview is mirrored back for the renderer', () {
      const info = VibeVideoInfo(duration: Duration(seconds: 5), size: Size(1280, 720));
      VibeExportJob job({required bool mirror, Offset center = const Offset(0.5, 0.5)}) => VibeExportJob(
        source: _file,
        edit: VibeEdit(trim: VibeTrim.full(info.duration), aspect: VibeCropAspect.square, cropCenter: center),
        info: info,
        quality: VibeExportQuality.p720,
        maxFps: 30,
        mirror: mirror,
      );
      // Framed at the left edge of what was shown…
      final left = job(mirror: true, center: const Offset(0, 0.5));
      expect(left.edit.cropRect(info.size), const Rect.fromLTWH(0, 0, 720, 720));
      // …is the right edge of the unflipped recording.
      expect(left.sourceCrop, const Rect.fromLTWH(560, 0, 720, 720));
      expect(left.outputSize, const Size(720, 720), reason: 'same size either way');
      expect(job(mirror: false, center: const Offset(0, 0.5)).sourceCrop, const Rect.fromLTWH(0, 0, 720, 720));
      expect(job(mirror: true).sourceCrop, const Rect.fromLTWH(280, 0, 720, 720), reason: 'centred stays centred');
      expect(job(mirror: false).mirror, isFalse);
    });
  });

  test('only Android front-camera recordings are the mirror of their preview', () {
    expect(CameraSession.mirrorsRecording(VibeLens.front, TargetPlatform.android), isTrue);
    expect(CameraSession.mirrorsRecording(VibeLens.back, TargetPlatform.android), isFalse);
    expect(CameraSession.mirrorsRecording(VibeLens.front, TargetPlatform.iOS), isFalse,
        reason: 'iOS records the front camera mirrored, as previewed');
    expect(CameraSession.mirrorsRecording(VibeLens.back, TargetPlatform.iOS), isFalse);
  });

  test('frame rates asked for, best first', () {
    expect(CameraSession.attempts(120).map((a) => a.$2), [120, 60, 30, null]);
    expect(CameraSession.attempts(60).map((a) => a.$2), [60, 30, null]);
    expect(CameraSession.attempts(30).map((a) => a.$2), [30, null]);
    expect(CameraSession.attempts(120).first.$1, ResolutionPreset.high);
    expect(CameraSession.videoBitrate(120), 10000000);
    expect(CameraSession.videoBitrate(60), 8000000);
    expect(CameraSession.videoBitrate(30), 6000000);
    expect(CameraSession.videoBitrate(null), 6000000);
  });

  testWidgets('a caption sits in the same box in the preview and the export', (tester) async {
    const t = VibeTextOverlay(id: 'a', text: 'Hello', style: VibeTextStyle.boxed, position: Offset(0.5, 0.25));
    const frame = Size(360, 640);
    final box = VibeTextPainting.box(t, frame);
    expect(box.center, const Offset(180, 160));
    final twice = VibeTextPainting.box(t, frame * 2);
    expect(twice.width, closeTo(box.width * 2, 2), reason: 'scales with the frame');
    final png = await tester.runAsync(() => VibeTextPainting.png([t], frame));
    expect(png, isNotNull);
    expect(png!.take(4), [0x89, 0x50, 0x4E, 0x47], reason: 'a PNG');
  });
}

final _file = File('/tmp/vibe_test.mp4');
