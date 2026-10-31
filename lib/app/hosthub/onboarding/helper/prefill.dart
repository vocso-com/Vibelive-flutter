import 'package:flutter/widgets.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/network/strapi.dart';
import '../../../api/client/client_models.dart';
import '../../../client/personal_info/helper/gender_answer.dart';
import '../../../api/hosthub/catalog_models.dart';
import '../../../api/hosthub/profile_models.dart';
import 'draft_controller.dart';
import 'draft_models.dart';
import '../../../api/client/profile_api.dart';

/// Fills a new draft from what the app already knows: Personal Info (name,
/// location, photo), the user's interests answers (gender), and, for a host
/// resubmitting, their saved host profile. Never overwrites an answer.
///
/// With no saved location the Location field fills it from the device's
/// current location (basic_profile_step `_Location`).
abstract final class HostPrefill {
  static void apply(
    HostDraftController d,
    UserWithExpert me, {
    HostProfile? host,
    Map<String, List<String>> answers = const {},
  }) {
    if (d.seeded) return;
    void text(TextEditingController c, String? value) {
      final v = (value ?? '').trim();
      if (c.text.trim().isEmpty && v.isNotEmpty) c.text = v;
    }

    text(d.name, me.name);
    d.state.value ??= me.state ?? _named(me.addressJson['state']);
    d.district.value ??= me.district ?? _named(me.addressJson['district']);
    d.gender.value ??=
        host?.gender ??
        userGenderLabel(me.user['gender']) ??
        genderFromAnswers(answers);

    if (host != null) _fromHost(d, host, text);
    text(d.handle, suggestHandle(me.name));
    final picId = me.profilePicId;
    if (d.photos.value.isEmpty && picId != null) {
      d.photos.value = [
        HostDraftPhoto(key: 'm$picId', mediaId: picId, url: me.profilePicUrl),
      ];
    }
    d.seeded = true;
    d.flush();
  }

  static void _fromHost(
    HostDraftController d,
    HostProfile host,
    void Function(TextEditingController, String?) text,
  ) {
    if (host.key.isNotEmpty) d.expertId ??= host.key;
    text(d.handle, host.handler);
    text(d.tagline, host.tagline);
    text(d.bio, host.descriptions);
    if (d.languages.value.isEmpty && host.languages.isNotEmpty) {
      d.languages.value = host.languages;
      d.languagesSeeded = true;
    }
    if (d.photos.value.isEmpty) {
      // Every saved photo, even past the 3 slots (an older app could save a
      // 4th): a hidden one could neither be seen nor removed, and save would
      // drop it silently. The step asks to remove down to 3.
      d.photos.value = [
        for (final img in host.profileImages)
          if (img.imageId != null)
            HostDraftPhoto(
              key: 'm${img.imageId}',
              mediaId: img.imageId,
              url: img.imageUrl,
            ),
      ];
    }
    if (d.voiceIntro.value == null && host.audioIntroUrl != null) {
      d.voiceIntro.value = HostVoiceIntro(
        savedMediaId: host.audioIntroMediaId,
        savedUrl: host.audioIntroUrl,
      );
    }
    if (d.videoIntro.value == null && host.videoIntroUrl != null) {
      d.videoIntro.value = HostVideoIntro(
        savedMediaId: host.videoIntroMediaId,
        savedUrl: host.videoIntroUrl,
      );
    }
    hostSettings(d, host);
  }

  /// Rates, "available now" and the weekly schedule of a saved profile
  /// (also seeds the host's schedule / rates edit screens).
  static void hostSettings(HostDraftController d, HostProfile host) {
    final rates = host.rates;
    if (rates.hasAny) {
      d.audioOn.value = rates.voiceCallRate > 0;
      d.videoOn.value = rates.videoCallRate > 0;
      if (rates.voiceCallRate > 0) {
        d.audioRate.value = rates.voiceCallRate.round();
      }
      if (rates.videoCallRate > 0) {
        d.videoRate.value = rates.videoCallRate.round();
      }
    }
    d.mode = host.availability;
    final week = host.weeklySchedule;
    if (week.values.any((slots) => slots.isNotEmpty)) {
      d.week.value = {
        for (final day in HostWeekday.values)
          day: (week[day] ?? const []).isEmpty
              ? HostDaySlot.off
              : HostDaySlot(
                  enabled: true,
                  slots: [
                    for (final s in week[day]!)
                      HostSlot(s.startMinutes, s.endMinutes),
                  ],
                ),
      };
    }
  }

  /// Languages default once: English, plus the app's language when it is
  /// another one (Hindi UI → Hindi, Tamil UI → Tamil…).
  static void seedLanguages(
    HostDraftController d,
    List<HostOption> catalog,
    Locale locale,
  ) {
    if (d.languagesSeeded || d.languages.value.isNotEmpty) return;
    final wanted = {
      'english',
      AppI18n.languageOf(locale).englishName.toLowerCase(),
    };
    d.languages.value = [
      for (final o in catalog)
        if (wanted.contains(languageKey(o.label))) o,
    ];
    d.languagesSeeded = true;
    d.flush();
  }

  /// A handle from the name: "Aanya Sharma" → "aanyasharma".
  static String suggestHandle(String? name) {
    final h = HostProfile.sanitizeHandle((name ?? '').replaceAll(' ', ''));
    if (h.length < 3) return '';
    return h.length > 30 ? h.substring(0, 30) : h;
  }

  /// The "How do you identify?" answer (where Personal Info saves the
  /// gender), as a host gender.
  static String? genderFromAnswers(Map<String, List<String>> answers) =>
      GenderAnswer.fromAnswers(answers);

  /// English name of a catalog language (labels come in native script).
  static String languageKey(String label) {
    final l = label.trim().toLowerCase();
    return _nativeNames[l] ?? l;
  }

  static const _nativeNames = {
    'हिंदी': 'hindi',
    'हिन्दी': 'hindi',
    'বাংলা': 'bengali',
    'தமிழ்': 'tamil',
    'తెలుగు': 'telugu',
    'मराठी': 'marathi',
    'ਪੰਜਾਬੀ': 'punjabi',
    'ગુજરાતી': 'gujarati',
    'ಕನ್ನಡ': 'kannada',
    'ଓଡ଼ିଆ': 'odia',
    'ଓଡିଆ': 'odia',
    'മലയാളം': 'malayalam',
    'اردو': 'urdu',
    'हरियाणवी': 'haryanvi',
  };

  static GeoOption? _named(dynamic name) {
    final n = (J.str(name) ?? '').trim();
    return n.isEmpty ? null : GeoOption({'name': n});
  }
}
