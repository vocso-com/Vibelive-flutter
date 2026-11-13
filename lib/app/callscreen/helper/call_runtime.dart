import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/query/query_client.dart';
import '../../../core/utils/log.dart';
import '../../api/callscreen/call_keys.dart';
import '../../api/free_call/free_call_queries.dart';
import '../../api/paymentscreen/payment_keys.dart';
import 'call_analytics.dart';
import 'call_billing.dart';
import 'call_controller.dart';
import 'call_navigator.dart';
import 'call_platform.dart';
import 'call_ringtone.dart';
import 'call_session.dart';
import 'call_timers.dart';
import 'engine/call_engine.dart';
import 'engine/engine_events.dart';
import 'engine/headless_join.dart';
import 'flows/end_flow.dart';
import 'flows/incoming_flow.dart';
import 'flows/instant_call_flow.dart';
import 'state/call_constants.dart';
import 'state/call_dedup.dart';
import 'state/call_store.dart';

/// Wiring between the one call, the engine and the device: reacts to every
/// phase change (wakelock, lock screen, ringtones, connect, teardown) and to
/// Agora events (connect, remote quit / drop, reconnect, token, join
/// failure). Started by the first `CallActions` / `CallSignals` entry.
abstract final class CallRuntime {
  static bool _started = false;
  static StreamSubscription<CallEngineEvent>? _engineSub;
  static CallSession _last = CallSession.idle;
  static String? _tornDown;
  static bool _awake = false;
  static CallSession _lastCall = CallSession.idle;

  /// The last call that ended (the post-call sheet outlives the session).
  static CallSession get lastCall => _lastCall;

  /// False in a background isolate (the Android FCM / CallKit handler
  /// isolates; native sets it at their entry). Timers that end a call
  /// locally (the 60 s incoming ring) only run in the UI isolate: an
  /// accept never reaches a background isolate, so its timer would end
  /// the answered call (A1).
  static bool isUiIsolate = true;

  static String? _ringingId;
  static Map<String, dynamic>? _ringingRaw;

  /// The raw invite payload (as the push / native layer delivered it) of
  /// the call ringing on this receiver right now; null when none rings.
  /// Native uses it to promote an in-app ring to CallKit (I4).
  static Map<String, dynamic>? get ringingPayload {
    final s = CallController.instance.value;
    final id = _ringingId;
    final raw = _ringingRaw;
    if (raw == null || id == null) return null;
    if (!s.isReceiver || s.phase != CallPhase.ringing || !s.isSameCall(id)) {
      return null;
    }
    return Map<String, dynamic>.of(raw);
  }

  /// Keeps [raw] as the invite of the ringing call [callId].
  static void rememberInvite(String callId, Map<String, dynamic> raw) {
    _ringingId = callId;
    _ringingRaw = Map<String, dynamic>.of(raw);
  }

  /// Seam: the screen-awake switch (tests: no platform channel).
  static Future<void> Function(bool on) wakelock = _setWakelock;

  static void ensureStarted() {
    if (_started) return;
    _started = true;
    _last = CallController.instance.value;
    CallController.instance.session.addListener(_onSession);
    _engineSub = CallEngine.instance.events.listen(_onEngine);
  }

  // ── phase changes ─────────────────────────────────────────────────────

  static void _onSession() {
    final s = CallController.instance.value;
    final prev = _last;
    _last = s;
    if (s.phase == prev.phase && s.callId == prev.callId) return;
    if (s.callId != null && s.callId != prev.callId) {
      EndFlow.newCall();
      _tornDown = null;
    }

    _keepAwake(s.phase.isActive);
    if (s.phase.isActive != prev.phase.isActive) {
      unawaited(CallPlatform.instance.setShowOverLockScreen(s.phase.isActive));
    }
    _tones(s);

    switch (s.phase) {
      case CallPhase.ongoing when prev.phase != CallPhase.ongoing:
        _onConnected(s);
      case CallPhase.ended:
        _onOver(s);
      case CallPhase.idle when prev.phase.isActive:
        _onOver(prev);
      default:
        break;
    }
  }

  /// The in-app ring only while this receiver's call rings; the ringback
  /// only while the caller waits.
  static void _tones(CallSession s) {
    if (CallRingtone.playing == CallTone.incoming &&
        !(s.isReceiver && s.phase == CallPhase.ringing)) {
      unawaited(CallRingtone.stop(CallTone.incoming));
    }
    if (CallRingtone.playing == CallTone.ringback &&
        !(s.isCaller && s.phase.isPreConnect)) {
      unawaited(CallRingtone.stop(CallTone.ringback));
    }
  }

  static void _onConnected(CallSession s) {
    final timers = CallTimers.instance;
    timers.cancel(CallTimers.noAnswer);
    timers.cancel(CallTimers.incomingRing);
    // Connected by the `CallTimer` push before the other side is in the
    // channel: it gets the remote-drop grace to show up.
    final callId = s.callId;
    if (callId != null && !CallEngine.instance.hasRemote) {
      timers.arm(CallTimers.remoteDrop, CallTimings.remoteDropGrace, () {
        final now = CallController.instance.value;
        if (now.isSameCall(callId) && !CallEngine.instance.hasRemote) {
          unawaited(EndFlow.hangup(reason: CallEndReason.peerNeverJoined));
        }
      });
    }
    unawaited(CallPlatform.instance.markConnected(s));
    unawaited(
      CallBilling.arm(
        s,
        onLimit: () =>
            unawaited(EndFlow.hangup(reason: CallEndReason.balanceExhausted)),
      ),
    );
  }

