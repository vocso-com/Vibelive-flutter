import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/analytics/events/call_ui_events.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/log.dart';
import '../../../api/callscreen/call_api.dart';
import '../../../api/callscreen/call_errors.dart';
import '../../../api/callscreen/call_models.dart';
import '../../../api/callscreen/call_queries.dart';
import '../../../api/listingflow/listing_models.dart';
import '../call_actions.dart';
import '../call_alerts.dart';
import '../call_analytics.dart';
import '../call_billing.dart';
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
import '../state/call_constants.dart';
import 'end_flow.dart';
import 'instant_call_flow.dart';
import '../../../api/instant_call/instant_call_models.dart';
import '../../../api/instant_call/instant_call_api.dart';

/// Who is being called and how (host card, callback sheet or redial).
@immutable
class OutgoingRequest {
  const OutgoingRequest({
    required this.receiverId,
    required this.video,
    this.receiverDocId,
    this.expertDocId,
    this.name,
    this.avatarUrl,
    this.isCompany = false,
    this.categoryId,
    this.ratePerMin,
    this.source = 'host_profile',
  });

  /// Profile path: RN sent the fallback category for every host card call.
  factory OutgoingRequest.fromHost(HostCard host, {required bool video}) =>
      OutgoingRequest(
        receiverId: host.receiverId?.toString(),
        video: video,
        receiverDocId: host.userDocumentId,
        expertDocId: host.expertProfileDocumentId,
        name: host.name,
        avatarUrl: host.images.firstOrNull ?? host.cardImage,
        categoryId: CallWire.profileCategoryId,
        ratePerMin: video ? host.vPrice : host.aPrice,
        source: 'host_profile',
      );

  /// Callback sheet (`categoryId: null`) or history redial (the old call's
  /// category).
  factory OutgoingRequest.fromTarget(
    CallTarget t, {
    required bool video,
    String source = 'callback',
  }) => OutgoingRequest(
    receiverId: t.receiverId,
    video: video,
    receiverDocId: t.receiverDocId,
    name: t.name,
    avatarUrl: t.avatarUrl,
    isCompany: t.isCompany,
    categoryId: t.categoryId,
    ratePerMin: t.ratePerMin?.toDouble(),
    source: source,
  );

  /// Numeric public-user id of the person called (their Agora uid).
  final String? receiverId;
  final bool video;

  /// Their public-user documentId (Discover re-opens it after the call).
  final String? receiverDocId;

  /// Their expert-profile documentId, when known.
  final String? expertDocId;
  final String? name;
  final String? avatarUrl;
  final bool isCompany;
  final String? categoryId;

  /// Host rate for this call type (max duration); null = look it up.
  final double? ratePerMin;

  /// Analytics: where the call was started (`host_profile` | `callback`).
  final String source;

  /// Analytics: the host's expert-profile (else user) documentId.
  String? get hostId => expertDocId ?? receiverDocId;
}

/// Placing a call (RN DiscoveryScreen `handleInitiateCall`, CallbackModal
/// `initiateCallTo`, explore `callExpertFromLog`).
abstract final class OutgoingFlow {
  static bool _placing = false;

  /// Permission gate → `/initiateCall` → busy / invalid / failure alerts
  /// with RN copy → the call (joined while it rings) → `/call`. Never
  /// throws; false when no call started.
  static Future<bool> place(OutgoingRequest r) async {
    CallRuntime.ensureStarted();
    if (_placing) return false; // E-74 double tap
    // Admin "Direct calls roll over": this host rings first, then others
    // join the way Talk Now rings them; the first to answer takes it.
    final rollover = await _rolloverConfig(r);
    if (rollover != null) {
      return InstantCallFlow.place(
        video: r.video,
        maxRingSeconds: rollover.maxRingSeconds,
        firstHost: r,
      );
    }
    return placeDirect(r);
  }

  /// A plain call to [r]'s host, never rolled over: also what a call falls
  /// back to when the server refuses to roll it over.
  static Future<bool> placeDirect(OutgoingRequest r) async {
    CallRuntime.ensureStarted();
    if (_placing) return false;
    final now = CallController.instance.value;
    // One call at a time (decision 17).
    if (now.phase.isActive) {
      _failed(r, 'call_in_progress');
      return false;
    }
    // The previous call's summary is still up (its screen would be reused
    // for this call): finish it first. Its own exit is ignored from now on
    // (`EndFlow.exitToHome` checks the call id).
    if (now.phase == CallPhase.ended) CallController.instance.reset();
    _placing = true;
    CallUiEvents.attempt(
      video: r.video,
      source: r.source,
      hostId: r.hostId,
      ratePerMin: r.ratePerMin,
    );
    try {
      return await _place(r);
    } catch (e) {
      Log.w('OutgoingFlow', 'place: $e');
      _failed(r, 'exception', Analytics.errorCode(e));
      return false;
    } finally {
      _placing = false;
    }
  }

