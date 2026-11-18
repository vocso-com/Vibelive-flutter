import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/config/env.dart';
import '../../../../core/utils/log.dart';
import '../../../api/splashscreen/splash_queries.dart';
import '../call_controller.dart';
import '../call_device.dart';
import '../call_payload.dart';
import '../call_platform.dart';
import '../call_session.dart';
import '../state/call_constants.dart';
import 'engine_events.dart';

part 'engine_handler.dart';
part 'engine_lifecycle.dart';
part 'engine_video.dart';

/// One join request (RN `gLastJoinArgs`).
@immutable
class _JoinArgs {
  const _JoinArgs({
    required this.channel,
    required this.token,
    required this.uid,
    required this.video,
    required this.headless,
  });

  final String channel;
  final String token;
  final int uid;

  /// A video call: the camera is wanted once the app can use it.
  final bool video;

  /// Joined from the background (CallKit answer): audio only so far.
  final bool headless;

  bool get publishCamera => video && !headless;

  _JoinArgs copyWith({bool? video, bool? headless}) => _JoinArgs(
    channel: channel,
    token: token,
    uid: uid,
    video: video ?? this.video,
    headless: headless ?? this.headless,
  );
}

/// The one Agora engine (RN `useAgora` module state), shared by the
/// incoming preview, the call screen and the headless background join.
///
/// CONTRACT for the call UI: read [media] and [rtc] / [channelId] to build
/// video views; call the toggles. Everything else (init, join, leave,
/// headless join, video publish, repair) belongs to the call logic.
class CallEngine {
  CallEngine._();
  static final instance = CallEngine._();

  /// Seam: tests hand in a fake engine (no platform channel, no FFI).
  @visibleForTesting
  static RtcEngine Function() factory = createAgoraRtcEngine;

  /// Last app-id source (RN: app-config `Agora_App_Id`).
  @visibleForTesting
  static Future<String?> Function() configAppId = _appConfigId;

  final _media = ValueNotifier<CallMedia>(CallMedia.initial);
  final _events = StreamController<CallEngineEvent>.broadcast();

  /// Live media state. Video views must only be built while
  /// `media.engineReady` (never true in widget tests).
  ValueListenable<CallMedia> get media => _media;

  /// For the call logic (timers, connect, hang-up on remote quit).
  Stream<CallEngineEvent> get events => _events.stream;

  RtcEngine? _engine;
  Future<RtcEngine?>? _creating;
  String? _initializedAppId;
  String? _resolvedAppId;
  DateTime? _initAt;
  RtcEngineEventHandler? _handler;
  bool _audioReady = false;

  // RN module flags (§4.1). Capturing ≠ publishing (mem #14 sub-bug).
  bool _hasVideo = false;
  bool _publishingCamera = false;
  bool _pendingCameraPublish = false;
  bool _localVideoFailed = false;
  bool _headlessActive = false;
  bool _joining = false;
  bool _minus17Recovered = false;
  bool _flipping = false;
  ({String channel, int uid})? _joined;
  _JoinArgs? _args;

  /// Where the call's sound goes (Agora `AudioRoute`: -1 default, 0 / 2 a
  /// wired headset, 1 the earpiece, 3 the speaker, 5+ Bluetooth and the
  /// like); null until Agora says.
  int? _audioRoute;

  /// Bumped by every NEW join and by [leave]: an in-flight join whose
  /// generation is no longer current gives up. Merging flags into the
  /// running join (a repeated accept, [ensureVideoIfNeeded]) replaces
  /// [_args] but keeps the generation, so it never cancels the join (a
  /// cold-start accept arrives 2-3 times; each used to abort the previous
  /// join and the call sat on "Connecting..." forever).
  int _joinGen = 0;
  String? _fingerprint;
  final _remoteUids = <int>{};
  Timer? _releaseTimer;

  /// The engine for `AgoraVideoView` (null until initialised).
  RtcEngine? get rtc => _engine;

  /// Channel this device joined (remote views need it).
  String? get channelId => _joined?.channel ?? _args?.channel;

  bool get isJoined => _joined != null;

