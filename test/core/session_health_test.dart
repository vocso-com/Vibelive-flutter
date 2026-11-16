import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/banner/session_issue_host.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/session/session_health.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/token_storage.dart';

import '../ui/host_onboarding_support/harness.dart';

/// The app never signs anyone out on its own: a session that can't be
/// refreshed (no answer, a server error, a refused token) keeps the user
/// signed in, with "Server unreachable" and Retry. Only the Logout button
/// signs out.
class _Server implements HttpClientAdapter {
  /// What `/session-auth/refresh` answers: an HTTP status (200 = new
  /// tokens), or null for no answer at all.
  int? refresh = 200;
  int refreshes = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    ResponseBody json(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
    if (o.path.contains('/session-auth/refresh')) {
      refreshes++;
      final status = refresh;
      if (status == null) {
        throw DioException.connectionError(
          requestOptions: o,
          reason: 'no answer',
        );
      }
      if (status != 200) {
        return json(status, {
          'error': {'status': status, 'message': 'nope'},
        });
      }
      return json(200, {
        'data': {'accessToken': 'access-2', 'refreshToken': 'refresh-2'},
      });
    }
    // Every other call: the access token has expired.
    final auth = o.headers['Authorization'];
    if (auth == 'Bearer access-2') return json(200, {'data': <Object>[]});
    return json(401, {
      'error': {'status': 401, 'message': 'expired'},
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Server server;

  setUpAll(() async {
    await setUpHostHarness();
  });

  setUp(() async {
    await resetHost();
    server = _Server();
    ApiClient.dio.httpClientAdapter = server;
    await SessionStore.instance.signIn(
      user: {'id': 9, 'documentId': 'u9', 'name': 'Asha'},
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    );
    await SessionStore.instance.restore(); // starts SessionHealth
    SessionHealth.instance.debugReset();
  });

  Future<void> anyRequest() async {
    try {
      await ApiClient.get('/me/anything');
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  test('a refused refresh: still signed in, tokens kept, asked', () async {
    server.refresh = 401;
    await anyRequest();
    expect(SessionStore.instance.value.isAuthenticated, isTrue);
    expect(await TokenStorage.instance.readRefreshToken(), 'refresh-1');
    expect(SessionHealth.instance.value, SessionIssue.rejected);
  });

  test('no answer / a server error: still signed in, "unreachable"', () async {
    server.refresh = null;
    await anyRequest();
    expect(SessionStore.instance.value.isAuthenticated, isTrue);
    expect(SessionHealth.instance.value, SessionIssue.unreachable);

    server.refresh = 503;
    await anyRequest();
    expect(SessionStore.instance.value.isAuthenticated, isTrue);
    expect(SessionHealth.instance.value, SessionIssue.unreachable);
  });

  test('Retry once the server is back: the issue clears', () async {
    server.refresh = null;
    await anyRequest();
    expect(SessionHealth.instance.value, SessionIssue.unreachable);

    server.refresh = 200;
    expect(await SessionHealth.instance.retry(), isTrue);
    expect(SessionHealth.instance.value, isNull);
    expect(await TokenStorage.instance.readRefreshToken(), 'refresh-2');
    expect(SessionStore.instance.value.isAuthenticated, isTrue);
  });

  test('a normal refresh needs no screen at all', () async {
    await anyRequest();
    expect(server.refreshes, 1);
    expect(SessionHealth.instance.value, isNull);
  });

  test('the Logout button still signs out (the only way)', () async {
    await SessionStore.instance.signOut();
    expect(SessionStore.instance.value.isAuthenticated, isFalse);
    expect(SessionHealth.instance.value, isNull);
    ApiClient.resetLogoutFlag();
  });

  group('the screen', () {
    Future<void> open(WidgetTester tester) async {
      phone(tester);
      await pumpRoutes(
        tester,
        const SessionIssueHost(child: Scaffold(body: Text('HOME'))),
      );
      await pumpFor(tester, 100);
    }

    testWidgets('unreachable: Retry, no way out but Retry', (tester) async {
      await open(tester);
      expect(find.text("Can't reach the server"), findsNothing);
      SessionHealth.instance.value = SessionIssue.unreachable;
      await pumpFor(tester, 100);
      expect(find.text("Can't reach the server"), findsOneWidget);
      expect(find.text('RETRY'), findsOneWidget);
      expect(find.text('Log in again'), findsNothing);

      server.refresh = 200;
      await tester.tap(find.text('RETRY'));
      await pumpFor(tester, 300);
      expect(find.text("Can't reach the server"), findsNothing);
      await finishHost(tester);
    });

    testWidgets('refused: Retry, and "Log in again" for the user', (
      tester,
    ) async {
      await open(tester);
      SessionHealth.instance.value = SessionIssue.rejected;
      await pumpFor(tester, 100);
      expect(find.text("Couldn't refresh your session"), findsOneWidget);
      expect(find.text('Log in again'), findsOneWidget);
      expect(tester.takeException(), isNull);
      SessionHealth.instance.debugReset();
      await pumpFor(tester, 50);
      await finishHost(tester);
    });

    testWidgets('"Log in again" asks in the panel itself (a dialog would open '
        'behind it), then signs out', (tester) async {
      await open(tester);
      SessionHealth.instance.value = SessionIssue.rejected;
      await pumpFor(tester, 100);

      // Cancel goes back to Retry.
      await tester.tap(find.text('Log in again'));
      await pumpFor(tester, 100);
      expect(find.text('Are you sure you want to logout?'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.byKey(const ValueKey('session-issue-cancel')));
      await pumpFor(tester, 100);
      expect(find.text('RETRY'), findsOneWidget);

      // Logout: signed out, the panel goes with the session.
      await tester.tap(find.text('Log in again'));
      await pumpFor(tester, 100);
      await tester.tap(find.byKey(const ValueKey('session-issue-logout')));
      await pumpFor(tester, 9000);
      expect(SessionStore.instance.value.isAuthenticated, isFalse);
      expect(find.text("Couldn't refresh your session"), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
      SessionHealth.instance.debugReset();
      ApiClient.resetLogoutFlag();
      await finishHost(tester);
    });
  });
}
