import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../../../core/storage/app_prefs.dart';
import '../../../../core/utils/log.dart';
import '../../../api/client/client_models.dart';
import '../../../api/hosthub/catalog_models.dart';
import '../../../api/hosthub/profile_models.dart';
import 'draft_models.dart';
import 'host_steps.dart';
import 'validation.dart';

/// The flow's state: one notifier per field, so each control rebuilds alone
/// (typing never rebuilds a step). Every change is written to prefs (per
/// account) shortly after, so leaving and coming back resumes on the same
/// step with the same answers.
class HostDraftController {
  HostDraftController(this.userKey, {this.persist = true}) {
    _all = Listenable.merge([
      step,
      name,
      handle,
      tagline,
      bio,
      gender,
      languages,
      state,
      district,
      topics,
      photos,
      voiceIntro,
      videoIntro,
      audioOn,
      videoOn,
      audioRate,
      videoRate,
      availableNow,
      vacation,
      week,
      agreed,
    ]);
    _all.addListener(_schedulePersist);
  }

  /// Restores the saved draft of [userKey], if any.
  factory HostDraftController.load(String userKey) {
    final draft = HostDraftController(userKey);
    final raw = AppPrefs.getString(storageKey(userKey));
    if (raw != null) {
      try {
        final json = jsonDecode(raw);
        if (json is Map) draft.restore(json);
      } catch (e) {
        Log.w('HostDraft', 'unreadable draft dropped: $e');
      }
    }
    return draft;
  }

  static const _prefix = 'hostflow_draft_v1';
  static String storageKey(String userKey) => '$_prefix:$userKey';

  static const defaultAudioRate = 25;
  static const defaultVideoRate = 35;

  final String userKey;

  /// False for the edit screens (schedule / rates): nothing is saved.
  final bool persist;
  late final Listenable _all;
  Timer? _persistTimer;
  bool _closed = false;

  final step = ValueNotifier(HostStep.intro);
  final name = TextEditingController();
  final handle = TextEditingController();
  final tagline = TextEditingController();
  final bio = TextEditingController();

  /// `Male` / `Female` / `Others` (backend values).
  final gender = ValueNotifier<String?>(null);
  final languages = ValueNotifier<List<HostOption>>(const []);
  final state = ValueNotifier<GeoOption?>(null);
  final district = ValueNotifier<GeoOption?>(null);
  final topics = ValueNotifier<List<HostTopic>>(const []);
  final photos = ValueNotifier<List<HostDraftPhoto>>(const []);
  final voiceIntro = ValueNotifier<HostVoiceIntro?>(null);

  /// Optional, and never gates a step: [HostValidation] does not ask for it, so
  /// a host who skips it is not held up. Added for existing hosts rather than
  /// as a thirteenth onboarding step.
  final videoIntro = ValueNotifier<HostVideoIntro?>(null);

  /// Off until the host turns a format on (then at the backend minimum).
  final audioOn = ValueNotifier(false);
  final videoOn = ValueNotifier(false);
  final audioRate = ValueNotifier(defaultAudioRate);
  final videoRate = ValueNotifier(defaultVideoRate);

  /// "Call any time" (`callAnyTime`).
  final availableNow = ValueNotifier(true);

  /// Vacation mode (`vocationMode`): no calls. With [availableNow] it makes
  /// the three exclusive modes of RN ScheduleScreen; both off means the
  /// weekly slots apply ([mode]).
  final vacation = ValueNotifier(false);
  final week = ValueNotifier(HostDaySlot.defaultWeek());
  final agreed = ValueNotifier(false);

  /// Why Continue was refused, shown above the button (not saved). Any
  /// edit clears it.
  final notice = ValueNotifier<HostIssue?>(null);

  /// "Try another suggestion" pages (not saved).
  final taglineSeed = ValueNotifier(0);
  final bioSeed = ValueNotifier(0);

  /// Set once the profile exists (an earlier submit got that far, or the
  /// user is already a host), so a retry updates instead of creating.
  String? expertId;

  /// Prefill from personal info ran (it never overwrites answers).
  bool seeded = false;

  /// "Get started" was tapped once: the intro offers "Continue setup".
  bool started = false;

  /// The language default was applied once (the user may clear it).
  bool languagesSeeded = false;

  /// Topics were read from the host's saved expertise once.
  bool topicsSeeded = false;

  bool get hasProgress => step.value != HostStep.intro;