  /// The sound goes to a headset or Bluetooth device (not the phone's own
  /// earpiece or speaker): moving it to the speaker would take it away.
  bool get audioOnAccessory {
    final r = _audioRoute;
    return r != null && r != -1 && r != 1 && r != 3 && r != 4;
  }

  /// The other side is in the channel now.
  bool get hasRemote => _remoteUids.isNotEmpty;

  /// A background (CallKit) join owns the engine: never release it (E-43).
  bool get headlessActive => _headlessActive;

  // ── join / leave ──────────────────────────────────────────────────────

  /// Joins [channel] as [uid] (RN `join` + `performJoin`). Idempotent per
  /// call: an equal join (same channel, uid, token tail) only makes sure
  /// the camera is published (E-6). [headless]: answered from CallKit in
  /// the background, audio only until [ensureVideoIfNeeded]. False when it
  /// could not start (a [EngineJoinFailed] follows for real failures).
  Future<bool> join({
    required String channel,
    required String token,
    required int uid,
    required bool video,
    bool headless = false,
  }) async {
    if (channel.isEmpty || token.isEmpty || uid <= 0) return false;
    _cancelRelease();
    final repaired = CallPayload.repairToken(token);
    final current = _args;
    final joined = _joined;
    if ((joined != null && joined.channel == channel && joined.uid == uid) ||
        _fingerprint == '$channel|$uid|${_tail(repaired)}') {
      if (current != null) {
        _args = current.copyWith(
          video: current.video || video,
          headless: current.headless && headless,
        );
      }
      Log.d(
        'CallEngine',
        'join $channel uid=$uid: already ${joined != null ? 'joined' : 'joining'}',
      );
      if (!headless) await ensureVideoIfNeeded();
      return true;
    }
    if (_joining && current?.channel == channel) return true;
    // A new call: forget the previous fingerprint and camera (E-54).
    if (current == null || current.channel != channel) {
      _fingerprint = null;
      _hasVideo = false;
      _setMedia((m) => CallMedia(engineReady: m.engineReady));
    }
    final args = _JoinArgs(
      channel: channel,
      token: repaired,
      uid: uid,
      video: video,
      headless: headless,
    );
    _fingerprint = '$channel|$uid|${_tail(repaired)}';
    _minus17Recovered = false;
    _args = args;
    final gen = ++_joinGen;
    Log.w(
      'CallEngine',
      'join $channel uid=$uid video=$video headless=$headless',
    );
    // Before any await: a release scheduled meanwhile must see it (E-43).
    if (headless) _headlessActive = true;
    final eng = await _ensureEngine(token: repaired);
    if (gen != _joinGen) return _superseded(channel);
    if (eng == null) return _joinFailed('engine_unavailable');
    // Video module on before the join; the camera itself waits (CE).
    final want = _args ?? args;
    if (want.video && want.headless) await _quiet(eng.enableVideo);
    final other = _joined;
    if (other != null && other.channel != channel) {
      await _quiet(eng.leaveChannel);
      _joined = null;
      if (CallDevice.isIOS) await Future.delayed(CallTimings.iosRejoinSettle);
    }
    await _quiet(eng.enableAudio);
    await _quiet(() => eng.enableLocalAudio(true));
    await _quiet(() => eng.muteLocalAudioStream(_media.value.muted));
    if (gen != _joinGen) return _superseded(channel);
    return _performJoin(eng, gen);
  }

  /// A newer join or a leave took over while this one awaited.
  bool _superseded(String channel) {
    Log.w('CallEngine', 'join $channel superseded (newer join or leave)');
    return false;
  }

