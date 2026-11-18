import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

/// Where the one live call is (RN `call.store` `status`). `initiating` is
/// folded into [calling]. Never the backend `CallStatus`.
enum CallPhase {
  idle,

  /// Caller: `/initiateCall` succeeded, joined, ringback playing.
  calling,

  /// Receiver: incoming UI up. Caller: the receiver's phone rings (ack).
  ringing,

  /// Answered, waiting for the other side in the channel ("connecting").
  accepted,

  /// Both in the channel; the timer runs.
  ongoing,

  /// Ended summary / feedback; then [idle].
  ended;

  bool get isLive => this == accepted || this == ongoing;

  /// Caller still waiting for an answer.
  bool get isPreConnect => this == calling || this == ringing;

  /// A call is in progress in any form (not idle, not ended).
  bool get isActive => this != idle && this != ended;
}

enum CallRole { caller, receiver }

/// The other person on the call.
@immutable
class CallPeer {
  const CallPeer({
    this.id,
    this.documentId,
    this.name,
    this.avatarUrl,
    this.isCompany = false,
  });

  /// Numeric public-user id (string), the Agora uid of that side.
  final String? id;
  final String? documentId;

  /// Raw name from the push / host card; null when unknown (screens pick
  /// their RN fallback: "Caller", "Host", "Expert", "User").
  final String? name;

  /// Absolute URL (relative paths resolved by the payload parser).
  final String? avatarUrl;

  /// `is_company_account`: blue ring + "App Official" badges.
  final bool isCompany;

  @override
  bool operator ==(Object other) =>
      other is CallPeer &&
      other.id == id &&
      other.documentId == documentId &&
      other.name == name &&
      other.avatarUrl == avatarUrl &&
      other.isCompany == isCompany;

  @override
  int get hashCode => Object.hash(id, documentId, name, avatarUrl, isCompany);
}

/// Snapshot of the one call (RN `call.store` + `callContext`). Immutable:
/// every transition publishes a new value, so `ValueListenableBuilder`s
/// with a `select`-style check rebuild only for the fields they read.
@immutable
class CallSession {
  const CallSession({
    this.phase = CallPhase.idle,
    this.role,
    this.callId,
    this.callDocumentId,
    this.channelName,
    this.token,
    this.isVideo = false,
    this.remote = const CallPeer(),
    this.callerId,
    this.receiverId,
    this.callerDocId,
    this.receiverDocId,
    this.category,
    this.categoryName,
    this.callerIsCompany = false,
    this.sentAt,
    this.autoAccept = false,
    this.openedLocked = false,
    this.connectedAt,
    this.endedAt,
    this.phaseSince,
    this.isInstantCall = false,
    this.instantCallSessionId,
    this.serverCallId,
    this.rollover = false,
  });

  static const idle = CallSession();

  final CallPhase phase;
  final CallRole? role;

  /// Numeric call id as a string: the id every call endpoint takes.
  final String? callId;
  final String? callDocumentId;
  final String? channelName;

  /// Agora token for THIS side (caller: `callerToken`; receiver: push
  /// `token` / `receiverToken`), `+` already repaired.
  final String? token;
  final bool isVideo;
  final CallPeer remote;

  /// Numeric public-user ids (strings) of both sides. The Agora uid of a
  /// side is its id (backend binds each token to it).
  final String? callerId;
  final String? receiverId;

  /// `calleridDocID` / `receiverDocID`.
  final String? callerDocId;
  final String? receiverDocId;
  final String? category;
  final String? categoryName;

  /// The caller is a company account (free call, "Company Account" pill).
  final bool callerIsCompany;

  /// Push `timestamp` (when the backend sent the ring), for stale checks.
  final DateTime? sentAt;

  /// Answered from CallKit / a notification before the UI existed.
  final bool autoAccept;

  /// The device was locked when the call arrived.
  final bool openedLocked;

  /// Wall clock at connect (`startedAt`): duration and billing source.
  final DateTime? connectedAt;
  final DateTime? endedAt;

