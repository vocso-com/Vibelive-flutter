import 'dart:async';

import '../../../../core/query/query_client.dart';
import '../../../../core/router/app_router.dart';
import '../../../api/callscreen/call_keys.dart';
import '../../../api/callscreen/call_models.dart';
import '../../../api/callscreen/call_queries.dart';
import '../../../api/paymentscreen/payment_keys.dart';
import '../call_analytics.dart';
import '../call_controller.dart';
import '../call_identity.dart';
import '../call_navigator.dart';
import '../call_payload.dart';
import '../call_platform.dart';
import '../call_ringtone.dart';
import '../call_runtime.dart';
import '../call_session.dart';
import '../call_signals.dart';
import '../call_timers.dart';
import '../engine/call_engine.dart';
import '../state/call_constants.dart';
import '../state/call_dedup.dart';
import '../state/call_store.dart';
import 'end_flow.dart';
import 'incoming_flow.dart';

/// Call pushes, already classified by the push layer (RN spec §5.3–5.5,
/// native spec §4.3). Every guard here exists because a real push did the
/// wrong thing once; the E-numbers say which.
abstract final class PushFlow {
  static CallController get _calls => CallController.instance;

  /// Caller-side statuses that must never ring (E-75).
  static const _remoteRingingTypes = {
    'call_ringing',
    'callringing',
    'call_ringing_legacy',
    'ringing',
  };

  static Future<void> onInvite(
    Map<String, dynamic> data, {
    required bool foreground,
    CallPushSource source = CallPushSource.fcm,
  }) async {
    CallRuntime.ensureStarted();
    final self = CallIdentity.userId;
    final payload = CallPayload.parse(data, selfId: self);
    if (payload == null) return;
    final callId = payload.callId;
    final call = payload.session;
    final type = (CallPayload.read(payload.data, const ['type']) ?? '')
        .toLowerCase();
    if (_remoteRingingTypes.contains(type)) return onRemoteRinging(callId);
    if (!payload.hasJoinCreds) return; // E-7: a bare callId never rings
    if (CallDedup.instance.isEnded(callId)) return; // E-18
    if (self != null && call.callerId == self) return; // E-19 self-call
    // E-75: only ring when the call is for this user.
    if (self != null && call.receiverId != null && call.receiverId != self) {
      return;
    }
    final live = _calls.value;
    if (live.isSameCall(callId) && live.phase.isActive) {
      // E-5 / E-6: a re-delivery of the call in progress never re-opens the
      // incoming screen or re-fills the store (the join would restart).
      if (live.isReceiver && live.phase == CallPhase.ringing) _ack(live);
      return;
    }
    // Native keeps a VoIP ring for 120 s; a foreground VoIP push is shown
    // in-app (no CallKit) and must live as long (I3).
    final ttl = source == CallPushSource.voip && !foreground
        ? CallTimings.voipInviteTtl
        : CallTimings.ringPayloadTtl;
    if (payload.isStale(ttl)) return; // E-13
    if (source == CallPushSource.voip) {
      if (await CallStore.isHandled(callId)) return; // E-4
      await CallStore.markHandled(callId);
    } else if (source == CallPushSource.fcm &&
        !CallDedup.instance.claim(payload.fingerprint)) {
      return; // E-2
    }
    // A system ringer already up for it (iOS CallKit while `.inactive`,
    // the Android plugin): never a second, in-app ring (I2).
    final nativeUp = await _isNativeRinging(callId);
    // A different call while one is live is ignored (E-61, decision 17).
    if (!_calls.receive(call)) return;
    CallRuntime.rememberInvite(callId, data);
    // A notification tap re-delivers a push whose first delivery (the
    // background handler) already acked it (A8: no second ack).
    if (source != CallPushSource.notificationTap) _ack(_calls.value);
    unawaited(IncomingFlow.noteLocked(callId)); // A9
    // Decision 7: no end push within a minute → dismiss here, no API. UI
    // isolate only: an accept never reaches a background isolate (A1).
    if (CallRuntime.isUiIsolate) {
      // The server may ask for a longer ring (a Talk Now cascade rings until
      // its search ends); a little extra for its end push to arrive.
      final asked = CallPayload.ringLength(data);
      final ring =
          asked != null &&
              asked + const Duration(seconds: 5) > CallTimings.incomingRing
          ? asked + const Duration(seconds: 5)
          : CallTimings.incomingRing;
      CallTimers.instance.arm(
        CallTimers.incomingRing,
        ring,
        () => unawaited(_ringTimedOut(callId)),
      );
    }
    final systemRinging =
        !foreground || nativeUp || source == CallPushSource.notificationTap;
    if (systemRinging) IncomingFlow.markNativeRinging(callId);
    // A notification-body tap dismisses the plugin's ringer: the app rings
    // instead (A8), unless the ringer was kept (locked screen: the system
    // ringtone keeps going, RN `wasOpenedLocked`). Otherwise a system ringer
    // up means no in-app ring.
    final ring =
        (source == CallPushSource.notificationTap && !nativeUp) ||
        !systemRinging;
    if (foreground) await present(callId, ring: ring);
  }

