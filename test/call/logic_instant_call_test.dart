import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/callscreen/helper/state/call_constants.dart';
import 'package:vibelive/app/authscreen/helper/deep_links.dart';
import 'package:vibelive/app/api/instant_call/instant_call_api.dart';
import 'package:vibelive/app/api/instant_call/instant_call_models.dart';
import 'package:vibelive/app/callscreen/helper/call_actions.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_payload.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/app/callscreen/helper/call_signals.dart';
import 'package:vibelive/app/callscreen/helper/flows/end_flow.dart';
import 'package:vibelive/app/callscreen/helper/flows/instant_call_flow.dart';
import 'package:vibelive/app/callscreen/helper/flows/outgoing_flow.dart';
import 'package:vibelive/app/callscreen/helper/native/headless_call_end.dart';
import 'package:vibelive/app/callscreen/helper/native/native_call_marks.dart';
import 'package:vibelive/app/callscreen/helper/push/push_envelope.dart';
import 'package:vibelive/app/api/free_call/free_call_models.dart';
import 'package:vibelive/app/callscreen/helper/call_billing.dart';

import 'logic_fakes.dart';

/// Talk Now (instant call), as the backend runs it: a ring is an
/// instant-call SESSION (its callId is the session id); a host's accept /
/// decline go to `/instant-call/*`, the accept creates the call record that
/// Callend bills, and an end for the ring may carry only the session id.
void main() {
  final calls = CallController.instance;
  late FakeBackend backend;
  late ({
    FakeBackend backend,
    FakeRingtone ringtone,
    FakePermissions permissions,
    FakePlatform platform,
    FakeRtcEngine Function() engine,
  })
  env;

  const hostAccept = '/api/instant-call/host-accept';
  const hostDecline = '/api/instant-call/host-decline';
  const cancel = '/api/instant-call/cancel';
  const callEnd = '/api/call/Callend';
  const updateCall = '/api/UpdateCall';
  const ack = '/api/call/receiver-ringing-ack';

  Map<String, dynamic> talkNowRing() => ringPush(
    callId: 'sess1',
    extra: const {'isInstantCall': 'true', 'instantCallSessionId': 'sess1'},
  );

  setUpAll(initCallTestEnv);
  setUp(() async {
    env = await resetCallTestEnv();
    backend = env.backend;
    backend.replies['POST $hostAccept'] = (_) => {
      'success': true,
      'callId': 901,
      'channelName': 'instant_5_1',
      'hostToken': 'tok',
    };
  });
  tearDown(resetCallState);

  group('the ring', () {
    test('a Talk Now ring says so; nothing to ack', () async {
      final p = CallPayload.parse(talkNowRing())!;
      expect(p.session.isInstantCall, isTrue);
      expect(p.session.instantCallSessionId, 'sess1');
      expect(p.session.backendCallId, isNull); // no call record yet

      await CallSignals.onInvite(talkNowRing(), foreground: false);
      await settle(200);
      expect(backend.to('POST', ack), isEmpty);
    });

    test('an end with only the session id stops the ring', () async {
      await CallSignals.onInvite(talkNowRing(), foreground: false);
      expect(calls.value.phase, CallPhase.ringing);
      // The backend's "stop ringing" (caller cancelled, another host took
      // it, the search moved on).
      final end = PushEnvelope.fromMap(const {
        'type': 'CALL_ENDED',
        'instantCallSessionId': 'sess1',
        'dismissNotification': 'true',
      });
      expect(end.callId, 'sess1');
      await CallSignals.onEnded(end.callId!);
      expect(calls.value.phase.isActive, isFalse);
    });
  });

  group('host', () {
    test(
      'accept: host-accept, never UpdateCall; Callend bills the record',
      () async {
        await CallSignals.onInvite(talkNowRing(), foreground: false);
        await CallActions.accept();
        await settle(500);
        expect(backend.lastBody('POST', hostAccept), {'sessionId': 'sess1'});
        expect(backend.to('POST', updateCall), isEmpty);
        expect(calls.value.serverCallId, '901');
        expect(await NativeCallMarks.serverCallId('sess1'), '901');

        // Pushes about the call record match this call.
        expect(calls.value.isSameCall('901'), isTrue);

        calls.setConnected(
          at: DateTime.now().subtract(const Duration(seconds: 30)),
        );
        await CallActions.hangup();
        await settle();
        final body = backend.lastBody('POST', callEnd);
        expect(body['callId'], '901');
        expect(body['status'], 'completed');
        // The host never cancels the caller's search.
        expect(backend.to('POST', cancel), isEmpty);
      },
    );

    test(
      'a transient host-accept failure is retried, then the call bills',
      () async {
        var failures = 1;
        backend.replies['POST $hostAccept'] = (_) {
          if (failures-- > 0) throw StateError('boom');
          return {
            'success': true,
            'callId': 901,
            'channelName': 'instant_5_1',
            'hostToken': 'tok',
          };
        };
        await CallSignals.onInvite(talkNowRing(), foreground: false);
        await CallActions.accept();
        await settle(100);
        expect(backend.to('POST', hostAccept), hasLength(1));
        expect(calls.value.serverCallId, isNull);
        await settle(2300); // first retry after 2 s
        expect(backend.to('POST', hostAccept), hasLength(2));
        expect(calls.value.serverCallId, '901');
      },
    );

    test(
      'accept refused because this host is busy: leave, with that word',
      () async {
        backend.refusals['POST $hostAccept'] = (
          409,
          {
            'data': null,
            'error': {
              'status': 409,
              'name': 'ConflictError',
              'message': 'You are already on a call.',
              'details': {'code': 'HOST_BUSY'},
            },
          },
        );
        await CallSignals.onInvite(talkNowRing(), foreground: false);
        await CallActions.accept();
        await settle(100);
        expect(calls.value.phase.isActive, isFalse);
        expect(alertLog().last, contains('host_busy'));
      },
    );

    test('accept refused (taken, too late): leave, with a word why', () async {
      backend.failures['POST $hostAccept'] = (
        400,
        'You are not currently being rung for this session.',
      );
      await CallSignals.onInvite(talkNowRing(), foreground: false);
      await CallActions.accept();
      await settle(500);
      expect(calls.value.phase.isActive, isFalse);
      expect(alertLog(), contains('toast|${InstantCallErrorKeys.taken}'));
      expect(backend.to('POST', updateCall), isEmpty);
      expect(backend.to('POST', callEnd), isEmpty);
    });

    test(
      'decline: host-decline (the next host rings now), no Callend',
      () async {
        await CallSignals.onInvite(talkNowRing(), foreground: false);
        await CallActions.decline();
        await settle();
        expect(backend.lastBody('POST', hostDecline), {'sessionId': 'sess1'});
        expect(backend.to('POST', callEnd), isEmpty);
      },
    );

    test('hung up before the accept reply: asks again, then bills', () async {
      calls.receive(
        const CallSession(
          callId: 'sess1',
          callerId: '5',
          receiverId: '9',
          isInstantCall: true,
          instantCallSessionId: 'sess1',
        ),
      );
      calls
        ..setAccepted()
        ..setConnected(
          at: DateTime.now().subtract(const Duration(seconds: 10)),
        );
      await CallActions.hangup();
      await settle(100);
      expect(backend.to('POST', hostAccept), hasLength(1));
      expect(backend.lastBody('POST', callEnd)['callId'], '901');
    });

    test('background notification Decline / Hang up', () async {
      await HeadlessCallEnd.decline('sess1', talkNowRing());
      expect(backend.lastBody('POST', hostDecline), {'sessionId': 'sess1'});

      await NativeCallMarks.saveServerCallId('sess2', '902');
      await NativeCallMarks.markConnected(
        'sess2',
        DateTime.now().subtract(const Duration(seconds: 20)),
      );
      await HeadlessCallEnd.hangUp('sess2', {
        'callId': 'sess2',
        '__role': 'receiver',
        'receiverId': '9',
        'isInstantCall': 'true',
        'instantCallSessionId': 'sess2',
      });
      expect(backend.lastBody('POST', callEnd)['callId'], '902');
    });
  });

  group('caller', () {
    CallSession searching() => const CallSession(
      callId: 'sess1',
      callDocumentId: 'sess1',
      callerId: '9',
      isInstantCall: true,
      instantCallSessionId: 'sess1',
    );

    test(
      'connected: keeps the call record; a late "failed" is ignored',
      () async {
        calls.startOutgoing(searching());
        CallSignals.onInstantCallConnected(const {
          'instantCallSessionId': 'sess1',
          'callId': '901',
          'hostUserId': '70',
          'hostName': 'Meera',
        });
        expect(calls.value.serverCallId, '901');
        expect(calls.value.receiverId, '70');

        calls.setConnected();
        CallSignals.onInstantCallFailed(const {
          'instantCallSessionId': 'sess1',
          'reason': 'timeout',
        });
        expect(calls.value.phase, CallPhase.ongoing);

        await CallActions.hangup();
        await settle();
        expect(backend.lastBody('POST', callEnd)['callId'], '901');
      },
    );

    test(
      'the host joins the channel: the caller CONFIRMS the connection '
      '(/UpdateCall on the record), never host-accept; the call goes on',
      () async {
        backend.replies['POST /api/instant-call/initiate'] = (_) => {
          'success': true,
          'sessionId': 'sess1',
          'channelName': 'instant_9_1',
          'callerToken': agoraToken(),
          'callerRate': 7,
          'currentHost': {'userId': 70, 'name': 'Meera', 'profilePic': null},
        };
        backend.replies['GET /api/instant-call/status/sess1'] = (_) => {
          'sessionId': 'sess1',
          'status': 'connected',
          'connectedCall': {'id': 901, 'status': 'pending'},
          'connectedHost': {'userId': 70, 'name': 'Meera'},
        };
        backend.replies['POST $updateCall'] = (_) => {'ok': true};

        expect(await InstantCallFlow.place(), isTrue);
        // The first host is known from the reply's own field names.
        expect(calls.value.remote.name, 'Meera');
        expect(calls.value.remote.id, '70');
        await settle(100); // the (unawaited) Agora join
        final engine = env.engine();
        engine.joined('instant_9_1', 9);
        await settle();
        // No INSTANT_CALL_CONNECTED push yet; the host is in the channel.
        engine.remoteJoined(70);
        await settle(700); // the 500 ms connect delay
        expect(calls.value.phase, CallPhase.ongoing);
        await settle(200);
        expect(backend.to('POST', hostAccept), isEmpty);
        expect(calls.value.serverCallId, '901');
        final confirm = backend.lastBody('POST', updateCall);
        expect(confirm['callId'], '901');
        expect(confirm['callerId'], '9');
        expect(confirm['receiverId'], '70');
        expect(backend.to('POST', updateCall), hasLength(1));

        // A "failed" that arrives now (an escalation push in flight) is
        // ignored: the call is live.
        CallSignals.onInstantCallFailed(const {
          'instantCallSessionId': 'sess1',
          'reason': 'timeout',
        });
        expect(calls.value.phase, CallPhase.ongoing);

        // The late push changes nothing (confirmed once).
        CallSignals.onInstantCallConnected(const {
          'instantCallSessionId': 'sess1',
          'callId': '901',
          'hostUserId': '70',
        });
        await settle(100);
        expect(backend.to('POST', updateCall), hasLength(1));

        await CallActions.hangup();
        await settle(100);
        expect(backend.lastBody('POST', callEnd)['callId'], '901');
        // Connected: nothing to cancel on the server.
        expect(backend.to('POST', cancel), isEmpty);
      },
    );

    test(
      'the connected push lands first: confirmed with its record id',
      () async {
        backend.replies['POST $updateCall'] = (_) => {'ok': true};
        calls.startOutgoing(searching());
        CallSignals.onInstantCallConnected(const {
          'instantCallSessionId': 'sess1',
          'callId': '901',
          'hostUserId': '70',
          'hostName': 'Meera',
        });
        await settle(50);
        // Not in the channel yet: nothing confirmed.
        expect(backend.to('POST', updateCall), isEmpty);
        calls.setConnected();
        await InstantCallFlow.confirmConnected(calls.value);
        expect(backend.lastBody('POST', updateCall)['callId'], '901');
        expect(backend.to('GET', '/api/instant-call/status/sess1'), isEmpty);
      },
    );

    test('the initiate reply is read with the server\'s field names', () {
      final r = InitiatedInstantCall.tryParse(const {
        'success': true,
        'sessionId': 'sess1',
        'callerToken': 'tok',
        'channelName': 'instant_9_1',
        'currentHost': {'userId': 70, 'name': 'Meera', 'profilePic': '/p.jpg'},
        'parallelHosts': [
          {'userId': 70, 'name': 'Meera', 'profilePic': '/p.jpg'},
          {'userId': 71, 'name': 'Asha', 'profilePic': null},
        ],
      })!;
      expect(r.currentHost?.userId, '70');
      expect(r.currentHost?.name, 'Meera');
      expect(r.currentHost?.profilePic, '/p.jpg');
      expect(r.parallelHosts?.map((h) => h.userId), ['70', '71']);
      expect(
        InstantConnectedCall.tryParse(const {
          'connectedCall': {'id': 901, 'status': 'pending'},
          'connectedHost': {'userId': 70, 'name': 'Meera'},
        })?.hostUserId,
        '70',
      );
      expect(
        InstantConnectedCall.tryParse(const {'connectedCall': null}),
        isNull,
      );
    });

    test('after a Talk Now call: Home, no host profile re-opened', () async {
      DeepLinks.instance.takeOpenUser();
      calls.startOutgoing(
        searching().copyWith(
          remote: const CallPeer(id: '70', documentId: 'host70', name: 'Meera'),
        ),
      );
      calls.setConnected();
      await CallActions.hangup();
      await settle(50);
      EndFlow.exitToHome(callId: 'sess1');
      await settle(CallTimings.reopenProfileDelay.inMilliseconds + 300);
      expect(DeepLinks.instance.takeOpenUser(), isNull);
    });

    test('hang up while searching: cancel the search, no Callend', () async {
      calls.startOutgoing(searching());
      await CallActions.hangup();
      await settle(100);
      expect(backend.lastBody('POST', cancel), {'sessionId': 'sess1'});
      expect(backend.to('POST', callEnd), isEmpty);
    });

    test('the search failed: the call ends', () async {
      calls.startOutgoing(searching());
      CallSignals.onInstantCallFailed(const {
        'instantCallSessionId': 'sess1',
        'reason': 'pool_exhausted',
      });
      expect(calls.value.phase.isActive, isFalse);
    });
  });

  test('a Talk Now ring rings as long as the server asks (cascade)', () {
    expect(
      CallPayload.ringLength(const {'ringSeconds': '110'}),
      const Duration(seconds: 110),
    );
    // Bounded: never under 10 s, never over 3 minutes.
    expect(
      CallPayload.ringLength(const {'ringSeconds': '3'}),
      const Duration(seconds: 10),
    );
    expect(
      CallPayload.ringLength(const {'ringSeconds': 900}),
      const Duration(minutes: 3),
    );
    // Not said (a direct call, an older backend): the usual length applies.
    expect(CallPayload.ringLength(const {}), isNull);
    expect(CallPayload.ringLength(const {'ringSeconds': 'null'}), isNull);
    expect(CallPayload.ringLength(const {'ringSeconds': '-4'}), isNull);
  });

  group('a call to a host that rolls over', () {
    const config = '/api/instant-call/config';
    const initiate = '/api/instant-call/initiate';
    const initiateCall = '/api/initiateCall';
    const meera = OutgoingRequest(
      receiverId: '70',
      receiverDocId: 'u70',
      video: false,
      name: 'Meera',
      avatarUrl: '/meera.jpg',
      ratePerMin: 12,
    );

    void rolloverOn({
      bool on = true,
      String types = 'voice_only',
      bool talkNow = true,
    }) {
      backend.replies['GET $config'] = (_) => {
        'enabled': talkNow,
        'allowedCallTypes': types,
        'directRollover': on,
        'maxRingSeconds': 120,
      };
    }

    test('on: the chosen host rings first, through Talk Now', () async {
      rolloverOn();
      backend.replies['POST $initiate'] = (_) => {
        'success': true,
        'sessionId': 'sess9',
        'channelName': 'instant_9_9',
        'callerToken': agoraToken(),
        'callerRate': 12,
        'currentHost': {'userId': 70, 'name': 'Meera'},
        'firstHost': {'userId': 70, 'name': 'Meera', 'callerRate': 12},
      };
      expect(await OutgoingFlow.place(meera), isTrue);
      await settle(100);
      expect(backend.lastBody('POST', initiate)['firstHostId'], 70);
      expect(backend.to('POST', initiateCall), isEmpty);
      final live = calls.value;
      expect(live.isInstantCall, isTrue);
      expect(live.remote.name, 'Meera');
      expect(live.remote.documentId, 'u70');

      // Another host answers at the Talk Now rate: the cap follows it.
      CallSignals.onInstantCallConnected(const {
        'instantCallSessionId': 'sess9',
        'callId': '905',
        'hostUserId': '71',
        'hostName': 'Asha',
        'callerRate': '10',
      });
      expect(calls.value.serverCallId, '905');
      expect(calls.value.remote.name, 'Asha');
    });

    test('a free search: the answer says whether the call is free', () async {
      rolloverOn();
      backend.replies['POST $initiate'] = (_) => {
        'success': true,
        'sessionId': 'sess9',
        'channelName': 'instant_9_9',
        'callerToken': agoraToken(),
        'callerRate': 12,
        'currentHost': {'userId': 70, 'name': 'Meera'},
        'firstHost': {'userId': 70, 'name': 'Meera', 'callerRate': 12},
        'freeCall': {'minutes': 2, 'continuePaid': false},
      };
      expect(await OutgoingFlow.place(meera), isTrue);
      await settle(100);
      expect(
        CallBilling.freeFor(calls.value.callId),
        const FreeCallTerms(minutes: 2, continuePaid: false),
      );

      CallSignals.onInstantCallConnected(const {
        'instantCallSessionId': 'sess9',
        'callId': '905',
        'hostUserId': '70',
        'callerRate': '12',
        'freeMinutes': '2',
        'freeContinuePaid': 'false',
      });
      expect(
        CallBilling.freeFor(calls.value.callId),
        const FreeCallTerms(minutes: 2, continuePaid: false),
      );

      // An answer without free minutes (the free call went elsewhere): paid.
      CallSignals.onInstantCallConnected(const {
        'instantCallSessionId': 'sess9',
        'callId': '905',
        'hostUserId': '70',
        'callerRate': '12',
      });
      expect(CallBilling.freeFor(calls.value.callId), isNull);
    });

    test('off (or the type not taken): a plain call', () async {
      rolloverOn(on: false);
      await OutgoingFlow.place(meera);
      await settle(100);
      expect(backend.to('POST', initiate), isEmpty);
      expect(backend.to('POST', initiateCall), hasLength(1));
      resetCallState();

      rolloverOn(types: 'voice_only');
      await OutgoingFlow.place(
        const OutgoingRequest(receiverId: '70', video: true, name: 'Meera'),
      );
      await settle(100);
      expect(backend.to('POST', initiate), isEmpty);
      expect(backend.to('POST', initiateCall), hasLength(2));
    });

    test(
      'rollover is its own switch: on with the Talk Now button off',
      () async {
        rolloverOn(talkNow: false);
        backend.replies['POST $initiate'] = (_) => {
          'success': true,
          'sessionId': 'sess9',
          'channelName': 'instant_9_9',
          'callerToken': agoraToken(),
          'currentHost': {'userId': 70, 'name': 'Meera'},
          'firstHost': {'userId': 70, 'name': 'Meera', 'callerRate': 12},
        };
        expect(await OutgoingFlow.place(meera), isTrue);
        await settle(100);
        expect(backend.lastBody('POST', initiate)['firstHostId'], 70);
        expect(backend.to('POST', initiateCall), isEmpty);
      },
    );

    test('the server refuses to roll it over: still a plain call', () async {
      for (final code in ['COMPANY_ONLY', 'ROLLOVER_OFF', 'DISABLED']) {
        rolloverOn();
        backend.refusals['POST $initiate'] = (
          code == 'COMPANY_ONLY' ? 403 : 400,
          {
            'data': null,
            'error': {
              'status': code == 'COMPANY_ONLY' ? 403 : 400,
              'message': 'Talk Now is not yet available.',
              'details': {'code': code},
            },
          },
        );
        final before = backend.to('POST', initiateCall).length;
        await OutgoingFlow.place(meera);
        await settle(100);
        expect(
          backend.to('POST', initiateCall),
          hasLength(before + 1),
          reason: code,
        );
        expect(alertLog().join(' '), isNot(contains('instant_call')));
        resetCallState();
      }
    });

    test('the host is on a call and nobody else is free: "busy"', () async {
      rolloverOn();
      backend.replies['POST $initiate'] = (_) => {
        'success': false,
        'code': 'USER_BUSY',
        'message': 'Receiver is currently on another call',
      };
      expect(await OutgoingFlow.place(meera), isFalse);
      await settle(100);
      expect(calls.value.phase.isActive, isFalse);
      expect(alertLog().join(' '), contains('user_busy'));
    });

    test('rollsOver needs the rollover switch and the type', () {
      const on = InstantCallConfig(
        enabled: true,
        directRollover: true,
        allowedCallTypes: 'both',
      );
      expect(on.rollsOver(video: true), isTrue);
      expect(
        const InstantCallConfig(
          enabled: true,
          directRollover: true,
        ).rollsOver(video: true),
        isFalse,
        reason: 'voice only by default',
      );
      expect(
        const InstantCallConfig(
          enabled: false,
          directRollover: true,
        ).rollsOver(video: false),
        isTrue,
        reason: 'switched apart from the Talk Now button',
      );
      expect(
        const InstantCallConfig(enabled: true).rollsOver(video: false),
        isFalse,
      );
      expect(
        InstantCallConfig.fromJson(const {
          'enabled': true,
          'directRollover': true,
        }).rollsOver(video: false),
        isTrue,
      );
    });
  });

  test("the search reply carries the caller's Talk Now rate", () {
    final r = InitiatedInstantCall.tryParse(const {
      'success': true,
      'sessionId': 'sess1',
      'callerToken': 'tok',
      'channelName': 'instant_9_1',
      'callerRate': 12,
    })!;
    expect(r.callerRate, 12);
  });

  test('Callend id: the record for Talk Now, the call otherwise', () {
    const talk = CallSession(callId: 'sess1', isInstantCall: true);
    expect(talk.backendCallId, isNull);
    expect(talk.copyWith(serverCallId: '901').backendCallId, '901');
    expect(const CallSession(callId: '42').backendCallId, '42');
    final input = EndFlow.endInput(
      talk.copyWith(serverCallId: '901', role: CallRole.receiver),
      connected: true,
      seconds: 5,
    );
    expect(input.callId, '901');
  });
}
