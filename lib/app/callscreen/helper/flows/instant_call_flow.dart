import 'dart:async';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/analytics/events/call_ui_events.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/log.dart';
import '../../../api/callscreen/call_api.dart';
import '../../../api/callscreen/call_errors.dart';
import '../../../api/callscreen/call_models.dart';
import '../../../api/callscreen/call_queries.dart';
import '../../../api/instant_call/instant_call_api.dart';
import '../../../api/free_call/free_call_models.dart';
import '../../../api/instant_call/instant_call_models.dart';
import '../call_alerts.dart';
import '../call_billing.dart';
import '../call_analytics.dart';
import '../call_controller.dart';
import '../call_identity.dart';
import '../call_navigator.dart';
import '../call_payload.dart';
import '../call_permissions.dart';
import '../call_platform.dart';
import '../call_ringtone.dart';
import '../call_runtime.dart';
import '../call_session.dart';
import '../call_timers.dart';
import '../engine/call_engine.dart';
import '../native/native_call_marks.dart';
import '../state/call_constants.dart';
import 'end_flow.dart';
import 'outgoing_flow.dart';

abstract final class InstantCallFlow {
  static bool _placing = false;

  /// Hosts the current instant call has rung so far (analytics).
  static int _attempts = 0;

  /// Sessions whose connection this caller has confirmed to the server
  /// (`/UpdateCall` sent, or in flight).
  static final _confirmed = <String>{};

  /// Retries of the status lookup while the accept reply is in flight.
  static List<Duration> resolveRetryDelays = const [
    Duration(milliseconds: 1500),
    Duration(seconds: 3),
    Duration(seconds: 6),
  ];

  static void debugReset() {
    _confirmed.clear();
    _attempts = 0;
    _placing = false;
  }

  /// The server searches this long by default (`max_total_ring_seconds`).
  static const defaultSearchSeconds = 120;

  /// [maxRingSeconds]: the server's search window (`/instant-call/config`);
  /// the caller waits that long, then a margin, for a host.
  ///
  /// [firstHost]: a call to a host that rolls over (admin "Direct calls roll
  /// over"): that host rings first, at their own rate.
  static Future<bool> place({
    bool video = false,
    int? maxRingSeconds,
    OutgoingRequest? firstHost,
  }) async {
    CallRuntime.ensureStarted();
    if (_placing) return false;
    final now = CallController.instance.value;
    if (now.phase.isActive) {
      CallUiEvents.instantFailed(video: video, reason: 'call_in_progress');
      return false;
    }
    if (now.phase == CallPhase.ended) CallController.instance.reset();
    _placing = true;
    CallUiEvents.instantRequested(video: video);
    try {
      return await _place(video, maxRingSeconds, firstHost);
    } catch (e) {
      Log.w('InstantCallFlow', 'place: $e');
      CallUiEvents.instantFailed(
        video: video,
        reason: 'exception',
        error: Analytics.errorCode(e),
      );
      return false;
    } finally {
      _placing = false;
    }
  }