  /// Wall clock when the call entered its current [phase] (set by
  /// [CallController] on every move to calling / ringing / accepted /
  /// ongoing, and when a new call takes the slot). Screens use it so a
  /// guard window survives a remount (minimize, then return).
  final DateTime? phaseSince;

  /// Talk Now: [callId] is the instant-call SESSION's id (the ring and
  /// every local map key); the call record the backend bills is created
  /// when a host accepts, as [serverCallId].
  final bool isInstantCall;
  final String? instantCallSessionId;

  /// Talk Now: the `api::call.call` id once a host accepted (host: the
  /// host-accept reply; caller: `INSTANT_CALL_CONNECTED`).
  final String? serverCallId;

  /// A call to the host the caller chose (their profile), run by the Talk
  /// Now engine only so it can roll over to others: the caller sees a
  /// normal call ("Calling", "Ringing"), never a search.
  final bool rollover;

  /// The Talk Now button's search for any free host ("Searching...").
  bool get isSearch => isInstantCall && !rollover;

  /// The caller's Talk Now search that no host has joined: whoever is being
  /// rung is not the call, so no name or photo shows anywhere (screen,
  /// header, bar, picture-in-picture, notification) until one connects;
  /// nor after, when it ended without anyone (the caller hung up, nobody
  /// took it). Only the Talk Now button's search: a call to a chosen host
  /// (a rolled-over profile call too) names its host as ever.
  bool get hidesPeer =>
      isCaller &&
      isSearch &&
      !everConnected &&
      (phase.isPreConnect ||
          phase == CallPhase.ended ||
          phase == CallPhase.idle);

  /// The other side's name / photo as the caller may see them now.
  String? get shownName => hidesPeer ? null : remote.name;
  String? get shownAvatar => hidesPeer ? null : remote.avatarUrl;

  /// The id `/call/Callend` takes: the call record. A Talk Now call has
  /// none until a host accepts (then nothing is billed: the session is
  /// cancelled or declined through `/instant-call/*` instead).
  String? get backendCallId => isInstantCall ? serverCallId : callId;

  bool get isCaller => role == CallRole.caller;
  bool get isReceiver => role == CallRole.receiver;

  /// The call reached `ongoing` at least once.
  bool get everConnected => connectedAt != null;

  /// Agora uid of this device: by role, never `user.id` (on a cold-start
  /// accept the session may not be restored yet). Null when unknown.
  int? get localUid {
    final raw = isCaller ? callerId : receiverId;
    final n = int.tryParse(raw ?? '');
    return n != null && n > 0 ? n : null;
  }

  /// Seconds talked (wall clock), at least 1 once connected.
  int durationSeconds([DateTime? now]) {
    final start = connectedAt;
    if (start == null) return 0;
    final end = endedAt ?? now ?? clock.now();
    final s = end.difference(start).inSeconds;
    return s < 1 ? 1 : s;
  }

  /// Same call (numeric id or documentId; for Talk Now also the call
  /// record's id, which the backend's pushes after the accept carry).
  bool isSameCall(String? id) =>
      id != null &&
      id.isNotEmpty &&
      (id == callId || id == callDocumentId || id == serverCallId);

