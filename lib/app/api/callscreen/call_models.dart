import '../../../core/network/strapi.dart';
import '../free_call/free_call_models.dart';

/// Backend `callStatus`. [unknown] covers a missing or new value.
enum CallStatus {
  pending,
  ringing,
  ongoing,
  completed,
  declined,
  missed,
  busy,
  cancelled,
  ended,

  /// Admin force-end: stored as `"force complete by admin"`, pushed as
  /// `force_complete_by_admin` (E-80).
  forceCompleteByAdmin,
  unknown;

  static CallStatus parse(Object? raw) {
    final s = (J.str(raw) ?? '').trim().toLowerCase();
    if (s == 'canceled') return cancelled;
    if (s.replaceAll(RegExp(r'[\s_]+'), ' ') == _forceCompleteWire) {
      return forceCompleteByAdmin;
    }
    for (final v in values) {
      if (v != unknown && v.name == s) return v;
    }
    return unknown;
  }

  static const _forceCompleteWire = 'force complete by admin';

  /// The backend has closed this call: never route into it (RN root layout).
  bool get isClosed => switch (this) {
    ended ||
    declined ||
    missed ||
    cancelled ||
    completed ||
    forceCompleteByAdmin => true,
    _ => false,
  };

  /// Value sent to `/UpdateCall` and `/call/Callend`.
  String get wireValue =>
      this == forceCompleteByAdmin ? _forceCompleteWire : name;
}

enum CallType {
  voice('voiceCall'),
  video('videoCall');

  const CallType(this.wireValue);

  final String wireValue;

  /// Anything mentioning "video" (`videoCall`, `video`) is video; else voice.
  static CallType parse(Object? raw) =>
      (J.str(raw) ?? '').toLowerCase().contains('video') ? video : voice;
}

/// A Strapi relation as a map; null when absent (`null`, `{data: null}`).
JsonMap? _relation(Object? value) {
  final node = Strapi.node(value);
  final first = node is List ? (node.isEmpty ? null : node.first) : node;
  final map = Strapi.map(first);
  if (map == null || map.isEmpty) return null;
  if (map.length == 1 && map.containsKey('data')) return null;
  return map;
}

/// Caller / receiver of a call, or the author of a review (public user).
class CallParty {
  const CallParty(this.raw);

  final JsonMap raw;

  static CallParty? from(Object? node) {
    final map = _relation(node);
    return map == null ? null : CallParty(map);
  }

  int? get id => J.integer(raw['id']);
  String? get documentId => J.str(raw['documentId']);

  /// documentId, else numeric id (RN `person.documentId || person.id`).
  String? get userKey => documentId ?? J.str(raw['id']);

  String? get name => J.str(raw['name']);
  String? get role => J.str(raw['role']);
  bool get isExpertRole => role?.toLowerCase() == 'expert';

  bool get hasExpertProfile {
    final expert = raw['expert'];
    if (expert is Map) return _relation(expert) != null;
    return expert != null && expert != false && expert != 0 && expert != '';
  }

  String? get avatarUrl => Strapi.mediaFromAsset(raw['profilePic']);
}

/// One `/calls` row. [raw] keeps every field; getters cover what the call log
/// reads (Strapi v4 and v5 shapes).
class CallLog {
  const CallLog(this.raw);

  final JsonMap raw;

  factory CallLog.fromJson(Object? json) =>
      CallLog(Map<String, dynamic>.from(json! as Map));

  JsonMap toJson() => raw;

  int? get id => J.integer(raw['id']);
  String? get documentId => J.str(raw['documentId']);

  /// Numeric id as a string (the id the call endpoints take), else documentId.
  String get key => J.str(raw['id']) ?? documentId ?? '';

  JsonMap? get _metadata => Strapi.map(raw['metadata']);

  CallStatus get status => CallStatus.parse(
    J.str(raw['callStatus']) ??
        J.str(raw['call_status']) ??
        J.str(_metadata?['callStatus']),
  );

  CallType get type =>
      CallType.parse(J.str(raw['type']) ?? J.str(_metadata?['callType']));

  bool get isVideo => type == CallType.video;

