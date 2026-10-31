import 'package:flutter/foundation.dart';

import '../../../../core/network/strapi.dart';
import '../../../api/hosthub/catalog_models.dart';
import '../../../api/hosthub/profile_models.dart';
import '../../../api/hosthub/profile_patch.dart';

/// A topic of the interests form's topic question (option value + label).
@immutable
class HostTopic {
  const HostTopic({required this.value, required this.label, this.emoji = ''});

  factory HostTopic.fromJson(Map json) => HostTopic(
    value: '${json['value'] ?? ''}',
    label: '${json['label'] ?? ''}',
    emoji: '${json['emoji'] ?? ''}',
  );

  final String value;
  final String label;
  final String emoji;

  JsonMap toJson() => {'value': value, 'label': label, 'emoji': emoji};

  @override
  bool operator ==(Object other) => other is HostTopic && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// One photo slot. [mediaId] is set once the upload finished; [localPath]
/// is the picked file (preview while it uploads).
@immutable
class HostDraftPhoto {
  const HostDraftPhoto({
    required this.key,
    this.mediaId,
    this.url,
    this.localPath,
    this.failed = false,
  });

  factory HostDraftPhoto.fromJson(Map json) => HostDraftPhoto(
    key: '${json['key'] ?? json['mediaId'] ?? ''}',
    mediaId: json['mediaId'],
    url: J.str(json['url']),
    localPath: J.str(json['localPath']),
  );

  /// Stable identity for the tile (survives the upload finishing).
  final String key;
  final Object? mediaId;
  final String? url;
  final String? localPath;

  /// The upload failed; tapping the tile retries.
  final bool failed;

  bool get uploaded => mediaId != null;
  bool get uploading => mediaId == null && !failed;

  HostDraftPhoto copyWith({Object? mediaId, String? url, bool? failed}) =>
      HostDraftPhoto(
        key: key,
        mediaId: mediaId ?? this.mediaId,
        url: url ?? this.url,
        localPath: localPath,
        failed: failed ?? this.failed,
      );

  /// Only uploaded photos are kept: a picked file in the OS temp folder may
  /// be gone by the next launch.
  JsonMap? toJson() => mediaId == null
      ? null
      : {'key': key, 'mediaId': mediaId, 'url': url, 'localPath': localPath};
}

/// The voice intro on the Bio step (RN ProfessionalDetails "Voice Intro"):
/// a new recording on this phone ([path], uploaded on save) and/or the one
/// already on the profile ([savedUrl], left alone: re-sending it would put an
/// approved intro back into review).
@immutable
class HostVoiceIntro {
  const HostVoiceIntro({
    this.path,
    this.seconds = 0,
    this.uploadedId,
    this.savedMediaId,
    this.savedUrl,
  });

  static const maxSeconds = 30;

  static HostVoiceIntro? fromJson(dynamic json) {
    if (json is! Map) return null;
    final intro = HostVoiceIntro(
      path: J.str(json['path']),
      seconds: J.integer(json['seconds']) ?? 0,
      uploadedId: json['uploadedId'],
      savedMediaId: json['savedMediaId'],
      savedUrl: J.str(json['savedUrl']),
    );
    return intro.isEmpty ? null : intro;
  }

  /// A recording made here, not uploaded yet.
  final String? path;

  /// Its length (the saved one's is unknown).
  final int seconds;

  /// Its media id once uploaded in the background (right after it was
  /// recorded); null until then, and the save uploads the file itself.
  final Object? uploadedId;
  final Object? savedMediaId;
  final String? savedUrl;

  bool get isNew => path != null;
  bool get isEmpty => path == null && savedUrl == null;

  /// What the save sends: only a new recording, by id once uploaded.
  HostMediaRef? get upload => switch ((path, uploadedId)) {
    (null, _) => null,
    (_, final Object id) => HostMediaRef.media(id),
    (final String p, null) => HostMediaRef.file(
      p,
      fileName: 'audio-intro-${DateTime.now().millisecondsSinceEpoch}.m4a',
      mimeType: 'audio/mp4',
    ),
  };

  /// [path] recorded now, the saved intro kept as the fallback.
  HostVoiceIntro withRecording(String path, int seconds) => HostVoiceIntro(
    path: path,
    seconds: seconds,
    savedMediaId: savedMediaId,
    savedUrl: savedUrl,
  );

  /// The same recording, uploaded as [id].
  HostVoiceIntro withUploaded(Object id) => HostVoiceIntro(
    path: path,
    seconds: seconds,
    uploadedId: id,
    savedMediaId: savedMediaId,
    savedUrl: savedUrl,
  );

