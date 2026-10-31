import '../../../core/network/strapi.dart';
import 'catalog_models.dart';
import 'profile_models.dart';

/// Body of `PUT /expert-profiles/:id`, built the way each RN screen built it.
class HostProfilePatch {
  const HostProfilePatch(this.data, {JsonMap? echo}) : _echo = echo;

  /// Sent as `{data: …}`.
  final JsonMap data;
  final JsonMap? _echo;

  /// Merged into the local copy when the post-save re-read fails: [data]
  /// minus relation operations (`connect`/`set`/`disconnect`), which do not
  /// have the read shape.
  JsonMap get echo =>
      _echo ??
      {
        for (final e in data.entries)
          if (!_isRelationOp(e.value)) e.key: e.value,
      };

  static bool _isRelationOp(dynamic v) =>
      v is Map &&
      (v.containsKey('connect') ||
          v.containsKey('set') ||
          v.containsKey('disconnect'));

  /// CallRatesScreen: a disabled call type is saved as rate 0.
  factory HostProfilePatch.rates({double voice = 0, double video = 0}) =>
      HostProfilePatch({
        'rates': HostRates(voiceCallRate: voice, videoCallRate: video).toJson(),
      });

  /// ScheduleScreen: slots are only sent when neither vacation nor "call me
  /// anytime" is on; days without slots are dropped.
  factory HostProfilePatch.schedule({
    required bool vacation,
    required bool callAnyTime,
    Map<HostWeekday, List<HostTimeSlot>> week = const {},
  }) {
    final data = <String, dynamic>{
      'vocationMode': vacation,
      'callAnyTime': callAnyTime,
    };
    if (!vacation && !callAnyTime) {
      data['schedule'] = [
        for (final day in HostWeekday.values)
          if ((week[day] ?? const []).isNotEmpty)
            {
              'days': day.apiValue,
              'timeSlots': [
                for (final slot in [
                  ...week[day]!,
                ]..sort((a, b) => a.startMinutes.compareTo(b.startMinutes)))
                  slot.toJson(),
              ],
            },
      ];
    }
    return HostProfilePatch(data);
  }

  /// Availability toggle on the host's own profile card.
  factory HostProfilePatch.availability(HostAvailability mode) =>
      HostProfilePatch({
        'vocationMode': mode == HostAvailability.vacation,
        'callAnyTime': mode == HostAvailability.available,
      });

  /// CategoriesScreen: categories set by numeric id.
  factory HostProfilePatch.categories(List<int> ids) => HostProfilePatch({
    'categories': [
      for (final id in ids) {'id': id},
    ],
  });

  /// ApprovalScreen "Go live".
  static const goLive = HostProfilePatch({'isActive': true});

  /// ProfessionalDetailsScreen fields.
  factory HostProfilePatch.professional({
    required String handler,
    required String tagline,
    String? gender,
    required String description,
    String website = '',
    required List<HostOption> languages,
    Object? audioIntroMediaId,
    Object? videoIntroMediaId,
  }) {
    final data = <String, dynamic>{
      'handler': HostProfile.sanitizeHandle(handler),
      'tagline': tagline.trim(),
      'gender': HostProfile.normalizeGender(gender),
      'descriptions': description.trim(),
      'website': website.trim(),
      'language': {
        'connect': [for (final l in languages) ?l.connectRef],
      },
      // Only when there is a recording: the backend has rejected this key
      // ("Invalid key audio_intro"), and sending `null` on every save took
      // unrelated edits down with it. An intro cannot be cleared from here.
      'audio_intro': ?audioIntroMediaId,
      // Same rule, same reason: absent rather than null when there is no clip.
      // The server also forces video_intro_status back to pending on any change
      // here, so sending an unchanged clip would quietly unpublish an approved
      // one — which is why a saved clip reports no upload at all.
      'video_intro': ?videoIntroMediaId,
    };
    return HostProfilePatch(
      data,
      echo: {
        for (final e in data.entries)
          // Media ids are not worth echoing into the local profile: the echo
          // feeds the optimistic view, which reads intros by URL, not by id.
          if (e.key != 'language' &&
              e.key != 'audio_intro' &&
              e.key != 'video_intro')
            e.key: e.value,
        'language': [for (final l in languages) l.raw],
      },
    );
  }
}

/// A file to upload, or media already on the server.
sealed class HostMediaRef {
  const HostMediaRef();

  const factory HostMediaRef.file(
    String path, {
    String? fileName,
    String? mimeType,
  }) = HostMediaFile;

  const factory HostMediaRef.media(Object id) = HostMediaId;
}

final class HostMediaFile extends HostMediaRef {
  const HostMediaFile(this.path, {this.fileName, this.mimeType});

  final String path;
  final String? fileName;
  final String? mimeType;
}

final class HostMediaId extends HostMediaRef {
  const HostMediaId(this.id);

  /// Strapi media id (or documentId).
  final Object id;
}

/// Everything the Professional Details save writes on the host side.
class ProfessionalDetailsInput {
  const ProfessionalDetailsInput({
    required this.userDocumentId,
    this.expertId,
    required this.handler,
    required this.tagline,
    this.gender,
    required this.description,
    this.website = '',
    required this.languages,
    this.photos = const [],
    this.existingPhotos = const [],
    this.audioIntro,
    this.videoIntro,
  });

  /// Owner; becomes the `user` relation when the profile is created.
  final String userDocumentId;

  /// Null creates the host profile.
  final String? expertId;
  final String handler;
  final String tagline;
  final String? gender;
  final String description;
  final String website;
  final List<HostOption> languages;

  /// Up to 3 slots, slot 1 = primary photo; null = empty slot.
  final List<HostMediaRef?> photos;

  /// Rows currently on the server (decides PUT vs POST per slot).
  final List<HostProfileImage> existingPhotos;

  /// A local recording is uploaded as `audio/mp4`.
  final HostMediaRef? audioIntro;

  /// A local capture is uploaded as `video/mp4`.
  final HostMediaRef? videoIntro;
}

class ProfessionalDetailsResult {
  const ProfessionalDetailsResult({
    required this.expertId,
    required this.created,
    required this.photoMediaIds,
    this.profile,
  });

  final String expertId;

  /// True when this save created the host profile.
  final bool created;

  /// Media id per slot after uploads. The caller still owes the user record
  /// `profilePic = photoMediaIds.first` (and `role: 'Expert'` when
  /// [created]) through the client feature's `/public-users` update.
  final List<Object?> photoMediaIds;

  /// Re-read profile, or the saved fields when the re-read failed.
  final HostProfile? profile;

  Object? get primaryMediaId =>
      photoMediaIds.isEmpty ? null : photoMediaIds.first;
}
