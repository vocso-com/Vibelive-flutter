import 'dart:async';
import 'dart:convert';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/api/callscreen/pending_decline_queue.dart';
import 'package:vibelive/app/callscreen/helper/call_alerts.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_device.dart';
import 'package:vibelive/app/callscreen/helper/call_identity.dart';
import 'package:vibelive/app/callscreen/helper/call_navigator.dart';
import 'package:vibelive/app/callscreen/helper/call_permissions.dart';
import 'package:vibelive/app/callscreen/helper/call_platform.dart';
import 'package:vibelive/app/callscreen/helper/call_ringtone.dart';
import 'package:vibelive/app/callscreen/helper/call_runtime.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/app/callscreen/helper/call_signals.dart';
import 'package:vibelive/app/callscreen/helper/call_timers.dart';
import 'package:vibelive/app/callscreen/helper/engine/call_engine.dart';
import 'package:vibelive/app/callscreen/helper/engine/headless_join.dart';
import 'package:vibelive/app/callscreen/helper/flows/end_flow.dart';
import 'package:vibelive/app/callscreen/helper/flows/incoming_flow.dart';
import 'package:vibelive/app/callscreen/helper/flows/native_flow.dart';
import 'package:vibelive/app/callscreen/helper/flows/instant_call_flow.dart';
import 'package:vibelive/app/callscreen/helper/flows/outgoing_flow.dart';
import 'package:vibelive/app/callscreen/helper/state/call_dedup.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';

/// A recorded request.
typedef Sent = ({String method, String path, Object? body, RequestOptions o});

/// Fake backend: replies per `METHOD /path`, records every request.
class FakeBackend implements HttpClientAdapter {
  final sent = <Sent>[];

  /// `'POST /api/initiateCall'` → reply body (or a function of the
  /// request). Unlisted paths answer `{data: []}`.
  final replies = <String, Object? Function(RequestOptions o)>{};

  /// `'POST /api/call/Callend'` → HTTP status (with `{message}` body).
  final failures = <String, (int, String)>{};

  /// Non-2xx replies with a full body (Strapi's `error.details.code`).
  final refusals = <String, (int, Object)>{};

  /// Wallet cash for the max-duration read.
  double cash = 1000;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    final key = '${o.method} ${o.path}';
    sent.add((method: o.method, path: o.path, body: o.data, o: o));
    final failure = failures[key];
    if (failure != null) {
      return ResponseBody.fromString(
        jsonEncode({
          'data': null,
          'error': {'status': failure.$1, 'message': failure.$2},
        }),
        failure.$1,
        headers: _json,
      );
    }
    final refusal = refusals[key];
    if (refusal != null) {
      return ResponseBody.fromString(
        jsonEncode(refusal.$2),
        refusal.$1,
        headers: _json,
      );
    }
    final reply = replies[key];
    final body =
        reply?.call(o) ??
        (o.path == '/api/wallets'
            ? {
                'data': [
                  {'id': 1, 'wallet_type': 'CASH_WALLET', 'balance': cash},
                ],
              }
            : {'data': <Object>[]});
    return ResponseBody.fromString(jsonEncode(body), 200, headers: _json);
  }

  static final _json = {
    Headers.contentTypeHeader: ['application/json'],
  };

  List<Sent> to(String method, String path) =>
      sent.where((r) => r.method == method && r.path == path).toList();

  Map<String, dynamic> lastBody(String method, String path) =>
      Map<String, dynamic>.from(to(method, path).last.body! as Map);

  @override
  void close({bool force = false}) {}
}

class FakeRingtone implements RingtoneBackend {
  final log = <String>[];

  @override
  Future<void> start(CallTone tone) async => log.add('start:${tone.name}');

  @override
  Future<void> stop() async => log.add('stop');
}

class FakePermissions implements CallPermissionBackend {
  CallAccess check_ = CallAccess.granted;
  CallAccess afterRequest = CallAccess.granted;
  int requests = 0;
  int settings = 0;

  @override
  Future<CallAccess> check({required bool video}) async => check_;

  @override
  Future<CallAccess> request({required bool video}) async {
    requests++;
    return afterRequest;
  }

  @override
  Future<void> openSettings() async => settings++;
}

class FakePlatform extends CallPlatform {
  final log = <String>[];

  /// What [isDeviceLocked] answers.
  bool locked = false;

  /// Call ids [isNativeRinging] answers true for.
  final nativeRinging = <String>{};

