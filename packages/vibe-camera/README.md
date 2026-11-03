# vibe_camera

An in-app camera for short vertical clips, with an editor, as one self-contained
Flutter package. Nothing in it knows about the app that uses it: limits, colours
and every word on screen are passed in, so it drops into any app.

## What it does

**Camera** (`camera` plugin)
- Live looks: 12 colour filters, swiped or picked from the strip, drawn on the GPU
  over the preview (smooth at any frame rate).
- Light: the sensor's own exposure (−/+), so the clip itself is brighter, not a
  filter on top.
- Frame rate: asks for 120 fps first, then 60, then 30, then the device default,
  and shows what it got. 120/60 record at 720p, 30 at 1080p.
- Tap to focus and meter, pinch to zoom, torch (back camera), front/back.
- Record button with a ring that fills to the clip limit and stops there.

**Editor**
- Filters (on the clip's own first frame), Adjust (brightness, contrast,
  saturation, warmth), Trim (frame strip with handles), Crop (original, 9:16,
  4:5, 1:1, drag to frame), Text (captions: colour, plain/box/soft style, size,
  drag to place, drag to the bin to delete).
- Everything previews live and is baked into a new MP4 on Done by
  `pro_video_editor` (native: Media3 on Android, AVFoundation on iOS; no FFmpeg).
  The preview and the export use the same colour matrix and the same caption
  painter, so what you see is what you get. An untouched clip is returned as
  recorded (no re-encode), except Android's front camera: CameraX records it
  unmirrored while the preview is mirrored, so the editor shows it flipped and
  the export bakes that flip in (once). iOS already records it as previewed;
  gallery videos are never flipped.

## Use

```dart
import 'package:vibe_camera/vibe_camera.dart';

final clip = await VibeCamera.open(
  context,
  config: VibeCameraConfig(
    maxDuration: const Duration(seconds: 30), // e.g. from your server
    preferredFps: 120,
    accent: Colors.pink,
    strings: VibeCameraStrings(done: 'Done', /* … translations … */),
    onOpenSettings: openAppSettings, // when access was refused
  ),
);
if (clip != null) {
  // clip.file, clip.duration, clip.recordedAt, clip.size, clip.fps, clip.edited
}
```

## Setup in an app

- Android: `CAMERA` and `RECORD_AUDIO` permissions in the manifest.
- iOS: `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` in
  Info.plist; `CADisableMinimumFrameDurationOnPhone` = true for 120 Hz UI on
  ProMotion phones.

## Layout

- `lib/src/core`: pure logic (colour matrices, filters, adjustments, crop, trim,
  captions, the edit) — unit tested.
- `lib/src/capture`: the camera session (fps fallback) and screen.
- `lib/src/edit`: the editor, trim bar, caption editor.
- `lib/src/export`: `VibeExporter` (probe, thumbnails, render, cancel) and the
  pro_video_editor implementation. Pass your own in `VibeCameraConfig.exporter`
  (tests do).