  CallSession copyWith({
    CallPhase? phase,
    CallRole? role,
    String? callId,
    String? callDocumentId,
    String? channelName,
    String? token,
    bool? isVideo,
    CallPeer? remote,
    String? callerId,
    String? receiverId,
    String? callerDocId,
    String? receiverDocId,
    String? category,
    String? categoryName,
    bool? callerIsCompany,
    DateTime? sentAt,
    bool? autoAccept,
    bool? openedLocked,
    DateTime? connectedAt,
    DateTime? endedAt,
    DateTime? phaseSince,
    bool? isInstantCall,
    String? instantCallSessionId,
    String? serverCallId,
    bool? rollover,
  }) => CallSession(
    phase: phase ?? this.phase,
    role: role ?? this.role,
    callId: callId ?? this.callId,
    callDocumentId: callDocumentId ?? this.callDocumentId,
    channelName: channelName ?? this.channelName,
    token: token ?? this.token,
    isVideo: isVideo ?? this.isVideo,
    remote: remote ?? this.remote,
    callerId: callerId ?? this.callerId,
    receiverId: receiverId ?? this.receiverId,
    callerDocId: callerDocId ?? this.callerDocId,
    receiverDocId: receiverDocId ?? this.receiverDocId,
    category: category ?? this.category,
    categoryName: categoryName ?? this.categoryName,
    callerIsCompany: callerIsCompany ?? this.callerIsCompany,
    sentAt: sentAt ?? this.sentAt,
    autoAccept: autoAccept ?? this.autoAccept,
    openedLocked: openedLocked ?? this.openedLocked,
    connectedAt: connectedAt ?? this.connectedAt,
    endedAt: endedAt ?? this.endedAt,
    phaseSince: phaseSince ?? this.phaseSince,
    isInstantCall: isInstantCall ?? this.isInstantCall,
    instantCallSessionId: instantCallSessionId ?? this.instantCallSessionId,
    serverCallId: serverCallId ?? this.serverCallId,
    rollover: rollover ?? this.rollover,
  );
}

/// Live media state of the call (owned by the Agora engine service), kept
/// apart from [CallSession] so a mute or a remote camera change rebuilds only
/// the widgets that show it.
@immutable
class CallMedia {
  const CallMedia({
    this.engineReady = false,
    this.joined = false,
    this.remoteUid,
    this.remoteVideoOff = false,
    this.localVideoOff = false,
    this.muted = false,
    this.speakerOn = false,
    this.frontCamera = true,
    this.localViewKey = 0,
    this.remoteViewKey = 0,
  });

  static const initial = CallMedia();

  /// Engine initialised (video views may be built).
  final bool engineReady;

  /// This device is in the channel.
  final bool joined;

  /// The other side's uid once it joined the channel.
  final int? remoteUid;
  final bool remoteVideoOff;
  final bool localVideoOff;
  final bool muted;

  /// Earpiece by default for audio AND video (RN).
  final bool speakerOn;
  final bool frontCamera;

  /// Bumped to remount a native video view (camera flip, remote video
  /// restart), RN "render keys".
  final int localViewKey;
  final int remoteViewKey;

  CallMedia copyWith({
    bool? engineReady,
    bool? joined,
    int? remoteUid,
    bool clearRemoteUid = false,
    bool? remoteVideoOff,
    bool? localVideoOff,
    bool? muted,
    bool? speakerOn,
    bool? frontCamera,
    int? localViewKey,
    int? remoteViewKey,
  }) => CallMedia(
    engineReady: engineReady ?? this.engineReady,
    joined: joined ?? this.joined,
    remoteUid: clearRemoteUid ? null : (remoteUid ?? this.remoteUid),
    remoteVideoOff: remoteVideoOff ?? this.remoteVideoOff,
    localVideoOff: localVideoOff ?? this.localVideoOff,
    muted: muted ?? this.muted,
    speakerOn: speakerOn ?? this.speakerOn,
    frontCamera: frontCamera ?? this.frontCamera,
    localViewKey: localViewKey ?? this.localViewKey,
    remoteViewKey: remoteViewKey ?? this.remoteViewKey,
  );

  @override
  bool operator ==(Object other) =>
      other is CallMedia &&
      other.engineReady == engineReady &&
      other.joined == joined &&
      other.remoteUid == remoteUid &&
      other.remoteVideoOff == remoteVideoOff &&
      other.localVideoOff == localVideoOff &&
      other.muted == muted &&
      other.speakerOn == speakerOn &&
      other.frontCamera == frontCamera &&
      other.localViewKey == localViewKey &&
      other.remoteViewKey == remoteViewKey;

  @override
  int get hashCode => Object.hash(
    engineReady,
    joined,
    remoteUid,
    remoteVideoOff,
    localVideoOff,
    muted,
    speakerOn,
    frontCamera,
    localViewKey,
    remoteViewKey,
  );
}