  /// The Talk Now config when this call should roll over; null for a plain
  /// call (off, the type not taken, calling a company account, or no
  /// answer from the server). A company caller rolls over too (their calls
  /// are free either way).
  static Future<InstantCallConfig?> _rolloverConfig(OutgoingRequest r) async {
    if (r.isCompany) return null;
    if (r.receiverId == null || r.receiverId!.isEmpty) return null;
    try {
      final config = await InstantCallApi.fetchConfig();
      return config.rollsOver(video: r.video) ? config : null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _place(OutgoingRequest r) async {
    final callerId = CallIdentity.userId;
    final receiverId = r.receiverId;
    if (callerId == null || receiverId == null || receiverId.isEmpty) {
      _failed(r, 'missing_participants');
      await CallAlerts.show(
        title: CallFlowKeys.unableTitle,
        message: CallErrorKeys.missingParticipants,
      );
      return false;
    }
    if (!await CallPermissions.ensureForOutgoing(video: r.video)) {
      _failed(r, 'permission_denied');
      return false;
    }

    final InitiatedCall started;
    try {
      started = await CallRequests.initiateCall(
        InitiateCallInput(
          callerId: int.tryParse(callerId) ?? callerId,
          receiverId: int.tryParse(receiverId) ?? receiverId,
          type: r.video ? CallType.video : CallType.voice,
          role: CallIdentity.role,
          categoryId: r.categoryId,
        ),
      );
    } on ApiException catch (e) {
      _failed(r, failureReason(e), Analytics.errorCode(e));
      // Busy is an answer, not a call: never Callend it (E-82).
      await CallAlerts.error(
        e,
        title: e.isUserBusy ? CallFlowKeys.busyTitle : CallFlowKeys.failedTitle,
      );
      return false;
    }

    final responseDoc = started.receiverDocId;
    final call = CallSession(
      role: CallRole.caller,
      callId: started.callId,
      callDocumentId: started.callDocumentId,
      channelName: started.channelName,
      token: CallPayload.repairToken(started.callerToken),
      isVideo: r.video,
      remote: CallPeer(
        id: receiverId,
        documentId: r.receiverDocId,
        name: r.name,
        avatarUrl: r.avatarUrl,
        isCompany: r.isCompany,
      ),
      callerId: callerId,
      receiverId: receiverId,
      callerDocId: CallIdentity.userDocumentId,
      // `receiverDocId` is the expert-profile documentId ('Null' without).
      receiverDocId:
          (responseDoc == null || responseDoc.toLowerCase() == 'null')
          ? r.expertDocId
          : responseDoc,
      callerIsCompany: CallIdentity.isCompany,
      sentAt: DateTime.now(),
    );
    final rate = r.ratePerMin;
    if (rate != null) CallBilling.rememberRate(started.callId, rate);
    // A free call (docs/free_calls.md): its free minutes come before any cap.
    CallBilling.rememberFree(started.callId, started.freeCall);
    CallController.instance.startOutgoing(call);
    // Android: the ongoing-call service must start while the app is in
    // front (Android 12+ refuses it from the background).
    unawaited(_markOutgoing(CallController.instance.value));
    CallTimers.instance.arm(CallTimers.noAnswer, CallTimings.noAnswer, () {
      final now = CallController.instance.value;
      if (now.isSameCall(started.callId) && now.phase.isPreConnect) {
        // decision 7: a normal caller cancel
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
      Log.w('OutgoingFlow', 'markOutgoing: $e');
    }
  }

  static void _failed(OutgoingRequest r, String reason, [String? error]) =>
      CallUiEvents.initiateFailed(
        reason: reason,
        video: r.video,
        source: r.source,
        hostId: r.hostId,
        error: error,
      );

  /// Analytics reason of a refused `/initiateCall` (instant calls too).
  static String failureReason(ApiException e) {
    if (e.isUserBusy) return 'host_busy';
    final m = '${e.serverMessage ?? ''} ${e.messageKey ?? ''}'.toLowerCase();
    if (m.contains('balance') ||
        m.contains('insufficient') ||
        m.contains('recharge')) {
      return 'insufficient_balance';
    }
    if (m.contains('offline') ||
        m.contains('unavailable') ||
        m.contains('not available')) {
      return 'host_offline';
    }
    if (m.contains('block')) return 'blocked';
    return switch (e.type) {
      ApiErrorType.network || ApiErrorType.timeout => 'network',
      _ => 'api_error',
    };
  }

  /// The caller is in the channel while it rings (RN C5); the ringback
  /// starts once Agora owns the audio session (CE: iOS ringback mixes into
  /// it).
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

  @visibleForTesting
  static void debugReset() => _placing = false;
}