  static Future<bool> _isNativeRinging(String callId) async {
    try {
      return await CallPlatform.instance.isNativeRinging(callId);
    } catch (_) {
      return false;
    }
  }

  /// The in-app ring got no end push in time. A call answered here, or one
  /// a system ringer still owns (its own timeout ends it), is left alone:
  /// ending it would end the native call too (A1).
  static Future<void> _ringTimedOut(String callId) async {
    if (CallDedup.instance.answeredHere(callId)) return;
    final s = _calls.value;
    if (!s.isSameCall(callId) || s.phase != CallPhase.ringing) return;
    if (IncomingFlow.isMarkedNativeRinging(callId) &&
        await _isNativeRinging(callId)) {
      return;
    }
    EndFlow.dismissRinging(callId, reason: CallEndReason.ringTimeout);
  }

  /// Ringing ack once per call; never blocks, never throws (E-25).
  static void _ack(CallSession s) {
    final callId = s.callId;
    final receiverId = s.receiverId ?? CallIdentity.userId;
    if (callId == null || receiverId == null) return;
    // Talk Now too: its callId is the search session's id, and the backend
    // records "rang on phone" for this host (admin's ring proof). Without it
    // a ring shown with the app open read as "Sent to phone, not proof".
    if (!CallDedup.instance.beginAck(callId)) return;
    unawaited(
      CallRequests.sendRingingAck(
        callId: callId,
        receiverId: receiverId,
      ).then((ok) => CallDedup.instance.finishAck(callId, ok: ok)),
    );
  }

  /// The app is in front and no system ringer is up (iOS foreground
  /// suppress, Android foreground): the in-app screen and ringtone. A
  /// never-throwing future that keeps presenting for
  /// [CallTimings.foregroundHold], retrying a router that is not ready
  /// every [CallTimings.foregroundRetry] (mem #1); it stops as soon as the
  /// call is answered or ended. Never shown twice for one call (E-1).
  static Future<void> present(String callId, {bool ring = true}) async {
    try {
      final deadline = DateTime.now().add(CallTimings.foregroundHold);
      if (ring) unawaited(CallRingtone.play(CallTone.incoming));
      unawaited(CallEngine.instance.startIncomingPreview());
      var shown = false;
      while (true) {
        final s = _calls.value;
        if (CallDedup.instance.isEnded(callId) ||
            !s.isSameCall(callId) ||
            s.phase != CallPhase.ringing) {
          return;
        }
        if (!shown) shown = CallNavigator.showIncoming();
        final left = deadline.difference(DateTime.now());
        if (left <= Duration.zero) {
          if (!shown) CallNavigator.queue(AppRoutes.incomingCall);
          return;
        }
        await Future<void>.delayed(shown ? left : CallTimings.foregroundRetry);
      }
    } catch (_) {}
  }

  /// Caller: the receiver's phone rings (`CALL_RINGING`, RN C6).
  static void onRemoteRinging(String callId) {
    CallRuntime.ensureStarted();
    if (!CallDedup.instance.shouldHandleSignal('ringing', callId)) return;
    final s = _calls.value;
    if (!s.isCaller || !isMatching(callId)) return;
    _calls.setRinging();
  }