  CallParty? get caller => CallParty.from(raw['caller']);
  CallParty? get receiver => CallParty.from(raw['receiver']);

  String? get channelName => J.str(raw['channelName']);
  DateTime? get startTime => J.date(raw['startTime']);
  DateTime? get endTime => J.date(raw['endTime']);
  DateTime? get createdAt => J.date(raw['createdAt']);

  /// When the call happened (RN `startTime || createdAt`).
  DateTime? get at => startTime ?? createdAt;

  /// Talk time in seconds (`duration_sec`).
  int get durationSeconds => J.integer(raw['duration_sec']) ?? 0;

  /// `duration`: RN showed it as minutes when `duration_sec` was empty.
  num get durationMinutes => J.number(raw['duration']) ?? 0;

  bool get hasPositiveDuration => [
    raw['duration_sec'],
    raw['duration'],
    raw['durationSeconds'],
  ].any((v) => (J.number(v) ?? 0) > 0);

  double get totalCost => J.number(raw['totalCost']) ?? 0;

  /// Review populated on the history query (`populate[review]`).
  Review? get review {
    final map = _relation(raw['review']);
    return map == null ? null : Review(map);
  }
}

/// One page of `/calls` history.
class CallHistoryPage {
  const CallHistoryPage({
    required this.calls,
    required this.page,
    required this.pageSize,
    this.pageCount,
    this.total,
  });

  final List<CallLog> calls;
  final int page;
  final int pageSize;
  final int? pageCount;
  final int? total;

  factory CallHistoryPage.fromResponse(
    dynamic body, {
    required int page,
    required int pageSize,
  }) {
    final p = Strapi.pagination(body);
    return CallHistoryPage(
      calls: [for (final row in Strapi.list(Strapi.body(body))) CallLog(row)],
      page: J.integer(p?['page']) ?? page,
      pageSize: J.integer(p?['pageSize']) ?? pageSize,
      pageCount: J.integer(p?['pageCount']),
      total: J.integer(p?['total']),
    );
  }

  factory CallHistoryPage.fromJson(Object? json) {
    final map = json! as Map;
    return CallHistoryPage(
      calls: [for (final row in map['calls'] as List) CallLog.fromJson(row)],
      page: J.integer(map['page']) ?? 1,
      pageSize: J.integer(map['pageSize']) ?? 10,
      pageCount: J.integer(map['pageCount']),
      total: J.integer(map['total']),
    );
  }

  Map<String, dynamic> toJson() => {
    'calls': [for (final c in calls) c.toJson()],
    'page': page,
    'pageSize': pageSize,
    'pageCount': pageCount,
    'total': total,
  };

  /// RN rule: trust `pageCount` when sent, else a full page means "maybe more".
  bool get hasMore {
    final count = pageCount;
    return count != null ? page < count : calls.length >= pageSize;
  }

  /// Pages flattened newest first, each call once: a new call shifts rows
  /// across page boundaries, and the earlier (fresher) page wins.
  static List<CallLog> merge(Iterable<CallHistoryPage> pages) {
    final seen = <String>{};
    final rows = <(int, CallLog)>[];
    for (final page in pages) {
      for (final call in page.calls) {
        final key = call.key;
        if (key.isNotEmpty && !seen.add(key)) continue;
        rows.add((rows.length, call));
      }
    }
    int ms(CallLog c) => c.at?.millisecondsSinceEpoch ?? 0;
    rows.sort((a, b) {
      final byDate = ms(b.$2).compareTo(ms(a.$2));
      return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
    });
    return [for (final row in rows) row.$2];
  }
}

/// How a call reads from the viewer's side (RN `callDirection`).
enum CallDirection { outgoing, incoming, outgoingMissed, missed, declined }

/// What the call log row says about the call (RN `callOutcomeLabel`).
enum CallOutcome { missed, declined, videoCall, voiceCall }

/// A [CallLog] seen by the signed-in user (RN explore `mapCall`).
class CallHistoryItem {
  CallHistoryItem(
    this.call, {
    required String viewerDocumentId,
    String? viewerRole,
  }) : isOutgoing = _isViewer(call.caller, viewerDocumentId),
       _viewerIsClient = (viewerRole ?? '').toLowerCase() == 'client';

