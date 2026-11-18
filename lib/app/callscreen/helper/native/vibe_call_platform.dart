import 'dart:async';
import 'dart:io' show Platform;

import '../../../../core/utils/log.dart';
import '../call_controller.dart';
import '../call_platform.dart';
import '../call_session.dart';
import '../call_signals.dart';
import '../engine/call_engine.dart';
import 'call_notification_sweep.dart';
import 'call_permission_primer.dart';
import 'callkit_params.dart';
import 'callkit_service.dart';
import 'native_call_bridge.dart';
import 'native_call_marks.dart';

/// The real [CallPlatform]: iOS through `VibeCallBridge` (native owns every
/// CallKit report), Android through `flutter_callkit_incoming` + the
/// `MainActivity` call channel. Installed at boot by `CallFlow`. Every method
/// never throws.
class VibeCallPlatform extends CallPlatform {
  const VibeCallPlatform();

  static const _tag = 'VibeCallPlatform';

  /// Android: calls whose ongoing notification is already up.
  static final _ongoing = <String>{};

  @override
  Future<void> endNativeCall(String callId) async {
    if (callId.isEmpty) return;
    try {
      if (Platform.isIOS) {
        // reportCall(endedAt:): clears the Dynamic Island, fires no
        // CXEndCallAction, so nothing echoes back (mem #10 / #12).
        await NativeCallBridge.endCall(callId);
        return;
      }
      if (!Platform.isAndroid) return;
      _ongoing.remove(callId);
      // Before endCall: the plugin echoes DECLINE / ENDED for it, and that
      // echo must never become a Callend (it would bill a call another
      // device answered).
      await NativeCallMarks.markAppEnded(callId);
      await CallKitService.end(callId);
      await NativeCallMarks.clearConnected(callId);
      unawaited(NativeCallBridge.releaseProximityLock());
      unawaited(CallNotificationSweep.clearEnded());
    } catch (e) {
      Log.w(_tag, 'endNativeCall $callId: $e');
    }
  }

  @override
  Future<void> markOutgoing(CallSession call) async {
    final callId = call.callId;
    if (callId == null || callId.isEmpty || !Platform.isAndroid) return;
    try {
      // Now, while the app is in front: Android 12+ refuses to start the
      // foreground service from the background (and 14 its mic type), so a
      // caller who leaves the app while it rings would lose the mic.
      await _startOngoing(call, callId);
      // RN: the screen goes dark at the ear from the first ring.
      _proximity(call);
      // With the call permissions (the mic gate just passed): headsets.
      unawaited(CallPermissionPrimer.ensureBluetooth());
    } catch (e) {
      Log.w(_tag, 'markOutgoing $callId: $e');
    }
  }

  @override
  Future<void> markConnected(CallSession call) async {
    final callId = call.callId;
    if (callId == null || callId.isEmpty) return;
    try {
      // iOS: the receiver's CallKit call is already answered and the caller
      // has none (Dart never starts CallKit calls on iOS, decision 15).
      if (!Platform.isAndroid) return;
      await NativeCallMarks.markConnected(
        callId,
        call.connectedAt ?? DateTime.now(),
      );
      _proximity(call);
      // Started by markOutgoing (caller) or answerNativeRinging (receiver)
      // already, else now. Either way the Telecom connection goes active.
      await _startOngoing(call, callId);
      await _activate(callId);
    } catch (e) {
      Log.w(_tag, 'markConnected $callId: $e');
    }
  }

  /// The ongoing notification + foreground service, once per call.
  Future<void> _startOngoing(CallSession call, String callId) async {
    if (!_ongoing.add(callId)) return;
    await CallKitService.startOngoing(
      callId,
      // A Talk Now search names nobody: the host rung first is not the call.
      name: call.isSearch
          ? CallKitParamsBuilder.appName
          : call.remote.name ?? CallKitParamsBuilder.appName,
      video: call.isVideo,
      extra: _extraOf(call),
    );
  }

  /// Android (A4): the plugin's Telecom connection ACTIVE, then the
  /// speaker choice again (Telecom resets the route when it activates).
  Future<void> _activate(String callId) async {
    await CallKitService.setConnected(callId);
    final media = CallEngine.instance.media.value;
    await setSpeaker(media.speakerOn);
  }

