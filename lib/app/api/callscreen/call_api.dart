import '../../../core/config/env.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'call_errors.dart';
import 'call_models.dart';

/// Call signaling and call logs (RN `call.service.js`, the Logs tab and the
/// root-layout status check). No caching here: use `call_queries.dart`.
abstract final class CallApi {
  /// Logs tab page size.
  static const historyPageSize = 10;

  /// Creates the call; the backend pushes it to the receiver.
  ///
  /// Throws [CallErrorKeys.userBusy] (conflict, server message kept) when the
  /// receiver is on another call, [CallErrorKeys.invalidResponse] when the
  /// answer can't be joined, [CallErrorKeys.missingParticipants] without ids.
  static Future<InitiatedCall> initiateCall(InitiateCallInput input) async {
    if (!input.hasParticipants) {
      throw const ApiException(
        ApiErrorType.rejected,
        messageKey: CallErrorKeys.missingParticipants,
      );
    }
    final body = await withCallFallback(
      CallErrorKeys.initiateFailed,
      () => ApiClient.post('/initiateCall', data: input.toJson()),
    );
    final data = body is Map
        ? Map<String, dynamic>.from(body)
        : <String, dynamic>{};
    if (InitiatedCall.isBusyResponse(data)) {
      throw ApiException(
        ApiErrorType.conflict,
        messageKey: CallErrorKeys.userBusy,
        serverMessage: ApiException.readableServerMessage(data),
        data: data,
      );
    }
    final call = InitiatedCall.tryParse(data);
    if (call == null) {
      throw ApiException(
        ApiErrorType.parse,
        messageKey: CallErrorKeys.invalidResponse,
        data: data,
      );
    }
    return call;
  }

  /// Tells the caller's side the receiver's phone is ringing.
  static Future<void> sendRingingAck({
    required String callId,
    required String receiverId,
  }) async {
    await ApiClient.post(
      '/call/receiver-ringing-ack',
      data: {'callId': callId, 'receiverId': receiverId},
    );
  }

  /// Mostly `ongoing` once the receiver accepted. A duplicate answer is not
  /// an error: see [UpdateCallResult.alreadyOngoing].
  static Future<UpdateCallResult> updateStatus(CallStatusUpdate update) async {
    final body = await ApiClient.post('/UpdateCall', data: update.toJson());
    return UpdateCallResult.fromResponse(body);
  }

  /// Ends, declines or cancels a call. A call can be ended from several
  /// paths (hangup, remote end, notification action, replay), so the request
  /// carries an idempotency key per call.
  static Future<void> endCall(CallEndInput input) async {
    await ApiClient.post(
      '/call/Callend',
      data: input.toJson(),
      headers: {'x-idempotency-key': 'callend:${input.callId}'},
    );
  }

  /// Current `callStatus` only ([CallStatus.unknown] when the row is missing
  /// or has none). Strapi 5 paths take a documentId, so a numeric id from a
  /// push goes through a filter (E-85: RN's `/calls/<id>` always 404'd).
  static Future<CallStatus> fetchStatus(String callId) async {
    final id = callId.trim();
    final byId = RegExp(r'^\d+$').hasMatch(id);
    final body = await ApiClient.get(
      '/calls',
      query: {
        byId ? 'filters[id][\$eq]' : 'filters[documentId][\$eq]': id,
        'fields[0]': 'callStatus',
      },
    );
    final rows = Strapi.list(Strapi.body(body));
    return rows.isEmpty
        ? CallStatus.unknown
        : CallStatus.parse(rows.first['callStatus']);
  }

  /// Calls placed or received by the user, newest first.
  static Future<CallHistoryPage> fetchHistory(
    String userDocumentId, {
    int page = 1,
    int pageSize = historyPageSize,
  }) async {
    final body = await ApiClient.get(
      '/calls',
      query: {
        'filters[\$or][0][caller][documentId][\$eq]': userDocumentId,
        'filters[\$or][1][receiver][documentId][\$eq]': userDocumentId,
        'pagination[page]': page,
        'pagination[pageSize]': pageSize,
        'populate[caller][populate]': 'profilePic',
        'populate[receiver][populate]': 'profilePic',
        'populate[review]': 'true',
        'sort': 'createdAt:desc',
      },
    );
    return CallHistoryPage.fromResponse(body, page: page, pageSize: pageSize);
  }

  /// The caller is paying in the middle of call [callId] (the call record's
  /// id): [active] keeps the backend's low-balance guard from ending it for a
  /// few minutes; false when done. True when the server took it (an older
  /// backend without the route: false, nothing else changes).
  static Future<bool> topUpHold(String callId, {required bool active}) async {
    try {
      final body = await ApiClient.post(
        '/call/topup-hold',
        data: {'callId': int.tryParse(callId) ?? callId, 'active': active},
      );
      return body is Map && body['ok'] == true;
    } on ApiException {
      return false;
    }
  }

  /// Expert nudge to a client who missed or declined their call.
  static Future<void> pingClient(String clientDocumentId) =>
      withCallFallback(CallErrorKeys.pingFailed, () async {
        await ApiClient.post(
          '/call/ping-client',
          data: {'clientDocId': clientDocumentId},
        );
      });
}

/// `Date.toISOString()` format: UTC, millisecond precision.
String _iso(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
  t.millisecondsSinceEpoch,
  isUtc: true,
).toIso8601String();

class InitiateCallInput {
  const InitiateCallInput({
    required this.callerId,
    required this.receiverId,
    this.type = CallType.voice,
    this.role,
    this.categoryId,
    this.userPlatform,
  });