  /// Disposed (the screen is gone): late async results must not write.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  void restore(Map json) {
    step.value = HostStep.fromName(json['step']?.toString());
    name.text = '${json['name'] ?? ''}';
    handle.text = '${json['handle'] ?? ''}';
    tagline.text = '${json['tagline'] ?? ''}';
    bio.text = '${json['bio'] ?? ''}';
    gender.value = HostProfile.normalizeGender(json['gender']?.toString());
    languages.value = [
      if (json['languages'] is List)
        for (final l in json['languages'] as List) ?DraftJson.languageFrom(l),
    ];
    state.value = _geo(json['state']);
    district.value = _geo(json['district']);
    topics.value = [
      if (json['topics'] is List)
        for (final t in json['topics'] as List)
          if (t is Map) HostTopic.fromJson(t),
    ];
    photos.value = [
      if (json['photos'] is List)
        for (final p in json['photos'] as List)
          if (p is Map && p['mediaId'] != null) HostDraftPhoto.fromJson(p),
    ];
    // A recording whose file is gone (cleared storage) falls back to the
    // saved intro instead of failing the upload.
    final voice = HostVoiceIntro.fromJson(json['voiceIntro']);
    voiceIntro.value = switch (voice?.path) {
      final p? when !File(p).existsSync() => voice!.withoutRecording(),
      _ => voice,
    };
    // Same fallback for the clip: a camera capture lives in a cache directory
    // the OS is free to clear, and a vanished file must not fail the save.
    final clip = HostVideoIntro.fromJson(json['videoIntro']);
    videoIntro.value = switch (clip?.path) {
      final p? when !File(p).existsSync() => clip!.withoutRecording(),
      _ => clip,
    };
    audioOn.value = json['audioOn'] == true;
    videoOn.value = json['videoOn'] == true;
    audioRate.value = _int(json['audioRate']) ?? defaultAudioRate;
    videoRate.value = _int(json['videoRate']) ?? defaultVideoRate;
    availableNow.value = json['availableNow'] != false;
    vacation.value = json['vacation'] == true;
    if (vacation.value) availableNow.value = false;
    final savedWeek = json['week'];
    if (savedWeek is Map) {
      week.value = {
        for (final d in HostWeekday.values)
          d: savedWeek[d.name] is Map
              ? HostDaySlot.fromJson(savedWeek[d.name] as Map)
              : HostDaySlot.defaultWeek()[d]!,
      };
    }
    agreed.value = json['agreed'] == true;
    expertId = json['expertId']?.toString();
    seeded = json['seeded'] == true;
    started = json['started'] == true;
    languagesSeeded = json['languagesSeeded'] == true;
    topicsSeeded = json['topicsSeeded'] == true;
  }

  Map<String, dynamic> toJson() => {
    'step': step.value.name,
    'name': name.text,
    'handle': handle.text,
    'tagline': tagline.text,
    'bio': bio.text,
    'gender': gender.value,
    'languages': [for (final l in languages.value) DraftJson.language(l)],
    'state': state.value?.toJson(),
    'district': district.value?.toJson(),
    'topics': [for (final t in topics.value) t.toJson()],
    'photos': [for (final p in photos.value) ?p.toJson()],
    'voiceIntro': voiceIntro.value?.toJson(),
    'videoIntro': videoIntro.value?.toJson(),
    'audioOn': audioOn.value,
    'videoOn': videoOn.value,
    'audioRate': audioRate.value,
    'videoRate': videoRate.value,
    'availableNow': availableNow.value,
    'vacation': vacation.value,
    'week': {for (final e in week.value.entries) e.key.name: e.value.toJson()},
    'agreed': agreed.value,
    'expertId': expertId,
    'seeded': seeded,
    'started': started,
    'languagesSeeded': languagesSeeded,
    'topicsSeeded': topicsSeeded,
  };

  // ── Edits used by several steps ─────────────────────────────────────────

  void toggleTopic(HostTopic topic) {
    final list = [...topics.value];
    if (!list.remove(topic)) list.add(topic);
    topics.value = list;
  }

  /// Exactly one of vacation / call any time / weekly slots is on.
  HostAvailability get mode => vacation.value
      ? HostAvailability.vacation
      : (availableNow.value
            ? HostAvailability.available
            : HostAvailability.custom);

  set mode(HostAvailability next) {
    vacation.value = next == HostAvailability.vacation;
    availableNow.value = next == HostAvailability.available;
  }

  void setDay(HostWeekday day, HostDaySlot slot) =>
      week.value = {...week.value, day: slot};

  void updatePhoto(String key, HostDraftPhoto Function(HostDraftPhoto) edit) {
    photos.value = [for (final p in photos.value) p.key == key ? edit(p) : p];
  }

  // ── Persistence ─────────────────────────────────────────────────────────

  void _schedulePersist() {
    notice.value = null;
    if (_closed || !persist) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 350), flush);
  }

  /// Writes the draft now (step changes, leaving the screen).
  void flush() {
    _persistTimer?.cancel();
    if (_closed || !persist) return;
    AppPrefs.setString(storageKey(userKey), jsonEncode(toJson())).ignore();
  }

  /// After a successful submit: forget the draft for good.
  Future<void> clear() async {
    _closed = true;
    _persistTimer?.cancel();
    await AppPrefs.remove(storageKey(userKey));
  }

  void dispose() {
    flush();
    _closed = true;
    _disposed = true;
    _all.removeListener(_schedulePersist);
    for (final c in [name, handle, tagline, bio]) {
      c.dispose();
    }
    for (final n in <ChangeNotifier>[
      step,
      gender,
      languages,
      state,
      district,
      topics,
      photos,
      voiceIntro,
      videoIntro,
      audioOn,
      videoOn,
      audioRate,
      videoRate,
      availableNow,
      vacation,
      week,
      agreed,
      taglineSeed,
      bioSeed,
      notice,
    ]) {
      n.dispose();
    }
  }

  static GeoOption? _geo(dynamic json) =>
      json is Map ? GeoOption(Map<String, dynamic>.from(json)) : null;

  static int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v');
}