  static Future<bool> _place(
    bool video,
    int? maxRingSeconds,
    OutgoingRequest? chosen,
  ) async {
    final callerId = CallIdentity.userId;
    if (callerId == null) {
      CallUiEvents.instantFailed(video: video, reason: 'missing_participants');
      await CallAlerts.show(
        title: CallFlowKeys.unableTitle,
        message: 'call:errors.missing_participants',
      );
      return false;
    }
    if (!await CallPermissions.ensureForOutgoing(video: video)) {
      CallUiEvents.instantFailed(video: video, reason: 'permission_denied');
      return false;
    }

    final InitiatedInstantCall started;
    try {
      final chosenId = chosen?.receiverId;
      started = await InstantCallApi.initiate(
        callerId: int.tryParse(callerId) ?? callerId,
        type: video ? 'videoCall' : 'voiceCall',
        firstHostId: chosenId == null
            ? null
            : int.tryParse(chosenId) ?? chosenId,
      );
    } on ApiException catch (e) {
      // The server won't roll this call over (switched off since, or not
      // for this caller): it is still a call to that host, placed plainly.
      final refused =
          InstantCallApi.knownErrorKey(e) == InstantCallErrorKeys.disabled;
      if (chosen != null && refused) {
        CallUiEvents.instantFailed(
          video: video,
          reason: 'rollover_refused',
          error: Analytics.errorCode(e),
        );
        return OutgoingFlow.placeDirect(chosen);
      }
      CallUiEvents.instantFailed(
        video: video,
        reason: OutgoingFlow.failureReason(e),
        error: Analytics.errorCode(e),
      );
      await CallAlerts.error(
        e,
        title: e.isUserBusy ? CallFlowKeys.busyTitle : CallFlowKeys.failedTitle,
      );
      return false;
    }

    // A rolled-over call shows the host the caller chose while they ring.
    final ringsChosen = chosen != null && !started.firstHostBusy;
    final firstHost = started.currentHost;
    _attempts = firstHost?.userId == null ? 0 : 1;
    final call = CallSession(
      role: CallRole.caller,
      callId: started.sessionId,
      callDocumentId: started.sessionId,
      channelName: started.channelName,
      token: CallPayload.repairToken(started.callerToken),
      isVideo: video,
      remote: ringsChosen
          ? CallPeer(
              id: chosen.receiverId,
              documentId: chosen.receiverDocId,
              name: chosen.name ?? firstHost?.name,
              avatarUrl: chosen.avatarUrl ?? firstHost?.profilePic,
            )
          : CallPeer(
              id: firstHost?.userId,
              name: firstHost?.name,
              avatarUrl: firstHost?.profilePic,
            ),
      callerId: callerId,
      callerDocId: CallIdentity.userDocumentId,
      callerIsCompany: CallIdentity.isCompany,
      sentAt: DateTime.now(),
      isInstantCall: true,
      instantCallSessionId: started.sessionId,
    );
    // The balance cap (hang up before the wallet runs out) needs the rate
    // the caller pays: the chosen host's, or Talk Now's (the connected push
    // corrects it when someone else answers).
    final rate = started.callerRate ?? (ringsChosen ? chosen.ratePerMin : null);
    if (rate != null && rate > 0) {
      CallBilling.rememberRate(started.sessionId, rate);
    }
    // A free search (docs/free_calls.md); the answer confirms it below.
    CallBilling.rememberFree(started.sessionId, started.freeCall);
    CallController.instance.startOutgoing(call);
    unawaited(_markOutgoing(CallController.instance.value));
    // The server says when its search failed (`INSTANT_CALL_FAILED`); if
    // that push is lost, give up once its window is surely over.
    final window = Duration(
      seconds: (maxRingSeconds ?? defaultSearchSeconds) + 15,
    );
    CallTimers.instance.arm(CallTimers.noAnswer, window, () {
      final now = CallController.instance.value;
      if (now.isSameCall(started.sessionId) && now.phase.isPreConnect) {
        unawaited(EndFlow.hangup(reason: CallEndReason.noAnswer));
      }
    });
    CallNavigator.toCall();
    unawaited(_joinAndRing(call));
    return true;
  }

  static Future<void> _markOutgoing(CallSession call) async {
    try {
      await CallPlatform.instance.markOutgoing(call);
    } catch (e) {
      Log.w('InstantCallFlow', 'markOutgoing: $e');
    }
  }

  static Future<void> _joinAndRing(CallSession call) async {
    final uid = call.localUid;
    if (uid != null) {
      await CallEngine.instance.join(
        channel: call.channelName ?? '',
        token: call.token ?? '',
        uid: uid,
        video: call.isVideo,
      );
    }
    final now = CallController.instance.value;
    if (now.isSameCall(call.callId) &&
        now.phase.isPreConnect &&
        !CallEngine.instance.hasRemote) {
      await CallRingtone.play(CallTone.ringback);
    }
  }