  @override
  Future<void> endNativeCall(String callId) async => log.add('end:$callId');

  @override
  Future<void> markConnected(CallSession call) async =>
      log.add('connected:${call.callId}');

  @override
  Future<void> answerNativeRinging(String callId) async =>
      log.add('answer:$callId');

  @override
  Future<bool> isDeviceLocked() async => locked;

  @override
  Future<void> markOutgoing(CallSession call) async =>
      log.add('outgoing:${call.callId}');

  @override
  Future<bool> isNativeRinging(String callId) async =>
      nativeRinging.contains(callId);

  @override
  Future<void> setShowOverLockScreen(bool on) async => log.add('lock:$on');

  @override
  Future<void> setSpeaker(bool on) async => log.add('speaker:$on');

  @override
  Future<void> minimizeApp() async => log.add('minimize');
}

/// An Agora engine that records calls and lets a test fire callbacks.
class FakeRtcEngine implements RtcEngine {
  final calls = <String>[];
  final joins = <ChannelMediaOptions>[];
  final tokens = <String>[];
  final updates = <ChannelMediaOptions>[];
  RtcEngineEventHandler? handler;
  String? appId;

  /// Codes `joinChannel` throws, in order (then succeeds).
  final joinErrors = <int>[];
  ConnectionStateType state = ConnectionStateType.connectionStateDisconnected;

  /// Codes `updateChannelMediaOptions` throws, in order.
  final updateErrors = <int>[];

  @override
  Future<void> initialize(RtcEngineContext context) async {
    appId = context.appId;
    calls.add('initialize');
  }

  @override
  Future<void> joinChannel({
    required String token,
    required String channelId,
    required int uid,
    required ChannelMediaOptions options,
  }) async {
    calls.add('joinChannel:$channelId:$uid');
    joins.add(options);
    tokens.add(token);
    if (joinErrors.isNotEmpty) {
      throw AgoraRtcException(code: joinErrors.removeAt(0));
    }
  }

  @override
  Future<void> updateChannelMediaOptions(ChannelMediaOptions options) async {
    calls.add('updateChannelMediaOptions');
    if (updateErrors.isNotEmpty) {
      throw AgoraRtcException(code: updateErrors.removeAt(0));
    }
    updates.add(options);
  }

  @override
  Future<ConnectionStateType> getConnectionState() async => state;

  @override
  void registerEventHandler(RtcEngineEventHandler eventHandler) =>
      handler = eventHandler;

  @override
  void unregisterEventHandler(RtcEngineEventHandler eventHandler) {}

  @override
  Future<void> muteRemoteVideoStream({
    required int uid,
    required bool mute,
  }) async => calls.add('muteRemoteVideoStream:$uid:$mute');

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(_name(invocation.memberName));
    return Future<void>.value();
  }

  static String _name(Symbol s) {
    final raw = s.toString(); // Symbol("name")
    return raw.substring(8, raw.length - 2);
  }

  /// Fires `onJoinChannelSuccess`.
  void joined(String channel, int uid) => handler?.onJoinChannelSuccess?.call(
    RtcConnection(channelId: channel, localUid: uid),
    0,
  );

  void remoteJoined(int uid) =>
      handler?.onUserJoined?.call(const RtcConnection(), uid, 0);

  void remoteLeft(int uid, UserOfflineReasonType reason) =>
      handler?.onUserOffline?.call(const RtcConnection(), uid, reason);

  /// Fires `onConnectionStateChanged`.
  void connection(
    ConnectionStateType state,
    ConnectionChangedReasonType reason,
  ) => handler?.onConnectionStateChanged?.call(
    const RtcConnection(),
    state,
    reason,
  );
}

/// A token whose embedded app id is [appId] (32 chars).
String agoraToken({String appId = 'abcdefabcdefabcdefabcdefabcdef12'}) =>
    '007$appId${'x' * 40}';

/// Everything the call logic touches, faked; call from `setUpAll`.
Future<void> initCallTestEnv() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  FlutterSecureStorage.setMockInitialValues({});
  PackageInfo.setMockInitialValues(
    appName: 'Vibe Live',
    packageName: 'com.angrymamba.vibelive',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  await AppPrefs.init();
  ApiClient.dio.interceptors.removeWhere((i) => i is PrettyDioLogger);
  CallRuntime.wakelock = (_) async {};
  CallIdentity.debugDeviceId = 'ios-device-1';
  CallDevice.debugIsIOS = false;
  CallDevice.debugForeground = false;
  CallEngine.configAppId = () async => null;
  CallRuntime.ensureStarted();
}