  /// The new recording dropped: back to the saved intro, or nothing.
  HostVoiceIntro? withoutRecording() => savedUrl == null
      ? null
      : HostVoiceIntro(savedMediaId: savedMediaId, savedUrl: savedUrl);

  JsonMap toJson() => {
    'path': path,
    'seconds': seconds,
    'uploadedId': uploadedId,
    'savedMediaId': savedMediaId,
    'savedUrl': savedUrl,
  };
}

/// A host's video intro: the same shape as [HostVoiceIntro], for a clip.
///
/// Deliberately a parallel class rather than a refactor of the voice one. The
/// two hold the same five fields, and folding them into a shared base would
/// mean editing the model the live host onboarding already saves through — a
/// funnel that cannot afford a regression for the sake of forty lines. This
/// duplication is inert data plumbing; the screening rule that MUST stay
/// shared lives server-side, in INTRO_MEDIA.
@immutable
class HostVideoIntro {
  const HostVideoIntro({
    this.path,
    this.seconds = 0,
    this.uploadedId,
    this.savedMediaId,
    this.savedUrl,
  });

  /// Kept short on purpose: this plays on a profile before anyone has paid,
  /// and a human reviews every second of it.
  static const maxSeconds = 30;

  static HostVideoIntro? fromJson(dynamic json) {
    if (json is! Map) return null;
    final intro = HostVideoIntro(
      path: J.str(json['path']),
      seconds: J.integer(json['seconds']) ?? 0,
      uploadedId: json['uploadedId'],
      savedMediaId: json['savedMediaId'],
      savedUrl: J.str(json['savedUrl']),
    );
    return intro.isEmpty ? null : intro;
  }

  /// A clip recorded here, not uploaded yet.
  final String? path;

  /// Its length (the saved one's is unknown).
  final int seconds;

  /// Its media id once uploaded in the background; null until then, and the
  /// save uploads the file itself.
  final Object? uploadedId;
  final Object? savedMediaId;
  final String? savedUrl;

  bool get isNew => path != null;
  bool get isEmpty => path == null && savedUrl == null;

  /// What the save sends: only a new clip, by id once uploaded. A saved clip
  /// sends nothing, so re-saving an unchanged profile cannot re-post it — and
  /// so cannot send an approved clip back to the review queue for no reason.
  HostMediaRef? get upload => switch ((path, uploadedId)) {
    (null, _) => null,
    (_, final Object id) => HostMediaRef.media(id),
    (final String p, null) => HostMediaRef.file(
      p,
      fileName: 'video-intro-${DateTime.now().millisecondsSinceEpoch}.mp4',
      mimeType: 'video/mp4',
    ),
  };

  /// [path] recorded now, the saved clip kept as the fallback.
  HostVideoIntro withRecording(String path, int seconds) => HostVideoIntro(
    path: path,
    seconds: seconds,
    savedMediaId: savedMediaId,
    savedUrl: savedUrl,
  );

  /// The same clip, uploaded as [id].
  HostVideoIntro withUploaded(Object id) => HostVideoIntro(
    path: path,
    seconds: seconds,
    uploadedId: id,
    savedMediaId: savedMediaId,
    savedUrl: savedUrl,
  );

  /// The new clip dropped: back to the saved one, or nothing.
  HostVideoIntro? withoutRecording() => savedUrl == null
      ? null
      : HostVideoIntro(savedMediaId: savedMediaId, savedUrl: savedUrl);

  JsonMap toJson() => {
    'path': path,
    'seconds': seconds,
    'uploadedId': uploadedId,
    'savedMediaId': savedMediaId,
    'savedUrl': savedUrl,
  };
}

/// One time slot of a day, minutes since midnight.
@immutable
class HostSlot {
  const HostSlot(this.start, this.end);

  static HostSlot? fromJson(dynamic json) {
    if (json is! Map) return null;
    final start = J.integer(json['start']);
    final end = J.integer(json['end']);
    return start == null || end == null ? null : HostSlot(start, end);
  }

  final int start;
  final int end;

  /// RN ScheduleScreen `isOverlapping`: touching slots do not overlap.
  bool overlaps(HostSlot other) => start < other.end && other.start < end;

  JsonMap toJson() => {'start': start, 'end': end};

  @override
  bool operator ==(Object other) =>
      other is HostSlot && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// One day of the weekly schedule: on/off and its slots, sorted by start
/// (RN ScheduleScreen). A day that is off has no slots.
@immutable
class HostDaySlot {
  const HostDaySlot({
    required this.enabled,
    List<HostSlot> slots = const [defaultSlot],
  }) : _slots = slots;

  /// 6:00 PM – 12:00 AM, the design's default.
  static const defaultStart = 18 * 60;
  static const defaultEnd = endOfDay;
  static const defaultSlot = HostSlot(defaultStart, defaultEnd);

