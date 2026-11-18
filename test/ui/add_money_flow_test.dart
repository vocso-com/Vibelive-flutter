import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/paymentscreen/wallet/helper/add_money_flow.dart';
import 'package:vibelive/app/paymentscreen/wallet/helper/topup_bonus.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_client.dart';

import 'call_support/call_harness.dart';

/// App-config with the first-top-up bonus, and the "ever paid?" question.
class _Backend implements HttpClientAdapter {
  double firstTopupPercent = 100;
  bool paidBefore = false;

  /// The next "ever paid?" questions answer 500.
  int failPaid = 0;
  int paidAsked = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    var code = 200;
    Object body = {'data': <Object>[]};
    switch ('${o.method} ${o.path}') {
      case 'GET /api/app-config':
        body = {
          'data': {
            'bonus': {
              'firstTopupBonusEnabled': firstTopupPercent > 0,
              'firstTopupBonusPercent': firstTopupPercent,
            },
          },
        };
      case 'GET /api/transactions':
        paidAsked++;
        if (failPaid > 0) {
          failPaid--;
          code = 500;
          body = {
            'error': {'status': 500, 'message': 'boom'},
          };
        } else {
          body = {
            'data': [
              if (paidBefore) {'id': 1},
            ],
          };
        }
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      code,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Backend backend;

  setUpAll(callSetUpAll);
  setUp(() async {
    await callSetUp();
    queryCache.clear();
    AddMoneyFlow.debugReset();
    ApiClient.dio.httpClientAdapter = backend = _Backend();
  });

  test('never paid, bonus on: the first-top-up bonus is promised', () async {
    final b = await AddMoneyFlow.firstTopupBonus();
    expect(b?.kind, TopUpBonusKind.firstTopup);
    expect(b?.percent, 100);
  });

  test('paid before, or the bonus off: none', () async {
    backend.paidBefore = true;
    expect(await AddMoneyFlow.firstTopupBonus(), isNull);

    AddMoneyFlow.debugReset();
    queryCache.clear();
    backend
      ..paidBefore = false
      ..firstTopupPercent = 0;
    expect(await AddMoneyFlow.firstTopupBonus(), isNull);
  });

  test('one failed "ever paid?" is asked again (a blip never hides the '
      'bonus)', () async {
    backend.failPaid = 1;
    final b = await AddMoneyFlow.firstTopupBonus();
    expect(b?.percent, 100);
    expect(backend.paidAsked, 2);
  });

  test(
    'both tries failing: no bonus promised (never a wrong promise)',
    () async {
      // Every answer fails (the client's own retries included).
      backend.failPaid = 1000;
      expect(await AddMoneyFlow.firstTopupBonus(), isNull);
    },
  );

  test(
    'asked once for the card and again for Add Money a moment later',
    () async {
      await AddMoneyFlow.firstTopupBonus();
      await AddMoneyFlow.firstTopupBonus();
      expect(backend.paidAsked, 1);
    },
  );
}