  static void onHostChanged(Map<String, dynamic> data) {
    final session = CallController.instance.value;
    if (!session.isInstantCall || !session.phase.isPreConnect) return;
    final sessionId = data['instantCallSessionId']?.toString();
    if (sessionId != session.instantCallSessionId) return;
    final host = InstantCallHost.fromPush(data);
    if (host.userId == null) return;
    if (host.userId != session.remote.id) {
      _attempts++;
      CallUiEvents.instantHostAssigned(
        callId: session.callId,
        attempt: _attempts,
      );
    }
    CallController.instance.update(
      (s) => s.copyWith(
        remote: CallPeer(
          id: host.userId,
          name: host.name,
          avatarUrl: host.profilePic,
        ),
      ),
    );
  }

  /// Caller: the host is in the channel — tell the server the call
  /// connected (`/UpdateCall`), which is when its bill starts. The record
  /// is `pending` from the host's answer until then, so a call nobody
  /// joined is never billed. The record id comes with the
  /// `INSTANT_CALL_CONNECTED` push; if that is late or lost, the session's
  /// status says. Once per session; a failure lets a later trigger retry
  /// (the server also connects it itself when it sees both in the channel).
  static Future<void> confirmConnected(CallSession s) async {
    if (!s.isInstantCall || !s.isCaller) return;
    final sessionId = s.instantCallSessionId ?? s.callId;
    if (sessionId == null || !_confirmed.add(sessionId)) return;
    try {
      final ok = await _confirm(s, sessionId);
      if (!ok) _confirmed.remove(sessionId);
    } catch (e) {
      _confirmed.remove(sessionId);
      Log.w('InstantCallFlow', 'confirmConnected: $e');
    }
  }

  static bool _stillOn(String sessionId) {
    final now = CallController.instance.value;
    return now.isSameCall(sessionId) && now.phase.isActive;
  }

  static Future<bool> _confirm(CallSession s, String sessionId) async {
    var record = s.serverCallId;
    var hostId = s.receiverId;
    for (final wait in [Duration.zero, ...resolveRetryDelays]) {
      if (record != null) break;
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      if (!_stillOn(sessionId)) return true; // over: nothing to confirm
      final live = CallController.instance.value;
      record = live.serverCallId; // the push may have landed meanwhile
      hostId ??= live.receiverId;
      if (record != null) break;
      try {
        final found = await InstantCallApi.connectedCall(sessionId);
        if (found != null) {
          record = found.callId;
          hostId ??= found.hostUserId;
          // The call record says whether it is free (the push may be lost).
          CallBilling.rememberFree(sessionId, found.freeCall);
          _adopt(sessionId, found.callId, hostId);
        }
      } catch (e) {
        Log.w('InstantCallFlow', 'status: $e');
      }
    }
    if (record == null) {
      Log.w('InstantCallFlow', 'connected but no call record for $sessionId');
      return false;
    }
    final update = CallStatusUpdate(
      callId: record,
      callerId: s.callerId,
      receiverId: hostId,
      type: s.isVideo ? CallType.video : CallType.voice,
    );
    for (final wait in [Duration.zero, ...CallTimings.updateRetry]) {
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      if (!_stillOn(sessionId)) return true;
      try {
        await CallRequests.updateStatus(update);
        return true;
      } on ApiException catch (e) {
        // Already ongoing / ended: nothing more to say.
        if (e.type == ApiErrorType.conflict ||
            e.type == ApiErrorType.rejected ||
            e.type == ApiErrorType.notFound) {
          Log.w('InstantCallFlow', 'UpdateCall refused: $e');
          return true;
        }
        Log.w('InstantCallFlow', 'UpdateCall failed: $e');
      }
    }
    return false;
  }