  /// A slot added with "Add slot" (RN: 9:00 AM, one hour).
  static const newSlotStart = 9 * 60;
  static const newSlotMinutes = 60;

  /// "12:00 AM" as an end time. The backend wants end > start on the same
  /// day (RN rule), so midnight is stored as 23:59.
  static const endOfDay = 23 * 60 + 59;

  /// RN minimum slot length.
  static const minSlotMinutes = 30;

  /// Reads `{enabled, slots: [{start, end}]}`, and the older single-slot
  /// `{enabled, start, end}` drafts.
  factory HostDaySlot.fromJson(Map json) {
    final enabled = json['enabled'] == true;
    final saved = json['slots'];
    final slots = saved is List
        ? [for (final s in saved) ?HostSlot.fromJson(s)]
        : [
            HostSlot(
              J.integer(json['start']) ?? defaultStart,
              J.integer(json['end']) ?? defaultEnd,
            ),
          ];
    return enabled && slots.isNotEmpty
        ? HostDaySlot(enabled: true, slots: sorted(slots))
        : const HostDaySlot(enabled: false);
  }

  final bool enabled;
  final List<HostSlot> _slots;

  List<HostSlot> get slots => enabled ? _slots : const [];

  /// RN `toggleDay`: off clears the slots; on starts with the default slot.
  HostDaySlot toggled(bool on) =>
      on ? (enabled ? this : const HostDaySlot(enabled: true)) : off;

  static const off = HostDaySlot(enabled: false, slots: []);

  /// RN `addSlot` rules for [slot] against the day's other slots (all but
  /// [replacing]): the `hostflow:errors.*` key, or null when it is fine.
  String? check(HostSlot slot, {int? replacing}) {
    if (slot.end <= slot.start) return 'slot_order';
    if (slot.end - slot.start < minSlotMinutes) return 'slot_short';
    for (var i = 0; i < slots.length; i++) {
      if (i != replacing && slots[i].overlaps(slot)) return 'slot_overlap';
    }
    return null;
  }

  /// Adds [slot] (or replaces the one at [replacing]), sorted by start.
  HostDaySlot withSlot(HostSlot slot, {int? replacing}) => HostDaySlot(
    enabled: true,
    slots: sorted([
      for (var i = 0; i < slots.length; i++)
        if (i != replacing) slots[i],
      slot,
    ]),
  );

  /// RN `removeSlot`: the last slot gone turns the day off.
  HostDaySlot withoutSlot(int index) {
    final rest = [...slots]..removeAt(index);
    return rest.isEmpty ? off : HostDaySlot(enabled: true, slots: rest);
  }

  /// Where "Add slot" opens: 9:00 – 10:00 AM (RN), or after the day's last
  /// slot when that hour is taken.
  HostSlot get nextSlot {
    const first = HostSlot(newSlotStart, newSlotStart + newSlotMinutes);
    if (!slots.any(first.overlaps)) return first;
    final s = slots.last.end.clamp(0, 23 * 60);
    return HostSlot(s, (s + newSlotMinutes).clamp(0, endOfDay));
  }

  static List<HostSlot> sorted(List<HostSlot> slots) =>
      [...slots]..sort((a, b) => a.start.compareTo(b.start));

  JsonMap toJson() => {
    'enabled': enabled,
    'slots': [for (final s in slots) s.toJson()],
  };

  /// Mon–Fri on, weekend off (the design's default week).
  static Map<HostWeekday, HostDaySlot> defaultWeek() => {
    for (final d in HostWeekday.values)
      d: d != HostWeekday.saturday && d != HostWeekday.sunday
          ? const HostDaySlot(enabled: true)
          : off,
  };

  @override
  bool operator ==(Object other) =>
      other is HostDaySlot &&
      other.enabled == enabled &&
      listEquals(other.slots, slots);

  @override
  int get hashCode => Object.hash(enabled, Object.hashAll(slots));
}

/// JSON helpers for the option types the draft keeps.
abstract final class DraftJson {
  static JsonMap language(HostOption o) => {
    'id': o.id,
    'documentId': o.documentId,
    'label': o.label,
  };

  static HostOption? languageFrom(dynamic json) {
    if (json is! Map) return null;
    final label = J.str(json['label']) ?? '';
    final option = HostOption(
      id: J.integer(json['id']),
      documentId: J.str(json['documentId']),
      label: label,
      raw: {
        if (json['id'] != null) 'id': json['id'],
        if (json['documentId'] != null) 'documentId': json['documentId'],
        'name': label,
      },
    );
    return option.value == null || label.isEmpty ? null : option;
  }
}
