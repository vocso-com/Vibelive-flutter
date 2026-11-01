import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/host_status/host_status_api.dart';
import 'package:vibelive/core/network/api_exception.dart';

/// The server refuses a status for reasons a host can act on — the feature is
/// not switched on yet, or they have used their day's allowance. Until these
/// are mapped, both arrive as a bare 403 and the host is shown a generic
/// failure, which reads as the app being broken.
void main() {
  ApiException e(ApiErrorType t, String msg, [Object? data]) =>
      ApiException(t, serverMessage: msg, data: data);

  ApiException coded(String code, String msg) => e(
        ApiErrorType.forbidden,
        msg,
        {'error': {'details': {'code': code}, 'message': msg}},
      );

  group('HostStatusApi.knownErrorKey', () {
    test('the feature being off has its own message', () {
      expect(
        HostStatusApi.knownErrorKey(
          coded('disabled', 'Statuses are not switched on yet.'),
        ),
        HostStatusErrorKeys.disabled,
      );
    });

    test('the daily cap is told apart from being off', () {
      // These need different things from the host: one is wait for us, the
      // other is come back tomorrow. One message for both helps nobody.
      expect(
        HostStatusApi.knownErrorKey(
          coded('daily_limit', 'You can post 10 statuses a day.'),
        ),
        HostStatusErrorKeys.dailyLimit,
      );
    });

    test('an older server with no code still maps by its wording', () {
      // The server shipped before this mapping did.
      expect(
        HostStatusApi.knownErrorKey(
          e(ApiErrorType.forbidden, 'Statuses are not switched on yet.'),
        ),
        HostStatusErrorKeys.disabled,
      );
      expect(
        HostStatusApi.knownErrorKey(
          e(ApiErrorType.forbidden, 'You can post 3 statuses a day. Try again tomorrow.'),
        ),
        HostStatusErrorKeys.dailyLimit,
      );
    });

    test('a plain forbidden with nothing to go on still reads as off', () {
      // Better "not switched on" than "something went wrong": it is the most
      // likely reason a host is forbidden from posting, and it is not alarming.
      expect(
        HostStatusApi.knownErrorKey(e(ApiErrorType.forbidden, 'Forbidden')),
        HostStatusErrorKeys.disabled,
      );
    });

    test('a real server fault is NOT dressed up as a feature switch', () {
      // A 500 is our problem. Telling a host "not switched on" would send them
      // away instead of letting them retry.
      expect(HostStatusApi.knownErrorKey(e(ApiErrorType.server, 'boom')), isNull);
    });

    test('an upload or network failure is left alone', () {
      expect(HostStatusApi.knownErrorKey(e(ApiErrorType.network, 'offline')), isNull);
    });
  });

  group('HostStatusErrorKeys', () {
    test('every key is namespaced so the i18n parity test can see it', () {
      for (final k in [
        HostStatusErrorKeys.disabled,
        HostStatusErrorKeys.dailyLimit,
        HostStatusErrorKeys.tooLong,
        HostStatusErrorKeys.postFailed,
      ]) {
        expect(k, startsWith('hostflow:'));
        expect(k, contains('.'));
      }
    });
  });
}
