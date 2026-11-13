import 'package:flutter/foundation.dart';

import '../../../core/network/strapi.dart';
import '../free_call/free_call_models.dart';

enum InstantCallSessionStatus {
  searching,
  ringing,
  connected,
  completed,
  failed,
  cancelled,
  unknown;

  static InstantCallSessionStatus parse(Object? raw) {
    final s = (J.str(raw) ?? '').trim().toLowerCase();
    for (final v in values) {
      if (v != unknown && v.name == s) return v;
    }
    return unknown;
  }

  bool get isActive => this == searching || this == ringing;
  bool get isTerminal =>
      this == completed || this == failed || this == cancelled;
}

class InstantCallHost {
  const InstantCallHost({
    this.userId,
    this.name,
    this.profilePic,
    this.ringAttemptIndex,
  });

  final String? userId;
  final String? name;
  final String? profilePic;
  final int? ringAttemptIndex;

  /// The initiate reply's `currentHost` / `parallelHosts[]`
  /// (`{userId, name, profilePic}`); the push field names are taken too.
  factory InstantCallHost.fromJson(Map<String, dynamic> json) =>
      InstantCallHost(
        userId: J.str(json['userId'] ?? json['hostUserId']),
        name: J.str(json['name'] ?? json['hostName']),
        profilePic: J.str(json['profilePic'] ?? json['hostProfilePic']),
        ringAttemptIndex: J.integer(json['ringAttemptIndex']),
      );

  factory InstantCallHost.fromPush(Map<String, dynamic> data) =>
      InstantCallHost(
        userId: J.str(data['hostUserId']),
        name: J.str(data['hostName']),
        profilePic: J.str(data['hostProfilePic']),
        ringAttemptIndex: J.integer(data['ringAttemptIndex']),
      );
}

class InitiatedInstantCall {
  const InitiatedInstantCall({
    required this.sessionId,
    required this.callerToken,
    required this.channelName,
    this.currentHost,
    this.parallelHosts,
    this.callerRate,
    this.firstHost,
    this.firstHostBusy = false,
    this.freeCall,
  });

  final String sessionId;
  final String callerToken;
  final String channelName;
  final InstantCallHost? currentHost;
  final List<InstantCallHost>? parallelHosts;

  /// A rolled-over direct call: the host the caller chose (rung first,
  /// unless [firstHostBusy]).
  final InstantCallHost? firstHost;
  final bool firstHostBusy;

  /// ₹/min the caller pays for Talk Now (the config's caller rate).
  final double? callerRate;

  /// The search may start free (docs/free_calls.md). The answer decides:
  /// the connected push / status says whether the call itself is free.
  final FreeCallTerms? freeCall;

  static InitiatedInstantCall? tryParse(Map<String, dynamic> body) {
    final sessionId = J.str(body['sessionId']);
    final token = J.str(body['callerToken']);
    final channel = J.str(body['channelName']);
    if (sessionId == null || token == null || channel == null) return null;

    final hostMap = body['currentHost'];
    final host = hostMap is Map<String, dynamic>
        ? InstantCallHost.fromJson(hostMap)
        : null;

    final parallelList = body['parallelHosts'];
    final parallel = parallelList is List
        ? [
            for (final h in parallelList)
              if (h is Map<String, dynamic>) InstantCallHost.fromJson(h),
          ]
        : null;

    final first = body['firstHost'];
    return InitiatedInstantCall(
      sessionId: sessionId,
      callerToken: token,
      channelName: channel,
      currentHost: host ?? parallel?.firstOrNull,
      parallelHosts: parallel,
      callerRate: J.number(body['callerRate']),
      firstHost: first is Map<String, dynamic>
          ? InstantCallHost.fromJson(first)
          : null,
      firstHostBusy: first is Map && J.boolean(first['busy']),
      freeCall: FreeCallTerms.tryParse(body['freeCall']),
    );
  }
}

/// `GET /instant-call/status/:id` once a host answered: the call record
/// (what Callend bills and `/UpdateCall` confirms) and who answered.
@immutable
class InstantConnectedCall {
  const InstantConnectedCall({
    required this.callId,
    this.hostUserId,
    this.hostName,
    this.callStatus,
    this.freeCall,
  });

  final String callId;
  final String? hostUserId;
  final String? hostName;

  /// `pending` until the caller confirms the connection, then `ongoing`.
  final String? callStatus;

  /// The call record is a free call (docs/free_calls.md); null: paid.
  final FreeCallTerms? freeCall;

  static InstantConnectedCall? tryParse(Map<String, dynamic>? body) {
    final call = body?['connectedCall'];
    final id = call is Map ? J.str(call['id']) : null;
    if (id == null) return null;
    final host = body?['connectedHost'];
    return InstantConnectedCall(
      callId: id,
      callStatus: call is Map ? J.str(call['status']) : null,
      hostUserId: host is Map ? J.str(host['userId']) : null,
      hostName: host is Map ? J.str(host['name']) : null,
      freeCall: call is Map ? FreeCallTerms.tryParse(call['freeCall']) : null,
    );
  }
}

/// `GET /instant-call/config`: Talk Now for the signed-in user.
@immutable
class InstantCallConfig {
  const InstantCallConfig({
    required this.enabled,
    this.allowedCallTypes = 'voice_only',
    this.callerVoiceRate,
    this.callerVideoRate,
    this.maxRingSeconds,
    this.directRollover = false,
  });

  factory InstantCallConfig.fromJson(Map<String, dynamic> json) =>
      InstantCallConfig(
        enabled: J.boolean(json['enabled']),
        allowedCallTypes: J.str(json['allowedCallTypes']) ?? 'voice_only',
        callerVoiceRate: J.number(json['callerVoiceRate']),
        callerVideoRate: J.number(json['callerVideoRate']),
        maxRingSeconds: J.integer(json['maxRingSeconds']),
        directRollover: J.boolean(json['directRollover']),
      );

  static const off = InstantCallConfig(enabled: false);

  final bool enabled;

  /// `voice_only`, `video_only` or `both`.
  final String allowedCallTypes;
  final double? callerVoiceRate;
  final double? callerVideoRate;

  /// How long the server searches for a host (null: an older backend).
  final int? maxRingSeconds;

  /// A call to a host rings them first, then other hosts join the same way
  /// as Talk Now (admin "Call rollover"). Switched apart from the Talk Now
  /// button: on even while [enabled] is off.
  final bool directRollover;

  /// The call type the one-tap button places.
  bool get placesVideo => allowedCallTypes == 'video_only';

  /// Talk Now takes this call type.
  bool allows({required bool video}) => switch (allowedCallTypes) {
    'video_only' => video,
    'voice_only' => !video,
    _ => true,
  };

  /// A [video] call to a host should roll over.
  bool rollsOver({required bool video}) =>
      directRollover && allows(video: video);
}

/// `POST /instant-call/host-accept`: the call record a Talk Now ring became.
@immutable
class InstantHostAccept {
  const InstantHostAccept({
    required this.callId,
    this.channelName,
    this.hostToken,
  });

  static InstantHostAccept? tryParse(Map<String, dynamic> body) {
    if (body['success'] == false) return null;
    final id = J.str(body['callId']);
    if (id == null) return null;
    final token = J.str(body['hostToken']);
    return InstantHostAccept(
      callId: id,
      channelName: J.str(body['channelName']),
      hostToken: token == null || token.isEmpty ? null : token,
    );
  }

  /// The `api::call.call` id: Callend bills it.
  final String callId;
  final String? channelName;
  final String? hostToken;
}
