import '../../../../core/network/strapi.dart';
import '../../../api/authscreen/interests_models.dart';
import '../../../api/client/client_models.dart';
import '../../../api/client/geo_api.dart';
import '../../../api/hosthub/onboarding_models.dart';
import '../../../api/hosthub/profile_models.dart';
import 'draft_controller.dart';
import 'prefill.dart';
import 'topic_catalog.dart';
import 'validation.dart';

/// Turns the finished draft into the submit's API input (pure; the network
/// part is `useSubmitHostOnboarding`).
abstract final class HostSubmitPlan {
  static HostOnboardingInput build(
    HostDraftController d, {
    required String userDocumentId,
    required InterestForm form,
    required UserWithExpert me,
    void Function(String expertId)? onExpertId,
  }) => HostOnboardingInput(
    userDocumentId: userDocumentId,
    expertId: d.expertId,
    handler: d.handle.text.trim(),
    tagline: d.tagline.text.trim(),
    gender: d.gender.value,
    description: d.bio.text.trim(),
    languages: d.languages.value,
    photoMediaIds: [
      for (final p in d.photos.value)
        if (p.mediaId != null) p.mediaId!,
    ],
    audioIntro: d.voiceIntro.value?.upload,
    videoIntro: d.videoIntro.value?.upload,
    rates: HostValidation.ratesOf(d),
    callAnyTime: d.availableNow.value && !d.vacation.value,
    vacation: d.vacation.value,
    week: week(d),
    expertise: expertise(form, d),
    userPatch: userPatch(d, me),
    promoteToExpert: '${me.user['role'] ?? ''}'.toLowerCase() != 'expert',
    onExpertId: onExpertId,
  );

  /// Days with slots, every slot kept (the schedule's save shape).
  static Map<HostWeekday, List<HostTimeSlot>> week(HostDraftController d) => {
    for (final e in d.week.value.entries)
      if (e.value.slots.isNotEmpty)
        e.key: [for (final s in e.value.slots) HostTimeSlot(s.start, s.end)],
  };

  /// Every live question of the interests form gets an answer: the topics
  /// from the Interests step, the others derived from the draft, else the
  /// admin default / opt-out (the server checks `required`).
  static Map<String, List<String>> expertise(
    InterestForm form,
    HostDraftController d,
  ) {
    final topicKey = HostTopicCatalog.question(form)?.key;
    final out = <String, List<String>>{};
    for (final q in form.questions) {
      if (q.key.isEmpty || q.isDeprecated) continue;
      final live = [
        for (final o in q.options)
          if (!o.isDeprecated) o,
      ];
      final derived = q.key == topicKey
          ? [
              for (final t in d.topics.value)
                if (live.any((o) => o.value == t.value)) t.value,
            ]
          : _derive(q, live, d);
      final capped = q.maxSelect == null
          ? derived
          : derived.take(q.maxSelect!).toList();
      final answer = capped.isNotEmpty
          ? (q.isMulti ? capped : capped.take(1).toList())
          : q.neutralAnswer;
      out[q.key] = answer;
    }
    return out;
  }

  static List<String> _derive(
    InterestQuestion q,
    List<InterestOption> live,
    HostDraftController d,
  ) {
    String text(InterestOption o) => '${o.value} ${o.label}'.toLowerCase();
    final key = q.key.toLowerCase();
    if (key.contains('user_gender')) {
      final g = d.gender.value;
      final match = switch (g) {
        'Female' => live.where(
          (o) => text(o).contains('female') || text(o).contains('woman'),
        ),
        'Male' => live.where(
          (o) =>
              !text(o).contains('female') &&
              (text(o).contains('male') || o.label.toLowerCase() == 'man'),
        ),
        _ => const <InterestOption>[],
      };
      return [for (final o in match.take(1)) o.value];
    }
    if (q.type == InterestQuestionType.mode) {
      final wantAudio = d.audioOn.value;
      final match = live.where(
        (o) => wantAudio
            ? text(o).contains('audio') || text(o).contains('voice')
            : text(o).contains('video'),
      );
      return [for (final o in match.take(1)) o.value];
    }
    if (q.type == InterestQuestionType.language) {
      final spoken = {
        for (final l in d.languages.value) HostPrefill.languageKey(l.label),
      };
      return [
        for (final o in live)
          if (spoken.contains(o.label.trim().toLowerCase()) ||
              spoken.contains(o.value.trim().toLowerCase()))
            o.value,
      ];
    }
    return const [];
  }

  /// Personal Info changed in the Basic Profile step (name, location), as
  /// `/public-users` fields. Empty when nothing changed.
  static JsonMap userPatch(HostDraftController d, UserWithExpert me) {
    final out = <String, dynamic>{};
    final name = d.name.text.trim();
    if (name.isNotEmpty && name != (me.name ?? '')) out['name'] = name;
    final state = d.state.value;
    final district = d.district.value;
    bool changed(GeoOption? next, GeoOption? current, dynamic saved) =>
        next != null &&
        ((next.filterId != null && next.filterId != current?.filterId) ||
            next.name != (current?.name ?? J.str(saved) ?? ''));
    final address = me.addressJson;
    if (changed(state, me.state, address['state']) ||
        changed(district, me.district, address['district'])) {
      final stateRef = state?.connect;
      final districtRef = district?.connect;
      if (stateRef != null) out['state'] = stateRef;
      if (districtRef != null) out['district'] = districtRef;
      out['address_JSON'] = {
        ...address,
        'state': state?.name ?? '',
        'district': district?.name ?? '',
        'country': address['country'] ?? GeoApi.defaultCountry,
      };
    }
    return out;
  }
}