  final CallLog call;

  /// The viewer placed this call.
  final bool isOutgoing;
  final bool _viewerIsClient;

  static bool _isViewer(CallParty? party, String viewer) =>
      party != null &&
      viewer.isNotEmpty &&
      (party.documentId == viewer || J.str(party.raw['id']) == viewer);

  /// The other person on the call.
  CallParty? get counterpart => isOutgoing ? call.receiver : call.caller;

  /// RN reads two fields: the direction and the rate rules only
  /// `callStatus`; the outcome label `call_status || callStatus ||
  /// metadata.callStatus`.
  CallStatus get _rowStatus => CallStatus.parse(call.raw['callStatus']);
  CallStatus get _outcomeStatus => CallStatus.parse(
    J.str(call.raw['call_status']) ??
        J.str(call.raw['callStatus']) ??
        J.str(Strapi.map(call.raw['metadata'])?['callStatus']),
  );

  /// completed → outgoing / incoming; declined → declined (no talk time) or
  /// missed; missed → outgoing-missed / missed; anything else (ongoing,
  /// pending, busy, cancelled, force-completed…) → outgoing / incoming.
  CallDirection get direction => switch (_rowStatus) {
    CallStatus.completed =>
      isOutgoing ? CallDirection.outgoing : CallDirection.incoming,
    // Declined before any talk time; with talk time it was cut off → missed.
    CallStatus.declined =>
      call.durationSeconds <= 0 && call.durationMinutes <= 0
          ? CallDirection.declined
          : CallDirection.missed,
    CallStatus.missed =>
      isOutgoing ? CallDirection.outgoingMissed : CallDirection.missed,
    _ => isOutgoing ? CallDirection.outgoing : CallDirection.incoming,
  };

  /// No topic is recorded on a call, so the row says how the call went.
  CallOutcome get outcome => switch (_outcomeStatus) {
    CallStatus.missed => CallOutcome.missed,
    CallStatus.declined => CallOutcome.declined,
    _ => call.isVideo ? CallOutcome.videoCall : CallOutcome.voiceCall,
  };

  /// Tapping the row opens an expert profile. A client only calls experts.
  bool get isExpert =>
      (counterpart?.isExpertRole ?? false) ||
      (counterpart?.hasExpertProfile ?? false) ||
      _viewerIsClient;

  /// A connected call with an expert: a review may exist, worth looking up.
  bool get mayHaveReview =>
      (counterpart?.isExpertRole ?? false) &&
      _rowStatus != CallStatus.missed &&
      call.hasPositiveDuration;

  /// "Rate this call" is for the caller only.
  bool get canRate => isOutgoing && mayHaveReview;

  /// Expert nudge to a client who missed or declined the call, while still
  /// inside the ping window ([pingWindow]).
  bool canPing({required Duration window, DateTime? now}) {
    if (isOutgoing || counterpart?.userKey == null) return false;
    if (window <= Duration.zero) return false;
    final d = direction;
    if (d != CallDirection.missed && d != CallDirection.declined) return false;
    final at = call.at;
    if (at == null) return false;
    return (now ?? DateTime.now()).difference(at) < window;
  }

  /// App-config `expert_ping_config.validity_hours` (RN `Number(hours ||
  /// 24)`): unset / 0 / empty → 24 h; not a number or negative → zero, and
  /// NUDGE never shows.
  static Duration pingWindow(JsonMap? expertPingConfig) {
    final raw = expertPingConfig?['validity_hours'];
    if (raw == null || raw == 0 || raw == '' || raw == false) {
      return const Duration(hours: 24);
    }
    final h = J.number(raw is String ? raw.trim() : raw);
    if (h == null || h.isNaN || h <= 0) return Duration.zero;
    return Duration(microseconds: (h * Duration.microsecondsPerHour).round());
  }
}

/// `/reviews` row (left after a call, listed on an expert profile).
class Review {
  const Review(this.raw);

  final JsonMap raw;

  factory Review.fromJson(Object? json) =>
      Review(Map<String, dynamic>.from(json! as Map));

  JsonMap toJson() => raw;

