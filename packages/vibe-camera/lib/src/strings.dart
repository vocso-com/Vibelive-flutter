import 'package:flutter/foundation.dart';

/// Every word the camera shows. English by default; an app passes its own
/// translations (and [filterNames] by filter id).
@immutable
class VibeCameraStrings {
  const VibeCameraStrings({
    this.close = 'Close',
    this.flip = 'Switch camera',
    this.flash = 'Flash',
    this.light = 'Light',
    this.holdToRecord = 'Tap to record',
    this.tooShort = 'Record a little longer',
    this.cameraDenied = 'Allow camera and microphone access to record.',
    this.cameraFailed = "The camera couldn't start. Please try again.",
    this.openSettings = 'Open settings',
    this.retry = 'Try again',
    this.retake = 'Retake',
    this.done = 'Done',
    this.filters = 'Filters',
    this.adjust = 'Adjust',
    this.trim = 'Trim',
    this.crop = 'Crop',
    this.text = 'Text',
    this.brightness = 'Brightness',
    this.contrast = 'Contrast',
    this.saturation = 'Saturation',
    this.warmth = 'Warmth',
    this.cropOriginal = 'Original',
    this.cropPortrait = '9:16',
    this.cropFourFive = '4:5',
    this.cropSquare = '1:1',
    this.addText = 'Add text',
    this.typeSomething = 'Type something',
    this.dragToDelete = 'Drag here to delete',
    this.saving = 'Saving your video',
    this.saveFailed = "Couldn't save the video. Please try again.",
    this.cancel = 'Cancel',
    this.discardTitle = 'Discard this video?',
    this.discard = 'Discard',
    this.keepEditing = 'Keep editing',
    this.gallery = 'Gallery',
    this.filterNames = const {},
  });

  /// The button that picks a video from the phone instead of recording.
  final String gallery;
  final String close;
  final String flip;
  final String flash;
  final String light;
  final String holdToRecord;
  final String tooShort;
  final String cameraDenied;
  final String cameraFailed;
  final String openSettings;
  final String retry;
  final String retake;
  final String done;
  final String filters;
  final String adjust;
  final String trim;
  final String crop;
  final String text;
  final String brightness;
  final String contrast;
  final String saturation;
  final String warmth;
  final String cropOriginal;
  final String cropPortrait;
  final String cropFourFive;
  final String cropSquare;
  final String addText;
  final String typeSomething;
  final String dragToDelete;
  final String saving;
  final String saveFailed;
  final String cancel;
  final String discardTitle;
  final String discard;
  final String keepEditing;

  /// Translated filter names by id (`warm`, `noir`…); the filter's own name
  /// otherwise.
  final Map<String, String> filterNames;

  String filterName(String id, String fallback) => filterNames[id] ?? fallback;
}
