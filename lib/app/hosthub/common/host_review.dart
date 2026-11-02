import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../api/hosthub/moderation_models.dart';
import '../../api/hosthub/profile_models.dart';
import '../onboarding/helper/host_steps.dart';

/// What review asked this host to change, as the onboarding steps show it:
/// the text fields a rejection named (with the team's note), each photo's
/// review state, and whether the voice intro was turned down.
@immutable
class HostReview {
  const HostReview({
    this.fields = const {},
    this.note,
    this.photos = const {},
    this.audioRejected = false,
    this.videoRejected = false,
  });

  /// From the saved profile and the team's messages (newest first).
  factory HostReview.from(
    HostProfile? host,
    List<HostModerationMessage> messages,
  ) {
    if (host == null) return none;
    final rejected = host.moderationStatus == 'rejected';
    final latest = rejected
        ? messages.where((m) => m.isTextRejection).firstOrNull
        : null;
    final note = (host.moderationNote ?? '').trim();
    return HostReview(
      fields: {...?latest?.fields.where(fieldSteps.containsKey)},
      note: !rejected
          ? null
          : note.isNotEmpty
          ? note
          : (latest?.body.isNotEmpty ?? false)
          ? latest!.body
          : null,
      photos: {
        for (final img in host.profileImages)
          if (img.imageId != null) '${img.imageId}': img.moderationStatus,
      },
      audioRejected: host.audioIntroStatus == 'rejected',
      videoRejected: host.videoIntroStatus == 'rejected',
    );
  }

  static const none = HostReview();

  /// Rejectable text fields → the step that edits them.
  static const fieldSteps = {
    'name': HostStep.basic,
    'handler': HostStep.basic,
    'tagline': HostStep.tagline,
    'descriptions': HostStep.bio,
  };

  /// Text fields to change (name, handler, tagline, descriptions).
  final Set<String> fields;

  /// The team's reason, while the profile stands rejected.
  final String? note;

  /// A saved photo's media id → pending / approved / rejected.
  final Map<String, String> photos;
  final bool audioRejected;

  /// The video intro was turned down: the Video step asks for a new one.
  final bool videoRejected;

  /// The rejection is about text, though no field was named.
  bool get textRejected => note != null;

  bool flagged(String field) => fields.contains(field);

  /// The named fields on [step]; a rejection naming none points at Basic.
  List<String> fieldsOn(HostStep step) => [
    for (final e in fieldSteps.entries)
      if (e.value == step && fields.contains(e.key)) e.key,
  ];

  /// Whether [step] shows the rejection notice.
  bool noticeOn(HostStep step) =>
      textRejected &&
      (fields.isEmpty ? step == HostStep.basic : fieldsOn(step).isNotEmpty);

  /// A draft photo's review state, by its media id; null for a new upload.
  String? photoStatus(Object? mediaId) =>
      mediaId == null ? null : photos['$mediaId'];

  bool get hasRejectedPhoto => photos.values.contains('rejected');

  @override
  bool operator ==(Object other) =>
      other is HostReview &&
      other.note == note &&
      other.audioRejected == audioRejected &&
      other.videoRejected == videoRejected &&
      setEquals(other.fields, fields) &&
      mapEquals(other.photos, photos);

  @override
  int get hashCode => Object.hash(
    note,
    audioRejected,
    videoRejected,
    Object.hashAllUnordered(fields),
    Object.hashAllUnordered(photos.entries.map((e) => '${e.key}=${e.value}')),
  );
}

/// Hands [review] to the onboarding steps.
class HostReviewScope extends InheritedWidget {
  const HostReviewScope({
    super.key,
    required this.review,
    required super.child,
  });

  final HostReview review;

  /// [HostReview.none] outside a scope (a new host, tests).
  static HostReview of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HostReviewScope>()?.review ??
      HostReview.none;

  @override
  bool updateShouldNotify(HostReviewScope old) => old.review != review;
}
