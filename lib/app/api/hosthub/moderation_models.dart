import 'package:flutter/foundation.dart';

import '../../../core/network/strapi.dart';
import 'profile_models.dart';

/// One message from the moderation team to this host
/// (`GET /api/me/moderation-notes`): a note, or a decision with what it is
/// about (the text fields a rejection named, the rejected photo) and the
/// screen to fix it on.
@immutable
class HostModerationMessage {
  const HostModerationMessage({
    required this.id,
    required this.kind,
    this.body = '',
    this.deeplink,
    this.fields = const [],
    this.photo,
    this.photoUrl,
    this.audio,
    this.status,
    this.createdAt,
    bool? dismissible,
  }) : _dismissible = dismissible;

  factory HostModerationMessage.from(JsonMap m) => HostModerationMessage(
    id: J.integer(m['id']) ?? 0,
    kind: J.str(m['kind']) ?? 'note',
    body: (J.str(m['body']) ?? '').trim(),
    deeplink: J.str(m['deeplink']),
    fields: [
      for (final f in m['fields'] is List ? m['fields'] as List : const [])
        ?J.str(f),
    ],
    photo: J.str(m['photo']),
    photoUrl: J.str(m['photoUrl']),
    audio: J.str(m['audio']),
    status: J.str(m['status']),
    createdAt: J.date(m['createdAt']),
    dismissible: m['dismissible'] is bool ? m['dismissible'] as bool : null,
  );

  final int id;

  /// note, rejected, approved, status_changed, photo_decision, edited_live.
  final String kind;
  final String body;

  /// The screen the team linked (`vibecalling://host-photos`), if any.
  final String? deeplink;

  /// Text fields a rejection is about: name, handler, tagline, descriptions.
  final List<String> fields;

  /// The rejected photo's documentId, and its picture.
  final String? photo;
  final String? photoUrl;

  /// The voice intro's new state (`rejected`), on a voice decision.
  final String? audio;

  /// The listing's new state, on a status change.
  final String? status;
  final DateTime? createdAt;

  /// The text was turned down: a rejected submission or profile.
  bool get isTextRejection =>
      kind == 'rejected' || (kind == 'status_changed' && status == 'rejected');

  /// Something needs the host to act.
  bool get needsAction =>
      isTextRejection || photo != null || audio == 'rejected';

  final bool? _dismissible;

  /// Just a message (a note, an approval): the host may close it with the X.
  /// A request to fix closes once fixed, or when the team resolves it. The
  /// backend says (`dismissible`); an older one does not, so the same rule.
  bool get dismissible => _dismissible ?? !needsAction;

  bool get isApproval =>
      kind == 'approved' || (kind == 'status_changed' && status == 'approved');

  /// Asked for a fix that [host] has made since: the rejected photo is gone
  /// (deleted, or approved since), the voice intro or the profile is no
  /// longer rejected. Notes and approvals are never resolved. (The backend
  /// leaves these out too; this covers an older backend and a profile
  /// changed since the messages loaded.)
  bool resolvedFor(HostProfile host) {
    final p = photo;
    if (p != null) {
      return !host.profileImages.any(
        (img) => img.documentId == p && img.moderationStatus == 'rejected',
      );
    }
    if (audio == 'rejected') return host.audioIntroStatus != 'rejected';
    if (isTextRejection) return host.moderationStatus != 'rejected';
    return false;
  }
}