/// Fresh fakes and a signed-in user ([userId] numeric, `u<id>` docId).
Future<
  ({
    FakeBackend backend,
    FakeRingtone ringtone,
    FakePermissions permissions,
    FakePlatform platform,
    FakeRtcEngine Function() engine,
  })
>
resetCallTestEnv({int userId = 9, String role = 'Client'}) async {
  resetCallState();
  queryCache.clear();
  await AppPrefs.remove(PendingDeclineQueue.storageKey);
  final backend = FakeBackend();
  ApiClient.dio.httpClientAdapter = backend;
  final ringtone = FakeRingtone();
  CallRingtone.backend = ringtone;
  final permissions = FakePermissions();
  CallPermissions.backend = permissions;
  final platform = FakePlatform();
  CallPlatform.instance = platform;
  FakeRtcEngine? last;
  CallEngine.factory = () => last = FakeRtcEngine();
  CallAlerts.debugLog = [];
  await SessionStore.instance.signIn(
    user: {
      'id': userId,
      'documentId': 'u$userId',
      'name': 'Asha',
      'role': role,
    },
    accessToken: 'access',
  );
  return (
    backend: backend,
    ringtone: ringtone,
    permissions: permissions,
    platform: platform,
    engine: () => last!,
  );
}

/// Every singleton back to idle, every timer cancelled.
void resetCallState() {
  CallTimers.instance.cancelAll();
  CallController.instance.reset();
  CallDedup.instance.reset();
  EndFlow.debugReset();
  IncomingFlow.debugReset();
  OutgoingFlow.debugReset();
  InstantCallFlow.debugReset();
  NativeFlow.debugReset();
  CallNavigator.debugReset();
  CallEngine.instance.debugReset();
  HeadlessJoin.instance.debugReset();
  CallRingtone.debugReset();
  CallRuntime.debugReset();
  CallSignals.clearCallbackRequest();
  CallDevice.debugForeground = false;
  CallDevice.debugIsIOS = false;
}

/// Alerts / toasts the call logic showed (`title|message` keys).
List<String> alertLog() => CallAlerts.debugLog ?? const [];

/// Lets queued microtasks and short timers run.
///
/// This waits on the CLOCK, not on the thing you care about, so a value picked
/// to be "comfortably enough" is a bet that loses on a loaded machine — which
/// is how `logic_billing_test.dart` came to fail roughly one full-suite run in
/// five while passing every time it was run alone. Fine for letting a microtask
/// drain; use [settleUntil] whenever you are waiting for an OUTCOME.
Future<void> settle([int ms = 20]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// Waits until [done] is true, then returns immediately.
///
/// Fast when the work is fast and patient when the machine is busy, which is
/// the opposite of a fixed delay on both counts. The timeout is deliberately
/// far longer than any of these paths need: it exists to fail a genuinely
/// broken test, not to be the thing a passing test waits for.
Future<void> settleUntil(
  bool Function() done, {
  int timeoutMs = 4000,
  int pollMs = 5,
  String? reason,
}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError(
        'settleUntil timed out after ${timeoutMs}ms'
        '${reason == null ? '' : ': $reason'}',
      );
    }
    await Future<void>.delayed(Duration(milliseconds: pollMs));
  }
}

/// A backend ring payload (P1), every value a string.
Map<String, dynamic> ringPush({
  String callId = '42',
  String callerId = '5',
  String receiverId = '9',
  String type = 'voiceCall',
  DateTime? sentAt,
  Map<String, dynamic> extra = const {},
}) => {
  'type': type,
  'timestamp': '${(sentAt ?? DateTime.now()).millisecondsSinceEpoch}',
  'callerName': 'Ravi+Kumar',
  'channelName': 'call_${callerId}_${receiverId}_1',
  'roomId': 'call_${callerId}_${receiverId}_1',
  'category': '',
  'categoryName': 'Breakup',
  'token': agoraToken(),
  'callerId': callerId,
  'receiverId': receiverId,
  'callId': callId,
  'receiverDocID': 'Null',
  'calleridDocID': 'caller-doc',
  'ProfilePic': '/uploads/ravi.png',
  'role': 'Client',
  'is_company_account': 'false',
  ...extra,
};
