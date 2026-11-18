import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/callscreen/call_api.dart';
import 'package:vibelive/app/api/callscreen/call_models.dart';
import 'package:vibelive/app/api/free_call/free_call_models.dart';
import 'package:vibelive/app/callscreen/helper/call_actions.dart';
import 'package:vibelive/app/callscreen/helper/call_billing.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/app/callscreen/helper/call_signals.dart';
import 'package:vibelive/app/callscreen/helper/call_timers.dart';

import 'logic_fakes.dart';

const callEnd = '/api/call/Callend';

void main() {
  final calls = CallController.instance;
  late FakeBackend backend;

  setUpAll(initCallTestEnv);
  setUp(() async => backend = (await resetCallTestEnv()).backend);
  tearDown(resetCallState);

  group('MaxDuration (decision 8)', () {
    test('ends 20 s inside the last affordable minute (A3), warns 5 min '
        'before', () {
      final cap = MaxDuration.compute(cashBalance: 100, ratePerMin: 10)!;
      expect(cap.end, const Duration(seconds: 580)); // 10 min − 20 s
      expect(cap.warnAt, const Duration(seconds: 280));

      final odd = MaxDuration.compute(cashBalance: 59.9, ratePerMin: 20)!;
      expect(odd.end, const Duration(seconds: 100)); // 2 whole minutes
      expect(odd.warnAt, Duration.zero, reason: 'under 5 min: warn now');
    });

    test('no cap for company callers or free calls', () {
      expect(
        MaxDuration.compute(cashBalance: 5, ratePerMin: 10, company: true),
        isNull,
      );
      expect(MaxDuration.compute(cashBalance: 5, ratePerMin: 0), isNull);
      expect(MaxDuration.compute(cashBalance: 5, ratePerMin: -1), isNull);
    });

    test('nothing affordable ends at once; capped by the token hour', () {
      expect(
        MaxDuration.compute(cashBalance: 5, ratePerMin: 10)!.end,
        Duration.zero,
      );
      expect(
        MaxDuration.compute(cashBalance: -3, ratePerMin: 10)!.end,
        Duration.zero,
      );
      expect(
        MaxDuration.compute(cashBalance: 1e6, ratePerMin: 1)!.end,
        const Duration(seconds: 3580),
      );
    });

    test('armed for the caller at connect from the cash wallet', () async {
      backend.cash = 100;
      CallBilling.rememberRate('77', 10);
      calls.startOutgoing(
        const CallSession(callId: '77', callerId: '9', receiverId: '5'),
      );
      calls
        ..setAccepted()
        ..setConnected();
      await settle(50);
      expect(backend.to('GET', '/api/wallets'), hasLength(1));
      expect(CallTimers.instance.isArmed(CallTimers.maxDuration), isTrue);
      expect(CallTimers.instance.isArmed(CallTimers.lowBalance), isTrue);
    });

    test(
      'an unaffordable call is hung up with the low-balance toast',
      () async {
        backend.cash = 0;
        CallBilling.rememberRate('77', 10);
        calls.startOutgoing(
          const CallSession(callId: '77', callerId: '9', receiverId: '5'),
        );
        calls
          ..setAccepted()
          ..setConnected();
        // Waits for the outcome rather than for 80ms of wall clock. The fixed
        // delay here was a bet that the hang-up round trip finishes in time,
        // and on a loaded machine it did not — this test failed about one full
        // suite run in five and passed every time it ran alone.
        //
        // The call-end POST is what to wait for, not the toast: the toast is
        // shown first and the request lands after it, so waiting on the toast
        // still raced the assertion below.
        await settleUntil(
          () => backend.to('POST', callEnd).isNotEmpty,
          reason: 'the call was never ended against the backend',
        );
        expect(alertLog(), contains('toast|callflow:low_balance.ended'));
        expect(calls.value.phase.isActive, isFalse);
        expect(backend.lastBody('POST', callEnd)['status'], 'completed');
      },
    );

    test('the LOW_BALANCE_WARNING hint toasts once per live call', () async {
      CallSignals.onLowBalanceWarning('77');
      expect(alertLog(), isEmpty, reason: 'no call');
      calls.startOutgoing(
        const CallSession(callId: '77', callerId: '9', receiverId: '5'),
      );
      calls
        ..setAccepted()
        ..setConnected();
      CallSignals.onLowBalanceWarning('77');
      CallSignals.onLowBalanceWarning('77');
      expect(
        alertLog().where((l) => l == 'toast|callflow:low_balance.warning'),
        hasLength(1),
      );
    });

    test('never armed for the receiver', () async {
      calls.receive(
        const CallSession(callId: '42', callerId: '5', receiverId: '9'),
      );
      calls
        ..setAccepted()
        ..setConnected();
      await settle(50);
      expect(CallTimers.instance.isArmed(CallTimers.maxDuration), isFalse);
      expect(backend.to('GET', '/api/wallets'), isEmpty);
    });
  });

  group('"Add money" during a call', () {
    var buzzes = 0;
    setUp(() {
      buzzes = 0;
      CallBilling.buzz = () async => buzzes++;
    });

    Future<void> connect({String id = '77'}) async {
      calls.startOutgoing(
        CallSession(callId: id, callerId: '9', receiverId: '5'),
      );
      calls
        ..setAccepted()
        ..setConnected();
      await settle(50);
    }

    test(
      'time to spare: armed for 2 min before the end; nothing shows yet',
      () async {
        backend.cash = 100; // 10 min at 10/min: ends at 580 s
        CallBilling.rememberRate('77', 10);
        await connect();
        expect(CallTimers.instance.isArmed(CallTimers.topUpPrompt), isTrue);
        expect(CallBilling.topUpDue.value, isNull);
        final limit = CallBilling.limit.value!;
        expect(limit.callId, '77');
        expect(limit.extendable, isTrue);
        expect(limit.freeLimit, isFalse);
        final left = limit.leftAt(DateTime.now());
        expect(left.inSeconds, inInclusiveRange(575, 580));
        expect(buzzes, 0);
      },
    );

    test('2 min or less from the start: it comes up a moment after connect, '
        'with one buzz', () async {
      backend.cash = 25; // 2 whole minutes: ends at 100 s
      CallBilling.rememberRate('77', 10);
      await connect();
      expect(CallBilling.topUpDue.value, isNull, reason: 'not on second 0');
      await settleUntil(
        () => CallBilling.topUpDue.value == '77',
        timeoutMs: 5000,
      );
      expect(buzzes, 1);
    });

    test(
      'money added: the end moves, the prompt goes, the next is armed',
      () async {
        backend.cash = 25;
        CallBilling.rememberRate('77', 10);
        await connect();
        await settleUntil(
          () => CallBilling.topUpDue.value == '77',
          timeoutMs: 5000,
        );
        final before = CallBilling.limit.value!.endsAt;
        backend.cash = 525; // +50 min
        expect(await CallBilling.rearm('77'), isTrue);
        expect(CallBilling.limit.value!.endsAt.isAfter(before), isTrue);
        expect(
          CallBilling.limit.value!.leftAt(DateTime.now()).inMinutes,
          greaterThanOrEqualTo(50),
        );
        expect(CallBilling.topUpDue.value, isNull);
        expect(CallTimers.instance.isArmed(CallTimers.topUpPrompt), isTrue);
        expect(CallTimers.instance.isArmed(CallTimers.maxDuration), isTrue);
        expect(buzzes, 1, reason: 'no second buzz');
      },
    );

    test('too little added: the prompt stays, no second buzz', () async {
      backend.cash = 25;
      CallBilling.rememberRate('77', 10);
      await connect();
      await settleUntil(
        () => CallBilling.topUpDue.value == '77',
        timeoutMs: 5000,
      );
      backend.cash = 29; // still 2 whole minutes: the same end
      expect(await CallBilling.rearm('77'), isTrue);
      await settle(100);
      expect(CallBilling.topUpDue.value, '77');
      expect(buzzes, 1);
    });

    test('a free call that just stops: no "Add money" (money cannot extend '
        'it)', () async {
      CallBilling.rememberRate('77', 10);
      CallBilling.rememberFree(
        '77',
        const FreeCallTerms(minutes: 1, continuePaid: false),
      );
      await connect();
      expect(CallBilling.limit.value?.extendable, isFalse);
      expect(CallTimers.instance.isArmed(CallTimers.topUpPrompt), isFalse);
      await settle(3300);
      expect(CallBilling.topUpDue.value, isNull);
      expect(buzzes, 0);
    });

    test('a free call that goes on paid, with no money: "Add money" before '
        'the free minutes end', () async {
      backend.cash = 0;
      CallBilling.rememberRate('77', 10);
      CallBilling.rememberFree('77', const FreeCallTerms(minutes: 1));
      await connect();
      final limit = CallBilling.limit.value!;
      expect(limit.freeLimit, isTrue);
      expect(limit.extendable, isTrue);
      await settleUntil(
        () => CallBilling.topUpDue.value == '77',
        timeoutMs: 5000,
      );
      // Money added: the paid minutes after the free one.
      backend.cash = 100;
      await CallBilling.rearm('77');
      expect(CallBilling.limit.value!.freeLimit, isFalse);
      expect(CallBilling.topUpDue.value, isNull);
    });

    test('the call is over: nothing re-armed, nothing left showing', () async {
      backend.cash = 25;
      CallBilling.rememberRate('77', 10);
      await connect();
      await settleUntil(
        () => CallBilling.topUpDue.value == '77',
        timeoutMs: 5000,
      );
      CallBilling.forget('77');
      expect(CallBilling.topUpDue.value, isNull);
      expect(CallBilling.limit.value, isNull);
      expect(await CallBilling.rearm('77'), isFalse);
    });

    test('paying: an end that comes meanwhile waits; money in, the call goes '
        'on', () async {
      backend.cash = 0; // its end is now
      CallBilling.rememberRate('77', 10);
      CallBilling.hold('77', on: true);
      await connect();
      await settle(100);
      expect(calls.value.phase, CallPhase.ongoing, reason: 'held');
      expect(backend.to('POST', callEnd), isEmpty);

      backend.cash = 500;
      CallBilling.markPaid('77');
      CallBilling.hold('77', on: false);
      await settle(150);
      expect(calls.value.phase, CallPhase.ongoing);
      expect(backend.to('POST', callEnd), isEmpty);
      expect(
        CallBilling.limit.value!.leftAt(DateTime.now()).inMinutes,
        greaterThanOrEqualTo(48),
      );
      expect(CallBilling.paidDuring('77'), isTrue);
    });

    test('paying, then nothing paid: released, the call ends then', () async {
      backend.cash = 0;
      CallBilling.rememberRate('77', 10);
      CallBilling.hold('77', on: true);
      await connect();
      await settle(100);
      expect(calls.value.phase, CallPhase.ongoing);

      CallBilling.hold('77', on: false);
      await settleUntil(
        () => backend.to('POST', callEnd).isNotEmpty,
        reason: 'released with no money: it ends',
      );
      expect(alertLog(), contains('toast|callflow:low_balance.ended'));
    });

    test('paid: "Add money" does not come straight back while the money is '
        'on its way', () async {
      backend.cash = 25;
      CallBilling.rememberRate('77', 10);
      await connect();
      await settleUntil(
        () => CallBilling.topUpDue.value == '77',
        timeoutMs: 5000,
      );
      CallBilling.markPaid('77');
      expect(CallBilling.topUpDue.value, isNull);
      // The balance not updated yet (pending): still the same end.
      await CallBilling.rearm('77');
      await settle(200);
      expect(CallBilling.topUpDue.value, isNull);
      expect(buzzes, 1);
    });

    test('never for the receiver', () async {
      calls.receive(
        const CallSession(callId: '42', callerId: '5', receiverId: '9'),
      );
      calls
        ..setAccepted()
        ..setConnected();
      await settle(50);
      expect(CallBilling.limit.value, isNull);
      expect(CallTimers.instance.isArmed(CallTimers.topUpPrompt), isFalse);
    });
  });

  group('free calls (docs/free_calls.md)', () {
    const twoFree = FreeCallTerms(minutes: 2, continuePaid: false);
    const twoThenPaid = FreeCallTerms(minutes: 2);

    test('ending at the free limit: 5 s inside it, warned 30 s before', () {
      final cap = MaxDuration.compute(
        cashBalance: 500,
        ratePerMin: 4,
        free: twoFree,
      )!;
      expect(cap.end, const Duration(seconds: 115));
      expect(cap.warnAt, const Duration(seconds: 85));
      expect(cap.freeLimit, isTrue);
    });

    test('going on paid: the free minutes, then what the cash pays for', () {
      final cap = MaxDuration.compute(
        cashBalance: 9,
        ratePerMin: 4,
        free: twoThenPaid,
      )!;
      // 2 free + 2 paid minutes, 20 s inside the last as any paid call.
      expect(cap.end, const Duration(seconds: 220));
      expect(cap.freeLimit, isFalse);
      // Nothing to pay with: it ends at the free limit after all.
      final broke = MaxDuration.compute(
        cashBalance: 3,
        ratePerMin: 4,
        free: twoThenPaid,
      )!;
      expect(broke.end, const Duration(seconds: 115));
      expect(broke.freeLimit, isTrue);
    });

    test('a company caller or an unpriced call: capped only when it stops', () {
      expect(
        MaxDuration.compute(
          cashBalance: 0,
          ratePerMin: 4,
          company: true,
          free: twoThenPaid,
        ),
        isNull,
      );
      expect(
        MaxDuration.compute(
          cashBalance: 0,
          ratePerMin: 4,
          company: true,
          free: twoFree,
        )!.end,
        const Duration(seconds: 115),
      );
      expect(
        MaxDuration.compute(cashBalance: 0, ratePerMin: 0, free: twoThenPaid),
        isNull,
      );
      expect(
        MaxDuration.compute(cashBalance: 0, ratePerMin: 0, free: twoFree)!.end,
        const Duration(seconds: 115),
      );
    });

    test('armed with no balance read when nothing is paid after', () async {
      backend.cash = 0;
      CallBilling.rememberRate('77', 10);
      CallBilling.rememberFree('77', twoFree);
      calls.startOutgoing(
        const CallSession(callId: '77', callerId: '9', receiverId: '5'),
      );
      calls
        ..setAccepted()
        ..setConnected();
      await settle(50);
      expect(backend.to('GET', '/api/wallets'), isEmpty);
      expect(CallTimers.instance.isArmed(CallTimers.maxDuration), isTrue);
      expect(CallTimers.instance.isArmed(CallTimers.lowBalance), isTrue);
      expect(CallBilling.freeFor('77'), twoFree);
    });

    test('at the free limit: hung up with the free-call words', () async {
      CallBilling.rememberRate('77', 10);
      CallBilling.rememberFree('77', const FreeCallTerms(minutes: 0));
      expect(CallBilling.freeFor('77'), isNull, reason: 'no free minutes');
      CallBilling.rememberFree('77', twoFree);
      calls.startOutgoing(
        const CallSession(callId: '77', callerId: '9', receiverId: '5'),
      );
      calls
        ..setAccepted()
        ..setConnected();
      await settle(50);
      // Two minutes on: armed again from there, the limit is already past.
      var ended = 0;
      await CallBilling.arm(
        calls.value.copyWith(
          connectedAt: DateTime.now().subtract(const Duration(minutes: 2)),
        ),
        onLimit: () => ended++,
      );
      await settle(20);
      expect(ended, 1);
      expect(alertLog(), contains('toast|callflow:free_call.ended'));
      expect(alertLog(), isNot(contains('toast|callflow:low_balance.ended')));
      CallBilling.forget('77');
      expect(CallBilling.freeFor('77'), isNull);
    });

    test('a later answer can take the free terms back', () {
      CallBilling.rememberFree('s1', twoFree);
      CallBilling.rememberFree('s1', null);
      expect(CallBilling.freeFor('s1'), isNull);
    });

    test('terms and status read from the server', () {
      expect(FreeCallTerms.tryParse(null), isNull);
      expect(FreeCallTerms.tryParse({'minutes': 0}), isNull);
      expect(
        FreeCallTerms.tryParse({'minutes': 3, 'continuePaid': false}),
        const FreeCallTerms(minutes: 3, continuePaid: false),
      );
      expect(FreeCallTerms.of('2', 'true'), twoThenPaid);
      expect(FreeCallTerms.of('2', null), twoThenPaid);
      expect(FreeCallTerms.of(null, 'false'), isNull);

      final call = InitiatedCall.tryParse({
        'callDetails': {'id': 5},
        'channelName': 'c',
        'callerToken': 't',
        'freeCall': {'minutes': 2, 'continuePaid': false},
      })!;
      expect(call.freeCall, twoFree);
      expect(
        InitiatedCall.tryParse({
          'callDetails': {'id': 5},
          'channelName': 'c',
          'callerToken': 't',
        })!.freeCall,
        isNull,
      );

      final status = FreeCallStatus.fromJson(const {
        'available': true,
        'callsLeft': 1,
        'minutes': 2,
        'voice': true,
        'video': false,
        'normal': true,
        'talkNow': false,
      });
      expect(status.covers(video: false, talkNow: false), isTrue);
      expect(status.covers(video: true, talkNow: false), isFalse);
      expect(status.covers(video: false, talkNow: true), isFalse);
      expect(
        FreeCallStatus.fromJson(const {
          'available': true,
          'callsLeft': 0,
          'minutes': 2,
        }).available,
        isFalse,
      );
      expect(FreeCallStatus.fromJson(const {}).available, isFalse);
    });
  });

  group('CallApi.fetchStatus (E-85)', () {
    test(
      'numeric id through filters[id], documentId through its filter',
      () async {
        backend.replies['GET /api/calls'] = (_) => {
          'data': [
            {'id': 42, 'callStatus': 'force complete by admin'},
          ],
        };
        expect(
          await CallApi.fetchStatus('42'),
          CallStatus.forceCompleteByAdmin,
        );
        final q = backend.to('GET', '/api/calls').last.o.queryParameters;
        expect(q[r'filters[id][$eq]'], '42');
        expect(q['fields[0]'], 'callStatus');

        await CallApi.fetchStatus('abc123');
        final q2 = backend.to('GET', '/api/calls').last.o.queryParameters;
        expect(q2[r'filters[documentId][$eq]'], 'abc123');

        backend.replies['GET /api/calls'] = (_) => {'data': <Object>[]};
        expect(await CallApi.fetchStatus('42'), CallStatus.unknown);
      },
    );
  });

  group('safety and feedback', () {
    void liveCallerCall() {
      calls.startOutgoing(
        const CallSession(
          callId: '501',
          callerId: '9',
          receiverId: '70',
          receiverDocId: 'exp7',
          remote: CallPeer(id: '70', documentId: 'usr7'),
        ),
      );
      calls
        ..setAccepted()
        ..setConnected();
    }

    test('report during a call: RN body, then hang up', () async {
      liveCallerCall();
      expect(await CallActions.reportDuringCall(), CallSafetyOutcome.done);
      final data = backend.lastBody('POST', '/api/reports')['data'] as Map;
      expect(data, {
        'reported_by_user': 'u9',
        'reported_to_user': 'usr7',
        'note': 'Reported during a live call.',
        'report_status': 'new',
      });
      expect(calls.value.phase.isActive, isFalse);
      await settle();
      expect(backend.to('POST', callEnd), hasLength(1));
    });

    test('block during a call; a failed block says so', () async {
      liveCallerCall();
      backend.failures['POST /api/user-blocks'] = (400, 'nope');
      expect(await CallActions.blockDuringCall(), CallSafetyOutcome.failed);
      expect(calls.value.phase.isActive, isFalse);
      expect(backend.lastBody('POST', '/api/user-blocks'), {
        'targetUserId': 'usr7',
        'reason': 'Blocked during a live call.',
      });
    });

    test('no one to report: noTarget, still hangs up', () async {
      calls.startOutgoing(const CallSession(callId: '501', callerId: '9'));
      expect(await CallActions.reportDuringCall(), CallSafetyOutcome.noTarget);
      expect(calls.value.phase.isActive, isFalse);
      expect(backend.to('POST', '/api/reports'), isEmpty);
    });

    test('feedback: expert-profile id resolved from the host user', () async {
      backend.replies['GET /api/public-users/usr7'] = (_) => {
        'data': {
          'id': 70,
          'documentId': 'usr7',
          'expert': {'id': 7, 'documentId': 'exp7-resolved'},
        },
      };
      liveCallerCall();
      await CallActions.hangup();
      await CallActions.submitFeedback(rating: 4, comments: 'Kind');
      final data = backend.lastBody('POST', '/api/reviews')['data'] as Map;
      expect(data, {
        'expert': 'exp7-resolved',
        'user': 'u9',
        'rating': 4,
        'comments': 'Kind',
        'call': 501,
      });
    });

    test(
      'feedback falls back to the initiate expert id; block after',
      () async {
        backend.failures['GET /api/public-users/usr7'] = (404, 'Not Found');
        liveCallerCall();
        await CallActions.hangup();
        await CallActions.submitFeedback(rating: 5);
        expect(
          (backend.lastBody('POST', '/api/reviews')['data'] as Map)['expert'],
          'exp7',
        );
        expect(await CallActions.blockAfterCall(), isTrue);
        expect(backend.lastBody('POST', '/api/user-blocks'), {
          'targetUserId': 'usr7',
        });
      },
    );
  });
}