  /// Joins with the CURRENT [_args] (a merged repeat may have asked for the
  /// camera meanwhile), unless generation [gen] is no longer current.
  Future<bool> _performJoin(RtcEngine eng, int gen) async {
    final first = _args;
    if (first == null || gen != _joinGen) return false;
    if (first.publishCamera) await _startCapture(eng);
    final initAt = _initAt;
    if (initAt != null &&
        DateTime.now().difference(initAt) < CallTimings.coldBootWindow) {
      await Future.delayed(CallTimings.coldBootSettle); // E-55
    }
    final args = _args;
    if (args == null || gen != _joinGen) return _superseded(first.channel);
    if (args.publishCamera && !_hasVideo) await _startCapture(eng);
    if (gen != _joinGen) return _superseded(args.channel);
    _joining = true;
    _publishingCamera = args.publishCamera;
    try {
      await eng.joinChannel(
        token: args.token,
        channelId: args.channel,
        uid: args.uid,
        options: ChannelMediaOptions(
          // COMMUNICATION: the backend's Agora webhook backstop only
          // understands this profile (E-89).
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          publishCameraTrack: args.publishCamera,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
        ),
      );
      return true;
    } on AgoraRtcException catch (e) {
      if (e.code.abs() == 17 && !_minus17Recovered) {
        return _recoverAlreadyJoining(eng, gen);
      }
      return _joinFailed('join_failed_code_${e.code}');
    } catch (e) {
      return _joinFailed('join_failed_$e');
    }
  }

  /// -17 "already joining" (E-53): connecting / connected / reconnecting is
  /// a success; otherwise leave, settle, rejoin once.
  Future<bool> _recoverAlreadyJoining(RtcEngine eng, int gen) async {
    ConnectionStateType? state;
    try {
      state = await eng.getConnectionState();
    } catch (_) {}
    if (state == ConnectionStateType.connectionStateConnecting ||
        state == ConnectionStateType.connectionStateConnected ||
        state == ConnectionStateType.connectionStateReconnecting) {
      return true;
    }
    _minus17Recovered = true;
    await _quiet(eng.leaveChannel);
    await Future.delayed(CallTimings.minus17Settle);
    if (gen != _joinGen) return false;
    return _performJoin(eng, gen);
  }

  bool _joinFailed(String reason) {
    Log.w('CallEngine', 'join failed: $reason');
    _joining = false;
    _fingerprint = null;
    _publishingCamera = false;
    _emit(EngineJoinFailed(reason));
    return false;
  }

  /// Leaves the channel; the engine stays for [scheduleRelease]. Clears the
  /// headless flag (RN `leave` + `leaveAgoraHeadless`).
  Future<void> leave() async {
    _joinGen++;
    _headlessActive = false;
    _joining = false;
    _joined = null;
    _args = null;
    _fingerprint = null;
    _minus17Recovered = false;
    _publishingCamera = false;
    _pendingCameraPublish = false;
    _remoteUids.clear();
    final eng = _engine;
    _setMedia((m) => CallMedia(engineReady: m.engineReady));
    if (eng == null) return;
    if (_hasVideo) {
      _hasVideo = false;
      await _quiet(eng.stopPreview);
    }
    await _quiet(eng.leaveChannel);
  }

  /// Releases the engine [CallTimings.engineReleaseGrace] after the call is
  /// over. Never while a call is live or a headless join holds it.
  void scheduleRelease() {
    _releaseTimer?.cancel();
    _releaseTimer = Timer(CallTimings.engineReleaseGrace, () {
      _releaseTimer = null;
      if (_headlessActive ||
          _args != null ||
          CallController.instance.value.phase.isActive) {
        return;
      }
      unawaited(_teardown());
    });
  }

