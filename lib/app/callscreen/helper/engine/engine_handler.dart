part of 'call_engine.dart';

/// Agora callbacks → engine flags, [CallMedia] and [CallEngineEvent]s
/// (RN `registerSharedHandler`). `onError` only logs (ce-frontend parity:
/// no retry loop, never recreate on errors).
extension _EngineHandler on CallEngine {
  RtcEngineEventHandler _buildHandler() => RtcEngineEventHandler(
    onJoinChannelSuccess: (connection, _) => _onJoined(connection),
    onUserJoined: (_, uid, _) => _onRemoteJoined(uid),
    onUserOffline: (_, uid, reason) => _onRemoteLeft(uid, reason),
    onLeaveChannel: (_, _) => _onLeft(),
    onConnectionStateChanged: (_, state, reason) =>
        _onConnection(state, reason),
    onTokenPrivilegeWillExpire: (_, _) => _emit(const EngineTokenExpiring()),
    onRequestToken: (_) => _emit(const EngineTokenExpiring()),
    onLocalVideoStateChanged: (_, state, _) => _onLocalVideo(state),
    onRemoteVideoStateChanged: (_, uid, state, _, _) =>
        _onRemoteVideo(uid, state),
    onAudioRoutingChanged: (routing) => _audioRoute = routing,
    onError: (code, message) => Log.w('CallEngine', 'error $code $message'),
  );

  void _onJoined(RtcConnection connection) {
    final args = _args;
    _joining = false;
    _minus17Recovered = false;
    final channel = connection.channelId ?? args?.channel ?? '';
    final uid = connection.localUid ?? args?.uid ?? 0;
    _joined = (channel: channel, uid: uid);
    final eng = _engine;
    if (eng != null) {
      // Joining re-establishes the audio session: re-apply the route (CE).
      final speaker = _media.value.speakerOn;
      unawaited(CallEngine._quiet(() => eng.setEnableSpeakerphone(speaker)));
      // A publish asked for before the join returned -8 (E-40): now.
      if (_pendingCameraPublish) unawaited(_applyCameraPublish());
    }
    _setMedia((m) => m.copyWith(joined: true));
    _emit(EngineJoined(channel, uid));
  }

  void _onRemoteJoined(int uid) {
    _remoteUids.add(uid);
    final eng = _engine;
    if (eng != null) {
      unawaited(
        CallEngine._quiet(
          () => eng.muteRemoteAudioStream(uid: uid, mute: false),
        ),
      );
      if (_hasVideo) {
        unawaited(
          CallEngine._quiet(
            () => eng.muteRemoteVideoStream(uid: uid, mute: false),
          ),
        );
      }
      // Self-heal: camera on but never published in this join.
      final args = _args;
      if (_hasVideo &&
          !_publishingCamera &&
          _joined != null &&
          !_joining &&
          args != null &&
          args.publishCamera) {
        unawaited(_applyCameraPublish());
      }
    }
    _setMedia(
      (m) => m.remoteUid != null && _remoteUids.contains(m.remoteUid)
          ? m
          : m.copyWith(remoteUid: uid, remoteVideoOff: false),
    );
    _emit(EngineRemoteJoined(uid));
  }

  void _onRemoteLeft(int uid, UserOfflineReasonType reason) {
    _remoteUids.remove(uid);
    _setMedia((m) {
      if (m.remoteUid != uid) return m;
      final next = _remoteUids.isEmpty ? null : _remoteUids.first;
      return next == null
          ? m.copyWith(clearRemoteUid: true, remoteVideoOff: false)
          : m.copyWith(remoteUid: next);
    });
    _emit(
      EngineRemoteLeft(
        uid,
        quit: reason == UserOfflineReasonType.userOfflineQuit,
      ),
    );
  }

  /// A leave that a rejoin is replacing (-17, channel switch) must not
  /// wipe the new join's state.
  void _onLeft() {
    if (_joining) return;
    _joined = null;
    _publishingCamera = false;
    _pendingCameraPublish = false;
    _localVideoFailed = false;
    _remoteUids.clear();
    _setMedia((m) => m.copyWith(joined: false, clearRemoteUid: true));
  }

  void _onConnection(
    ConnectionStateType state,
    ConnectionChangedReasonType reason,
  ) {
    switch (state) {
      case ConnectionStateType.connectionStateFailed:
        if (_joined == null && _joining && _args != null) {
          _joinFailed('conn_failed_reason_${reason.name}');
        } else if (_joined != null) {
          // Kicked out after the join: the same uid joined from another
          // device (both of the receiver's phones answered), banned, or the
          // token was revoked. Agora will not reconnect (A7).
          _emit(EngineConnectionLost(reason.name));
        }
      case ConnectionStateType.connectionStateReconnecting:
        _emit(const EngineReconnecting(true));
      case ConnectionStateType.connectionStateConnected:
        _emit(const EngineReconnecting(false));
      default:
        break;
    }
  }

  /// A locked iOS device refuses the camera while `startPreview` still
  /// returns 0: remember it for the unlock repair (E-48).
  void _onLocalVideo(LocalVideoStreamState state) {
    switch (state) {
      case LocalVideoStreamState.localVideoStreamStateFailed:
        _localVideoFailed = true;
      case LocalVideoStreamState.localVideoStreamStateCapturing ||
          LocalVideoStreamState.localVideoStreamStateEncoding:
        _localVideoFailed = false;
      default:
        break;
    }
  }

  void _onRemoteVideo(int uid, RemoteVideoState state) {
    if (uid != _media.value.remoteUid) return;
    switch (state) {
      case RemoteVideoState.remoteVideoStateStopped:
        _setMedia((m) => m.copyWith(remoteVideoOff: true));
      case RemoteVideoState.remoteVideoStateStarting ||
          RemoteVideoState.remoteVideoStateDecoding:
        // Back on: remount the remote view (RN render keys).
        _setMedia(
          (m) => m.remoteVideoOff
              ? m.copyWith(
                  remoteVideoOff: false,
                  remoteViewKey: m.remoteViewKey + 1,
                )
              : m,
        );
      default:
        break;
    }
  }
}
