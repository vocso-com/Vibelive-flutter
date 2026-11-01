import 'package:flutter/foundation.dart';

/// Host statuses as the app reads them.
///
/// Two shapes on purpose, because a client and the host who posted it are
/// asking different questions. A client only ever needs "is there a clip and
/// where is it"; the host needs to know whether theirs is live, waiting, or was
/// turned down. Serving one shape to both would mean either leaking a review
/// state to viewers or hiding it from the person it is about.
///
/// The server has already decided what each caller may see — it withholds the
/// file for anything unapproved and keeps expired clips out of the client list
/// entirely — so neither model re-implements the visibility rule. They only
/// describe what arrived.
String? _str(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

DateTime? _date(Object? v) {
  final s = _str(v);
  if (s == null) return null;
  return DateTime.tryParse(s);
}

List<Object?> _rows(Object? body) {
  if (body is! Map) return const [];
  final results = body['results'];
  return results is List ? results : const [];
}

/// One clip on someone else's profile.
@immutable
class HostStatus {
  const HostStatus({
    required this.documentId,
    required this.media,
    this.recordedAt,
    this.visibleUntil,
  });

  /// Null when there is nothing to show: no id, or no file. A row whose file
  /// the server withheld arrives with `media` null, and a viewer has no use
  /// for a status they cannot watch.
  static HostStatus? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _str(json['documentId']);
    final media = _str(json['media']);
    if (id == null || media == null) return null;
    return HostStatus(
      documentId: id,
      media: media,
      recordedAt: _date(json['recordedAt']),
      visibleUntil: _date(json['visibleUntil']),
    );
  }

  /// Newest first, as the server orders them; unshowable rows dropped.
  static List<HostStatus> listFrom(Object? body) => [
    for (final row in _rows(body)) ?HostStatus.fromJson(row),
  ];

  final String documentId;
  final String media;
  final DateTime? recordedAt;
  final DateTime? visibleUntil;
}

/// One of the host's own clips, with the review state they are entitled to see.
@immutable
class HostOwnStatus {
  const HostOwnStatus({
    required this.documentId,
    this.media,
    this.status,
    this.state,
    this.recordedAt,
    this.visibleUntil,
  });

  /// Kept even with no file. A rejected or purged clip has nothing to play and
  /// still belongs in the host's own history — dropping it would leave them
  /// wondering where the clip they posted went.
  static HostOwnStatus? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _str(json['documentId']);
    if (id == null) return null;
    return HostOwnStatus(
      documentId: id,
      media: _str(json['media']),
      status: _str(json['status']),
      state: _str(json['state']),
      recordedAt: _date(json['recordedAt']),
      visibleUntil: _date(json['visibleUntil']),
    );
  }

  static List<HostOwnStatus> listFrom(Object? body) => [
    for (final row in _rows(body)) ?HostOwnStatus.fromJson(row),
  ];

  final String documentId;
  final String? media;

  /// `pending` / `approved` / `rejected`: the reviewer's verdict.
  final String? status;

  /// The server's own word for where this stands: `visible`, `pending`,
  /// `rejected`, `expired` or `purged`. Read rather than recomputed, so the
  /// app and the server cannot disagree about it.
  final String? state;

  final DateTime? recordedAt;
  final DateTime? visibleUntil;

  /// Showing to clients right now. Approval alone is not enough — an approved
  /// clip past its 24 hours is no longer on anybody's profile.
  bool get isLive => status == 'approved' && state == 'visible';

  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
}