  /// Once per call, whatever ended it.
  static void _onOver(CallSession s) {
    final callId = s.callId;
    if (callId == null || _tornDown == callId) return;
    _tornDown = callId;
    _lastCall = s;
    if (_ringingId == callId) {
      _ringingId = null;
      _ringingRaw = null;
    }
    CallTimers.instance.cancelAll();
    CallDedup.instance.markEnded(callId);
    CallBilling.forget(callId);
    // Dynamic Island / notification cleared on every end (mem #10, E-35).
    EndFlow.endNativeOnce(callId);
    unawaited(_teardown(callId));
    queryCache.invalidateAll([
      ...CallKeys.afterCallChange(callId),
      ...PaymentKeys.walletData,
    ]);
    // The call may have used a free call (docs/free_calls.md).
    invalidateFreeCallStatus();
    // No call screen to show the summary (headless call, minimized): back
    // to idle right away. A call screen left in the background keeps it.
    if (s.phase == CallPhase.ended && !CallNavigator.onCallRoute) {
      scheduleMicrotask(() {
        if (CallController.instance.value.phase == CallPhase.ended) {
          CallController.instance.reset();
        }
      });
    }
  }

  static Future<void> _teardown(String callId) async {
    try {
      await CallRingtone.silence();
      HeadlessJoin.instance.cancel();
      await CallEngine.instance.leave();
      CallEngine.instance.scheduleRelease();
      await CallStore.clearPendingAccept(callId);
    } catch (e) {
      Log.w('CallRuntime', 'teardown: $e');
    }
  }

  static void _keepAwake(bool on) {
    if (on == _awake) return;
    _awake = on;
    unawaited(wakelock(on));
  }

  static Future<void> _setWakelock(bool on) async {
    try {
      on ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } catch (_) {}
  }

  // ── engine events ─────────────────────────────────────────────────────

  static void _onEngine(CallEngineEvent event) {
    final s = CallController.instance.value;
    final callId = s.callId;
    if (callId == null || !s.phase.isActive) return;
    final timers = CallTimers.instance;
    switch (event) {
      case EngineJoined():
        Log.w('CallFlow', 'Agora joined $callId (receiver=${s.isReceiver})');
        if (s.isReceiver) CallController.instance.setAccepted(); // R4
      case EngineRemoteJoined():
        Log.w('CallFlow', 'remote joined $callId: connected');
        timers.cancel(CallTimers.remoteDrop);
        if (s.isCaller) {
          unawaited(CallRingtone.stop(CallTone.ringback));
          CallController.instance.setRinging();
          if (s.phase != CallPhase.ongoing &&
              !timers.isArmed(CallTimers.callerConnect)) {
            // RN C8: connected 500 ms after the remote joined.
            timers.arm(
              CallTimers.callerConnect,
              CallTimings.callerConnectDelay,
              () {
                final now = CallController.instance.value;
                if (!now.isSameCall(callId) || !now.phase.isActive) return;
                CallController.instance.setConnected();
                // Talk Now: the caller confirms the connection (the record
                // goes ongoing, the bill starts); host-accept is the
                // host's call, never the caller's.
                unawaited(
                  now.isInstantCall
                      ? InstantCallFlow.confirmConnected(now)
                      : IncomingFlow.reportOngoing(now, answering: false),
                );
              },
            );
          }
        } else {
          CallController.instance.setConnected(); // R5
          unawaited(IncomingFlow.reportOngoing(s, answering: true));
        }
      case EngineRemoteLeft(quit: true):
        // RN C12 / R13
        unawaited(EndFlow.hangup(reason: CallEndReason.remoteHangup));
      case EngineRemoteLeft(quit: false):
        // Dropped: the call goes on for a grace period (decision 7).
        timers.arm(CallTimers.remoteDrop, CallTimings.remoteDropGrace, () {
          final now = CallController.instance.value;
          if (now.isSameCall(callId) && !CallEngine.instance.hasRemote) {
            unawaited(EndFlow.hangup(reason: CallEndReason.remoteDropped));
          }
        });
      case EngineReconnecting(reconnecting: true):
        timers.arm(CallTimers.reconnecting, CallTimings.reconnecting, () {
          if (CallController.instance.value.isSameCall(callId)) {
            unawaited(EndFlow.hangup(reason: CallEndReason.networkLost));
          }
        });
      case EngineReconnecting(reconnecting: false):
        timers.cancel(CallTimers.reconnecting);
      case EngineTokenExpiring():
        // E-88: no renew endpoint
        unawaited(EndFlow.hangup(reason: CallEndReason.tokenExpired));
      case EngineJoinFailed(:final reason):
        Log.w('CallFlow', 'Agora join failed $callId: $reason');
        unawaited(EndFlow.joinFailed());
      case EngineConnectionLost():
        // Same uid joined elsewhere (another device of ours answered too):
        // the other device owns the call and its Callend (A7).
        EndFlow.endLocally(callId, reason: CallEndReason.otherDevice);
    }
  }

  @visibleForTesting
  static void debugReset() {
    _tornDown = null;
    _ringingId = null;
    _ringingRaw = null;
    isUiIsolate = true;
    _awake = false;
    _last = CallController.instance.value;
  }

  @visibleForTesting
  static bool get started => _started && _engineSub != null;
}