  @override
  Future<void> answerNativeRinging(String callId) async {
    if (callId.isEmpty) return;
    try {
      if (Platform.isIOS) {
        // Native requests CXAnswerCallAction for its live UUID: CallKit, the
        // audio session and native's `/UpdateCall` follow (I6). Never the
        // plugin's setCallConnected: it overwrites its stored call data.
        if (!await NativeCallBridge.answerLive(callId)) {
          // Nothing unanswered is live on CallKit any more, so no native
          // `/UpdateCall` follows: the logic sends it (the I1 retry path).
          unawaited(CallSignals.onNativeUpdateFailed(callId));
        }
        return;
      }
      if (!Platform.isAndroid) return;
      final native = (await CallKitService.activeCalls())
          .where((c) => c.callId == callId && !c.isCompliance)
          .firstOrNull;
      if (native == null) return; // in-app ring only: nothing to answer
      if (_ongoing.add(callId)) {
        final call = CallController.instance.value;
        await CallKitService.startOngoing(
          callId,
          name: call.isSameCall(callId) && call.remote.name != null
              ? call.remote.name!
              : CallKitParamsBuilder.callerName(native.extra),
          video: call.isSameCall(callId)
              ? call.isVideo
              : CallKitParamsBuilder.isVideo(native.extra),
          extra: {...native.extra, '__role': 'receiver'},
        );
      }
      await _activate(callId);
    } catch (e) {
      Log.w(_tag, 'answerNativeRinging $callId: $e');
    }
  }

  @override
  Future<bool> isNativeRinging(String callId) async {
    if (callId.isEmpty) return false;
    try {
      if (Platform.isIOS) {
        final live = await NativeCallBridge.liveCall();
        return live != null &&
            '${live['callId'] ?? ''}' == callId &&
            live['answered'] != true;
      }
      if (!Platform.isAndroid) return false;
      // A ring whose sound the app took down is not ringing any more.
      if (CallKitService.wasHidden(callId)) return false;
      return (await CallKitService.activeCalls()).any(
        (c) => c.callId == callId && !c.isAccepted && !c.isCompliance,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isDeviceLocked() async {
    try {
      return await NativeCallBridge.isDeviceLocked();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setShowOverLockScreen(bool on) async {
    if (!Platform.isAndroid) return;
    await NativeCallBridge.setLockedActivity(on);
  }

  @override
  Future<void> setSpeaker(bool on) async {
    // iOS: Agora owns the route (CallKit never touches the session).
    if (!Platform.isAndroid) return;
    final callId = CallController.instance.value.callId;
    if (callId == null) return;
    // While the plugin's self-managed Telecom connection is live, Telecom
    // overrides Agora's speakerphone (E41).
    await NativeCallBridge.setAudioRoute(
      on ? 'speaker' : 'earpiece',
      callId: callId,
    );
    // On speaker the phone is away from the face: keep the screen on.
    _proximity(CallController.instance.value, speakerOn: on);
  }

  /// RN CallingScreen: the proximity lock (screen off at the ear) while an
  /// audio call rings or runs on the earpiece; released on speaker, for
  /// video, and when the call ends ([endNativeCall]). Android only.
  void _proximity(CallSession call, {bool? speakerOn}) {
    final speaker = speakerOn ?? CallEngine.instance.media.value.speakerOn;
    final engage = !call.isVideo && call.phase.isActive && !speaker;
    unawaited(
      engage
          ? NativeCallBridge.acquireProximityLock()
          : NativeCallBridge.releaseProximityLock(),
    );
  }

  @override
  Future<void> minimizeApp() async {
    if (!Platform.isAndroid) return;
    await NativeCallBridge.minimizeApp();
  }

  /// What a background Hang up on the ongoing notification needs to send
  /// `/call/Callend` with no UI isolate.
  static Map<String, dynamic> _extraOf(CallSession call) => {
    'callId': call.callId,
    '__role': call.isCaller ? 'caller' : 'receiver',
    'callerId': ?call.callerId,
    'receiverId': ?call.receiverId,
    'calleridDocID': ?call.callerDocId,
    'type': call.isVideo ? 'videoCall' : 'voiceCall',
    if (!call.isSearch) 'callerName': ?call.remote.name,
    if (!call.isSearch) 'ProfilePic': ?call.remote.avatarUrl,
    // Talk Now: a background Hang up ends a session / bills its record.
    if (call.isInstantCall) 'isInstantCall': 'true',
    'instantCallSessionId': ?call.instantCallSessionId,
  };
}