  int? get id => J.integer(raw['id']);
  String? get documentId => J.str(raw['documentId']);
  double get rating => normalizeRating(raw['rating']);
  String get comments => J.str(raw['comments']) ?? '';
  DateTime? get createdAt => J.date(raw['createdAt']);

  /// Reviewer (`user`, with `profilePic` on expert lists).
  CallParty? get author => CallParty.from(raw['user']);

  bool get hasContent => rating > 0 || comments.isNotEmpty;

  /// First value within 0–5 among the shapes the backend has used
  /// (`rating`, `rating.value`, `rating[.data].attributes.value`).
  static double normalizeRating(Object? raw, [num fallback = 0]) {
    Object? at(Object? v, String k) => v is Map ? v[k] : null;
    final candidates = [
      raw,
      at(raw, 'value'),
      at(at(raw, 'attributes'), 'value'),
      at(at(at(raw, 'data'), 'attributes'), 'value'),
    ];
    for (final c in candidates) {
      final n = J.number(c is String ? c.trim() : c);
      if (n != null && !n.isNaN && n >= 0 && n <= 5) return n;
    }
    return fallback.toDouble().clamp(0, 5);
  }
}

/// One page of an expert's reviews.
class ReviewPage {
  const ReviewPage({
    required this.reviews,
    required this.page,
    this.pageCount,
    this.total,
  });

  final List<Review> reviews;
  final int page;
  final int? pageCount;
  final int? total;

  factory ReviewPage.fromResponse(dynamic body, {required int page}) {
    final p = Strapi.pagination(body);
    return ReviewPage(
      reviews: [for (final row in Strapi.list(Strapi.body(body))) Review(row)],
      page: J.integer(p?['page']) ?? page,
      pageCount: J.integer(p?['pageCount']),
      total: J.integer(p?['total']),
    );
  }

  bool get hasMore {
    final count = pageCount;
    return count != null && page < count;
  }
}

/// `/UpdateCall` answer. [alreadyOngoing]: another request (the other side,
/// the native CallKit answer, another receiver device) moved the call to
/// ongoing first (E-86). Fine for the caller and the answering device; a
/// receiver device that did not answer stands down.
class UpdateCallResult {
  const UpdateCallResult({required this.alreadyOngoing, this.raw});

  factory UpdateCallResult.fromResponse(Object? body) {
    final map = body is Map ? Map<String, dynamic>.from(body) : null;
    return UpdateCallResult(
      alreadyOngoing: J.boolean(map?['alreadyOngoing']),
      raw: map,
    );
  }

  final bool alreadyOngoing;

  /// The updated call entity, or `{ok, alreadyOngoing}`.
  final JsonMap? raw;
}

/// A call the backend accepted: everything needed to join the channel.
class InitiatedCall {
  const InitiatedCall({
    required this.raw,
    required this.callId,
    required this.channelName,
    required this.callerToken,
    this.callDocumentId,
    this.receiverDocId,
  });

  /// Full `/initiateCall` body.
  final JsonMap raw;

  /// Numeric call id: the id every later call endpoint takes.
  final String callId;
  final String channelName;

  /// Agora token for the caller.
  final String callerToken;
  final String? callDocumentId;
  final String? receiverDocId;

  /// The server offered this call free (docs/free_calls.md); null: paid.
  FreeCallTerms? get freeCall => FreeCallTerms.tryParse(raw['freeCall']);

  /// `{status: 'busy'}`: the receiver is already on another call.
  static bool isBusyResponse(JsonMap body) =>
      (J.str(body['status']) ?? '').toLowerCase() == 'busy';

  /// Null when the body lacks the call id, channel or token.
  static InitiatedCall? tryParse(JsonMap body) {
    final details = Strapi.map(body['callDetails']);
    final callId = J.str(details?['id']);
    final channel = J.str(body['channelName']);
    final token = J.str(body['callerToken']);
    if (callId == null || channel == null || token == null) return null;
    return InitiatedCall(
      raw: body,
      callId: callId,
      channelName: channel,
      callerToken: token,
      callDocumentId: J.str(details?['documentId']),
      receiverDocId: J.str(body['receiverDocId']),
    );
  }
}