  /// The call record (and who answered) onto the live call.
  static void _adopt(String sessionId, String record, String? hostId) {
    unawaited(NativeCallMarks.saveServerCallId(sessionId, record));
    final live = CallController.instance.value;
    if (!live.isSameCall(sessionId)) return;
    if (live.serverCallId == record &&
        (hostId == null || live.receiverId == hostId)) {
      return;
    }
    CallController.instance.update(
      (c) =>
          c.copyWith(serverCallId: record, receiverId: hostId ?? c.receiverId),
    );
  }

  static void onConnected(Map<String, dynamic> data) {
    final session = CallController.instance.value;
    if (!session.isInstantCall) return;
    final sessionId = data['instantCallSessionId']?.toString();
    if (sessionId != session.instantCallSessionId) return;
    final hostId = data['hostUserId']?.toString();
    final hostName = data['hostName']?.toString();
    final hostPic = data['hostProfilePic']?.toString();
    // The call record the backend created: Callend bills it.
    final record = CallPayload.read(data, const ['callId']);
    final ring = session.callId;
    if (record != null && ring != null) {
      unawaited(NativeCallMarks.saveServerCallId(ring, record));
    }
    // The rate this call bills at (whoever answered): the balance cap.
    final rate = num.tryParse(
      CallPayload.read(data, const ['callerRate']) ?? '',
    );
    if (ring != null && rate != null && rate > 0) {
      CallBilling.rememberRate(ring, rate.toDouble());
    }
    // Whether the call the host answered is free (docs/free_calls.md): the
    // answer decides, so no free minutes here takes the search's back.
    if (ring != null) {
      CallBilling.rememberFree(
        ring,
        FreeCallTerms.of(
          CallPayload.read(data, const ['freeMinutes']),
          CallPayload.read(data, const ['freeContinuePaid']),
        ),
      );
    }
    CallUiEvents.instantMatched(callId: session.callId, hostUserId: hostId);
    CallController.instance.update(
      (s) => s.copyWith(
        receiverId: hostId,
        serverCallId: record,
        remote: hostId == null
            ? null
            : CallPeer(
                id: hostId,
                name: hostName ?? s.remote.name,
                avatarUrl: hostPic ?? s.remote.avatarUrl,
              ),
      ),
    );
    // The host may already be in the channel (the push often lands after
    // the remote join): confirm now, with the record id just learnt.
    final now = CallController.instance.value;
    if (now.isCaller &&
        (now.phase == CallPhase.ongoing || CallEngine.instance.hasRemote)) {
      unawaited(confirmConnected(now));
    }
  }

  static void onFailed(Map<String, dynamic> data) {
    final session = CallController.instance.value;
    if (!session.isInstantCall) return;
    final sessionId = data['instantCallSessionId']?.toString();
    if (sessionId != session.instantCallSessionId) return;
    // Only a search can fail: a call a host already answered goes on (the
    // host may be in the channel before the 500 ms connect delay ran).
    if (!session.phase.isPreConnect || CallEngine.instance.hasRemote) return;
    CallUiEvents.instantNoHost(callId: session.callId, attempts: _attempts);
    // Nobody picked up: CallAnalytics files it as not answered.
    CallAnalytics.reason(session.callId, CallEndReason.noAnswer);
    CallController.instance.end();
  }

  /// Ends the caller's search (`/instant-call/cancel`). [call]: the call
  /// that just ended (the live slot may already be reset by then).
  static Future<void> cancel([CallSession? call]) async {
    final session = call ?? CallController.instance.value;
    // The caller's search only (the server refuses anyone else's cancel).
    if (!session.isInstantCall || !session.isCaller) return;
    final sessionId = session.instantCallSessionId;
    if (sessionId == null) return;
    // Every hang-up comes through here; a search that connected is over on
    // the server already (Callend ends the call), nothing to cancel.
    if (session.everConnected) return;
    CallUiEvents.instantCancelled(callId: session.callId, attempts: _attempts);
    try {
      await InstantCallApi.cancel(sessionId);
    } catch (e) {
      Log.w('InstantCallFlow', 'cancel: $e');
    }
  }
}
