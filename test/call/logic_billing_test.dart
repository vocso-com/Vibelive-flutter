import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/callscreen/call_api.dart';
import 'package:vibelive/app/api/callscreen/call_models.dart';
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
