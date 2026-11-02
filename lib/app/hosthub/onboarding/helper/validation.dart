import '../../../api/hosthub/profile_models.dart';
import 'draft_controller.dart';
import 'draft_models.dart';
import 'host_steps.dart';

/// Why Continue is refused: an i18n key and its variables.
typedef HostIssue = ({String key, Map<String, dynamic>? variables});

/// Per-step checks of the draft (pure, so tests drive them directly). The
/// handle's "is it free" check is async and lives in the flow controller.
abstract final class HostValidation {
  /// What the backend keeps (RN `sanitizeProfileHandle`): a–z and `_`.
  static final handlePattern = RegExp(r'^[a-z_]{3,30}$');

  static const nameMin = 2;
  static const taglineMin = 10;
  static const taglineMax = 60;
  static const bioMin = 30;
  static const bioMax = 500;
  static const maxPhotos = 3;

  /// Rate stepper bounds (₹/min); the pricing config can raise the floor.
  static const rateStep = 5;
  static const rateFloor = 5;
  static const rateCeiling = 1000;

  static HostIssue _issue(String key, [Map<String, dynamic>? variables]) =>
      (key: 'hostflow:errors.$key', variables: variables);

  /// Smallest rate the stepper allows: the pricing config's minimum as it
  /// is, [rateFloor] without one.
  static int minRate(double pricingMinimum) {
    // The backend's own minimum (₹7 stays ₹7); the stepper then goes in
    // steps of [rateStep]. No config: [rateFloor].
    final m = pricingMinimum.isFinite ? pricingMinimum.ceil() : 0;
    return m < 1 ? rateFloor : m;
  }

  static HostIssue? check(
    HostStep step,
    HostDraftController d, {
    double minVoiceRate = 0,
    double minVideoRate = 0,
  }) => switch (step) {
    HostStep.basic => basic(d),
    HostStep.interests => d.topics.value.isEmpty ? _issue('interests') : null,
    HostStep.photos => photos(d),
    HostStep.voice => d.voiceIntro.value == null ? _issue('voice') : null,
    // Optional: a host may go on without a video intro.
    HostStep.video => null,
    HostStep.tagline => tagline(d.tagline.text),
    HostStep.bio => bio(d.bio.text),
    HostStep.rates => rates(d, minVoiceRate, minVideoRate),
    HostStep.availability => availability(d),
    HostStep.guidelines => d.agreed.value ? null : _issue('agree'),
    _ => null,
  };

  static HostIssue? basic(HostDraftController d) {
    if (d.name.text.trim().length < nameMin) return _issue('name');
    if (!handlePattern.hasMatch(d.handle.text)) return _issue('handle_invalid');
    if (d.gender.value == null) return _issue('gender');
    if (d.languages.value.isEmpty) return _issue('languages');
    if (d.state.value == null || d.district.value == null) {
      return _issue('location');
    }
    return null;
  }

  static HostIssue? photos(HostDraftController d) {
    final list = d.photos.value;
    if (list.any((p) => p.uploading)) return _issue('photos_uploading');
    if (!list.any((p) => p.uploaded)) return _issue('photos');
    if (list.length > maxPhotos) {
      return _issue('photos_too_many', {'max': maxPhotos});
    }
    return null;
  }

  static HostIssue? tagline(String text) => text.trim().length < taglineMin
      ? _issue('tagline', {'min': taglineMin})
      : null;

  static HostIssue? bio(String text) =>
      text.trim().length < bioMin ? _issue('bio', {'min': bioMin}) : null;

  static HostIssue? rates(
    HostDraftController d,
    double minVoiceRate,
    double minVideoRate,
  ) {
    if (!d.audioOn.value && !d.videoOn.value) return _issue('rates_none');
    final voiceMin = minRate(minVoiceRate);
    if (d.audioOn.value && d.audioRate.value < voiceMin) {
      return _issue('rate_audio_min', {'min': voiceMin});
    }
    final videoMin = minRate(minVideoRate);
    if (d.videoOn.value && d.videoRate.value < videoMin) {
      return _issue('rate_video_min', {'min': videoMin});
    }
    return null;
  }

  static HostIssue? availability(HostDraftController d) {
    // RN ScheduleScreen `handleSave`: vacation and "call any time" need no
    // slots; the weekly mode needs at least one.
    if (d.mode != HostAvailability.custom) return null;
    final slots = [for (final day in d.week.value.values) ...day.slots];
    if (slots.isEmpty) return _issue('availability');
    if (slots.any((s) => s.end - s.start < HostDaySlot.minSlotMinutes)) {
      return _issue('slot_short');
    }
    return null;
  }

  /// Rates as saved: a switched-off call type is 0.
  static HostRates ratesOf(HostDraftController d) => HostRates(
    voiceCallRate: d.audioOn.value ? d.audioRate.value.toDouble() : 0,
    videoCallRate: d.videoOn.value ? d.videoRate.value.toDouble() : 0,
  );
}