  /// `CallTimer` / accepted / connected. Receiver: confirmation only, never
  /// rings or tears down (mem #5). Caller: answered → connected (RN C7).
  static void onOngoingSignal(String callId, Map<String, dynamic> data) {
    CallRuntime.ensureStarted();
    final s = _calls.value;
    if (!s.phase.isActive || !s.isCaller || !isMatching(callId, data)) return;
    _calls.setAccepted();
    if ((s.channelName ?? '').isNotEmpty && (s.token ?? '').isNotEmpty) {
      _calls.setConnected();
    }
    // A documentId-keyed push: remember it, keep the numeric id (E-71).
    if (!_numeric(callId) && s.callDocumentId == null) {
      _calls.update((c) => c.copyWith(callDocumentId: callId));
    }
  }

  /// `CALL_ENDED` (+ declined / missed / cancel / missed history). A
  /// ringing / calling / accepted call ends now (E-45, E-46). An ongoing
  /// one is Agora's remote quit to end (E-47: duration, Callend, rating);
  /// when the server ended it (low balance, admin) nobody leaves the
  /// channel, so it ends locally after [CallTimings.endedPushGrace].
  static Future<void> onEnded(String callId, {String? status}) async {
    CallRuntime.ensureStarted();
    if (callId.isEmpty) return;
    if (!CallDedup.instance.shouldHandleSignal('ended', callId)) return;
    CallDedup.instance
      ..markEnded(callId)
      ..releaseClaims(callId);
    IncomingFlow.clearNativeRinging(callId);
    unawaited(CallStore.clearPendingAccept(callId));
    // Balance and history changed (spec §9.6).
    queryCache.invalidateAll([
      ...CallKeys.afterCallChange(callId),
      ...PaymentKeys.walletData,
    ]);
    final s = _calls.value;
    if (!s.phase.isActive || !isMatching(callId)) return;
    final id = s.callId!;
    switch (s.phase) {
      case CallPhase.ringing when s.isReceiver:
        EndFlow.dismissRinging(id);
      case CallPhase.ongoing:
        if (CallStatus.parse(status) == CallStatus.forceCompleteByAdmin) {
          EndFlow.endLocally(id, reason: CallEndReason.adminEnded);
        } else {
          CallTimers.instance.arm(
            CallTimers.endedPush,
            CallTimings.endedPushGrace,
            () => EndFlow.endLocally(id),
          );
        }
      default:
        EndFlow.endLocally(id);
    }
  }

  /// `CALL_ANSWERED_ELSEWHERE`: stop ringing here unless this device
  /// answered or is in the call (E-76). No API.
  static void onAnsweredElsewhere(String callId) {
    CallRuntime.ensureStarted();
    if (CallDedup.instance.answeredHere(callId)) return;
    final s = _calls.value;
    if (s.isSameCall(callId) &&
        (s.phase == CallPhase.accepted || s.phase == CallPhase.ongoing)) {
      return;
    }
    IncomingFlow.clearNativeRinging(callId);
    if (s.isSameCall(callId) && s.phase == CallPhase.ringing) {
      EndFlow.dismissRinging(callId, reason: CallEndReason.answeredElsewhere);
    } else {
      CallDedup.instance.markEnded(callId);
    }
  }

  /// RN `isMatchingCall`: the same id or documentId; or, while only the
  /// numeric id is known, a documentId-keyed push not older than the call.
  static bool isMatching(String? incomingId, [Map<String, dynamic>? data]) {
    if (incomingId == null || incomingId.isEmpty) return true;
    final s = _calls.value;
    if (s.isSameCall(incomingId)) return true;
    if (s.callDocumentId == null &&
        !_numeric(incomingId) &&
        _numeric(s.callId)) {
      final callAt = s.sentAt;
      final pushAt = data == null
          ? null
          : CallPayload.sentAt(
              CallPayload.read(data, const [
                'sentTime',
                'google.sent_time',
                'timestamp',
              ]),
            );
      return callAt == null || pushAt == null || !pushAt.isBefore(callAt);
    }
    return false;
  }

  static bool _numeric(String? id) =>
      id != null && RegExp(r'^\d+$').hasMatch(id);
}