  /// Caller's public-user id (sent as given, like RN).
  final Object? callerId;

  /// Receiver's public-user id.
  final Object? receiverId;
  final CallType type;

  /// Caller's role; `Client` when unset.
  final String? role;
  final Object? categoryId;

  /// Some backend middlewares read the platform from the body, not headers.
  final String? userPlatform;

  bool get hasParticipants =>
      J.str(callerId) != null && J.str(receiverId) != null;

  Map<String, dynamic> toJson({DateTime? now}) => {
    'startTime': _iso(now ?? DateTime.now()),
    'callerId': callerId,
    'receiverId': receiverId,
    'role': J.str(role) ?? 'Client',
    'type': type.wireValue,
    'categoryId': ?categoryId,
    'userPlatform': J.str(userPlatform) ?? Env.appPlatform,
  };
}

class CallStatusUpdate {
  const CallStatusUpdate({
    required this.callId,
    this.callerId,
    this.receiverId,
    this.status = CallStatus.ongoing,
    this.startTime,
    this.type,
    this.category,
    this.answeredDeviceId,
  });

  final String callId;
  final String? callerId;
  final String? receiverId;
  final CallStatus status;

  /// Billing start. Left out by default so the server clock is used: the
  /// first `/UpdateCall` `startTime` is what the call is billed from, and a
  /// skewed phone clock changes the bill (E-87).
  final DateTime? startTime;
  final CallType? type;

  /// Echoed into the `CallTimer` push (RN native sent it).
  final String? category;

  /// Stable install id of the device that answered. The backend then sends
  /// `CALL_ANSWERED_ELSEWHERE` only to the receiver's OTHER devices (E-76).
  final String? answeredDeviceId;

  Map<String, dynamic> toJson() => {
    'callId': callId,
    'callerId': ?J.str(callerId),
    'receiverId': ?J.str(receiverId),
    'status': status.wireValue,
    if (startTime case final t?) 'startTime': _iso(t),
    'type': ?type?.wireValue,
    'category': ?J.str(category),
    'answeredDeviceId': ?J.str(answeredDeviceId),
  };
}

/// `/call/Callend` body. Also what the pending-decline queue stores.
///
/// The backend reads only `callId`, `endedById` (400 without it) and
/// `status` (only `missed` has an effect: it ends ANY call unbilled, E-92).
/// The other fields are kept for RN parity.
class CallEndInput {
  const CallEndInput({
    required this.callId,
    required this.endedById,
    this.status = CallStatus.completed,
    this.startTime,
    this.endTime,
    this.durationSeconds = 0,
    this.totalCost = 0,
    this.type = CallType.voice,
    this.callerDocumentId,
  });

  /// Receiver declines a ringing call (RN `declineCall`). [endedById]: the
  /// receiver's id.
  factory CallEndInput.decline({
    required String callId,
    required Object endedById,
    CallType type = CallType.voice,
    String? callerDocumentId,
    DateTime? at,
  }) {
    final time = at ?? DateTime.now();
    return CallEndInput(
      callId: callId,
      endedById: endedById,
      status: CallStatus.declined,
      startTime: time,
      endTime: time,
      type: type,
      callerDocumentId: callerDocumentId,
    );
  }

  /// Caller hangs up before the call connected: no `status`, so the server
  /// derives `missed` for a pending call and still bills a call that just
  /// went ongoing (E-92). [endedById]: the caller's id.
  factory CallEndInput.cancel({
    required String callId,
    required Object endedById,
    CallType type = CallType.voice,
    String? callerDocumentId,
  }) => CallEndInput(
    callId: callId,
    endedById: endedById,
    status: null,
    type: type,
    callerDocumentId: callerDocumentId,
  );

  factory CallEndInput.fromJson(Map<String, dynamic> json) => CallEndInput(
    callId: J.str(json['callId']) ?? '',
    endedById: json['endedById'] ?? '',
    status: json.containsKey('status')
        ? CallStatus.parse(json['status'])
        : null,
    startTime: J.date(json['startTime']),
    endTime: J.date(json['endTime']),
    durationSeconds: J.integer(json['duration']) ?? 0,
    totalCost: switch (json['totalCost']) {
      final num n => n,
      final other => J.number(other) ?? 0,
    },
    type: CallType.parse(json['type']),
    callerDocumentId: J.str(json['calleridDocID']),
  );

  final String callId;

  /// Public-user id of whoever ended the call (sent as given). Always set:
  /// the backend answers 400 "endedById is required" without it (E-28).
  final Object endedById;

  /// `completed` once connected, `declined` for a receiver decline, null
  /// (not sent) for a caller cancel. Never `missed` (E-92).
  final CallStatus? status;

  /// Both default to now.
  final DateTime? startTime;
  final DateTime? endTime;
  final int durationSeconds;
  final num totalCost;
  final CallType type;

  /// Caller's public-user documentId (`calleridDocID`).
  final String? callerDocumentId;

  /// RN omitted undefined keys: so does this.
  Map<String, dynamic> toJson({DateTime? now}) {
    final time = now ?? DateTime.now();
    return {
      'callId': callId,
      'status': ?status?.wireValue,
      'startTime': _iso(startTime ?? time),
      'endTime': _iso(endTime ?? time),
      'duration': durationSeconds,
      'totalCost': totalCost,
      'type': type.wireValue,
      'calleridDocID': ?callerDocumentId,
      'endedById': endedById,
    };
  }
}