  void _cancelRelease() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
  }

  /// Incoming video call on screen: the engine and the local camera, no
  /// audio (the ringtone owns the audio session until Accept, CE).
  Future<void> startIncomingPreview() async {
    final call = CallController.instance.value;
    if (!call.isVideo || !CallDevice.isForeground) return;
    try {
      final eng = await _ensureEngine(token: call.token, audio: false);
      if (eng != null &&
          CallController.instance.value.isSameCall(call.callId)) {
        await _startCapture(eng);
      }
    } catch (e) {
      Log.w('CallEngine', 'preview: $e');
    }
  }

  /// The app id embedded in an Agora token, or null.
  static String? appIdFromToken(String token) {
    final t = CallPayload.repairToken(token);
    if (t.length < 35 || !RegExp(r'^00[67]').hasMatch(t)) return null;
    return t.substring(3, 35);
  }

  static Future<String?> _appConfigId() async {
    final id = (await ensureAppConfig()).agoraAppId;
    return id.isEmpty ? null : id;
  }

  static String _tail(String token) =>
      token.length <= 12 ? token : token.substring(token.length - 12);

  // ── toggles (call UI) ─────────────────────────────────────────────────

  /// Mic on/off (RN `enableLocalAudio(!m)` + `muteLocalAudioStream(m)`).
  Future<void> toggleMute() async {
    final muted = !_media.value.muted;
    final eng = _engine;
    if (eng != null) {
      await _quiet(() => eng.enableLocalAudio(!muted));
      await _quiet(() => eng.muteLocalAudioStream(muted));
    }
    _setMedia((m) => m.copyWith(muted: muted));
  }

  /// Speaker / earpiece (earpiece by default for audio AND video).
  Future<void> toggleSpeaker() async {
    final on = !_media.value.speakerOn;
    final eng = _engine;
    if (eng != null) {
      if (CallDevice.isIOS) {
        // iOS: the default route is a pre-join setting only (CE).
        await _quiet(
          () => _joined != null
              ? eng.setEnableSpeakerphone(on)
              : eng.setDefaultAudioRouteToSpeakerphone(on),
        );
      } else {
        await _quiet(() => eng.setDefaultAudioRouteToSpeakerphone(on));
        if (_joined != null) await _quiet(() => eng.setEnableSpeakerphone(on));
      }
    }
    unawaited(CallPlatform.instance.setSpeaker(on));
    _setMedia((m) => m.copyWith(speakerOn: on));
  }

  /// The speaker [on] or off; nothing when it already is.
  Future<void> setSpeaker(bool on) async {
    if (_media.value.speakerOn != on) await toggleSpeaker();
  }

  /// Own camera on/off (video calls).
  Future<void> toggleVideo() async {
    final off = !_media.value.localVideoOff;
    final eng = _engine;
    if (eng != null) {
      await _quiet(() => eng.muteLocalVideoStream(off));
      await _quiet(() => eng.enableLocalVideo(!off));
    }
    _setMedia((m) => m.copyWith(localVideoOff: off));
  }

  /// Front / back camera; bumps `localViewKey` after 100 ms.
  Future<void> flipCamera() async {
    final eng = _engine;
    if (eng == null || _flipping || !(_args?.video ?? false)) return;
    _flipping = true;
    try {
      await eng.switchCamera();
      _setMedia((m) => m.copyWith(frontCamera: !m.frontCamera));
      Timer(CallTimings.cameraFlipRemount, () {
        _setMedia((m) => m.copyWith(localViewKey: m.localViewKey + 1));
      });
    } catch (e) {
      Log.w('CallEngine', 'switchCamera: $e');
    } finally {
      _flipping = false;
    }
  }

  // ── plumbing ──────────────────────────────────────────────────────────

  /// Publishes only real changes.
  void _setMedia(CallMedia Function(CallMedia current) change) {
    final next = change(_media.value);
    if (next != _media.value) _media.value = next;
  }

  void _emit(CallEngineEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  static Future<void> _quiet(Future<void> Function() call) async {
    try {
      await call();
    } catch (e) {
      Log.w('CallEngine', '$e');
    }
  }

  /// Tests only.
  @visibleForTesting
  void debugSetMedia(CallMedia media) => _media.value = media;

  /// Where the sound goes, as Agora would say (see [audioOnAccessory]).
  @visibleForTesting
  void debugSetAudioRoute(int? route) => _audioRoute = route;

  /// Tests only: forget every engine and flag (no platform calls).
  @visibleForTesting
  void debugReset() {
    _cancelRelease();
    _engine = null;
    _handler = null;
    _creating = null;
    _initializedAppId = null;
    _resolvedAppId = null;
    _initAt = null;
    _audioReady = false;
    _hasVideo = false;
    _publishingCamera = false;
    _pendingCameraPublish = false;
    _localVideoFailed = false;
    _headlessActive = false;
    _joining = false;
    _minus17Recovered = false;
    _joined = null;
    _args = null;
    _fingerprint = null;
    _remoteUids.clear();
    _media.value = CallMedia.initial;
  }
}
