import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../config/env.dart';
import '../storage/app_prefs.dart';
import '../storage/token_storage.dart';
import '../utils/log.dart';
import 'api_exception.dart';
import 'device_info.dart';

/// Single HTTP entry point (port of RN `src/core/api/client.js`).
///
/// Feature API files call [get]/[post]/[put]/[patch]/[delete]/[upload]; they
/// never touch [dio] directly. Every method returns the decoded response body
/// and throws only [ApiException].
///
/// Paths are written like the RN code: `'/me/interests'` → `/api/me/interests`.
abstract final class ApiClient {
  static final Dio dio = _create();

  // ── Session events ─────────────────────────────────────────────────────
  static final _sessionExpired = StreamController<ApiException>.broadcast();
  static final _tokenRefreshed = StreamController<String>.broadcast();

  /// The session could not be refreshed (no answer, or the server refused
  /// the refresh token). NEVER a sign-out: the app only signs out from the
  /// Logout button. `SessionHealth` shows "Server unreachable" with Retry.
  static Stream<ApiException> get onSessionExpired => _sessionExpired.stream;

  /// Refreshes the access token now (single flight): `SessionHealth`'s
  /// Retry. Throws [ApiException] / the refresh error when it fails.
  static Future<String> refreshSession() => _refreshAccessToken();

  /// New access token after a refresh (e.g. to hand to native CallKit code).
  static Stream<String> get onTokenRefreshed => _tokenRefreshed.stream;

  static bool _loggingOut = false;
  static bool get isLoggingOut => _loggingOut;

  /// Blocks every non-auth request until an auth call (login) or
  /// [resetLogoutFlag] — stops in-flight screens from firing during logout.
  static void beginLogout() => _loggingOut = true;
  static void resetLogoutFlag() => _loggingOut = false;

  // ── Typed wrappers ─────────────────────────────────────────────────────
  static Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool skipAuth = false,
    bool retry = true,
    Duration? timeout,
    CancelToken? cancelToken,
  }) => _send(
    () => dio.get(
      path,
      queryParameters: query,
      options: _opts(skipAuth: skipAuth, retry: retry, timeout: timeout),
      cancelToken: cancelToken,
    ),
  );

  /// Raw bytes (a private picture kept in memory only).
  static Future<Uint8List> getBytes(String path) => guard(() async {
    final res = await dio.get<List<int>>(
      path,
      options: _opts().copyWith(responseType: ResponseType.bytes),
    );
    final data = res.data ?? const <int>[];
    return data is Uint8List ? data : Uint8List.fromList(data);
  });

  static Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    bool skipAuth = false,
    Duration? timeout,
  }) => _send(
    () => dio.post(
      path,
      data: data,
      queryParameters: query,
      options: _opts(skipAuth: skipAuth, headers: headers, timeout: timeout),
    ),
  );

  static Future<dynamic> put(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    bool skipAuth = false,
    Duration? timeout,
  }) => _send(
    () => dio.put(
      path,
      data: data,
      queryParameters: query,
      options: _opts(skipAuth: skipAuth, timeout: timeout),
    ),
  );

  static Future<dynamic> patch(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  }) => _send(
    () => dio.patch(path, data: data, queryParameters: query, options: _opts()),
  );

  static Future<dynamic> delete(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  }) => _send(
    () =>
        dio.delete(path, data: data, queryParameters: query, options: _opts()),
  );

  /// Multipart upload (Strapi `/upload`, documents, images).
  static Future<dynamic> upload(
    String path,
    FormData form, {
    void Function(int sent, int total)? onProgress,
  }) => _send(
    () => dio.post(
      path,
      data: form,
      onSendProgress: onProgress,
      options: _opts(timeout: const Duration(seconds: 60)),
    ),
  );

  /// Runs multi-step API logic and converts any failure to [ApiException].
  static Future<T> guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e, st) {
      throw ApiException.from(e, st);
    }
  }

  static Future<dynamic> _send(Future<Response<dynamic>> Function() call) =>
      guard(() async => (await call()).data);

  static Options _opts({
    bool skipAuth = false,
    bool retry = true,
    Map<String, dynamic>? headers,
    Duration? timeout,
  }) => Options(
    headers: headers,
    sendTimeout: timeout,
    receiveTimeout: timeout,
    extra: {_kSkipAuth: skipAuth, _kRetry: retry},
  );

  // ── Setup ──────────────────────────────────────────────────────────────
  static Dio _create() {
    final dio = Dio(
      BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: _baseHeaders,
      ),
    );
    dio.interceptors.addAll([
      _AuthInterceptor(dio),
      _TransientRetryInterceptor(dio),
      if (kDebugMode)
        PrettyDioLogger(
          requestBody: true,
          responseBody: false,
          compact: true,
          maxWidth: 100,
        ),
    ]);
    if (Env.defaultApiToken.isEmpty) {
      Log.w(
        'ApiClient',
        'DEFAULT_API_TOKEN missing: run with '
            '--dart-define-from-file=config/env.json',
      );
    }
    return dio;
  }

  static Map<String, dynamic> get _baseHeaders => {
    'Content-Type': 'application/json',
    'x-ce-app': Env.appPlatform,
    'x-ce-platform': DeviceInfo.platform,
    'x-platform': DeviceInfo.platform,
    'x-delivery-method': 'json',
  };

  // ── Refresh (single flight) ────────────────────────────────────────────
  static Future<String>? _refreshing;

  static Future<String> _refreshAccessToken() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  static Future<String> _doRefresh() async {
    final refreshToken = await TokenStorage.instance.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const ApiException(ApiErrorType.unauthorized);
    }
    final Response<dynamic> res;
    try {
      // Bare Dio: the refresh call must not go through the 401 interceptor.
      // Same transport as every other request (tests fake it there).
      final bare = Dio(
        BaseOptions(
          baseUrl: Env.apiBaseUrl,
          connectTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          // Long on purpose: a slow server still completes the refresh and
          // rotates the token. Giving up at 10 s threw the new pair away, and
          // the next refresh (with the old token) was refused (29 Oct: every
          // user signed out).
          receiveTimeout: const Duration(seconds: 60),
          headers: _baseHeaders,
        ),
      )..httpClientAdapter = dio.httpClientAdapter;
      res = await bare.post<dynamic>(
        '/api/session-auth/refresh',
        data: {
          'refreshToken': refreshToken,
          // The rotated session takes its push tokens from here, else
          // from older rows of this device id, which can be dead or
          // empty — and a call rings only the session's token. Keys as
          // in PushTokens (api/authscreen/push_api.dart).
          'deviceInfo': {
            ...await DeviceInfo.get(),
            'fcmToken': ?_nonEmpty(AppPrefs.getString('fcm_token')),
            'voipToken': ?_nonEmpty(AppPrefs.getString('voip_token')),
          },
        },
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        final access = await _rotatedElsewhere(refreshToken);
        if (access != null) {
          _loggingOut = false;
          _tokenRefreshed.add(access);
          return access;
        }
      }
      rethrow;
    }

    final body = res.data;
    final d = body is Map ? (body['data'] is Map ? body['data'] : body) : null;
    final tokens = d is Map && d['tokens'] is Map ? d['tokens'] as Map : null;
    final session = d is Map && d['session'] is Map
        ? d['session'] as Map
        : null;
    final access = (d?['accessToken'] ?? d?['token'] ?? tokens?['accessToken'])
        ?.toString();
    final refresh =
        (d?['refreshToken'] ??
                session?['refreshToken'] ??
                tokens?['refreshToken'])
            ?.toString();
    if (access == null || access.isEmpty) {
      throw const ApiException(ApiErrorType.parse);
    }

    await TokenStorage.instance.saveTokens(
      accessToken: access,
      refreshToken: refresh,
    );
    _loggingOut = false;
    _tokenRefreshed.add(access);
    Log.d('ApiClient', 'token refreshed');
    return access;
  }

  /// The refresh token was refused because another isolate (the FCM or
  /// CallKit background handler, refreshing at the same moment) already
  /// used it: the backend accepts each one once. That isolate saves the new
  /// pair to the shared store a moment later — use it. Logging out instead
  /// wiped the session for every isolate, and each ring after that was
  /// dropped as signed out until the next login.
  static Future<String?> _rotatedElsewhere(String sent) async {
    for (var i = 0; i < 6; i++) {
      final current = await TokenStorage.instance.readRefreshToken();
      if (current != null && current.isNotEmpty && current != sent) {
        final access = await TokenStorage.instance.readAccessToken();
        if (access != null && access.isNotEmpty) return access;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return null;
  }

  /// The session could not be refreshed: say so (`SessionHealth`), keep
  /// the user signed in with their tokens. Never a sign-out.
  static void _reportSessionTrouble(Object cause) {
    Log.w('ApiClient', 'session refresh failed, staying signed in ($cause)');
    _sessionExpired.add(ApiException.from(cause));
  }
}

String? _nonEmpty(String? s) => s == null || s.isEmpty ? null : s;

const _kSkipAuth = 'skipAuth';
const _kRetry = 'retry';
const _kRetried401 = 'retried401';
const _kAttempt = 'retryAttempt';

/// OTP, session-auth, referrals and app-config work before login: they use
/// the app token and never trigger a refresh (RN `isAuthEndpoint`).
bool _isAuthEndpoint(String path) =>
    path.contains('/otp/') ||
    path.contains('/session-auth/') ||
    path.contains('/user-referrals') ||
    path.contains('/app-config');

String _normalizePath(String path) {
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(path)) return path;
  final p = path.startsWith('/') ? path : '/$path';
  return p.startsWith('/api/') ? p : '/api$p';
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._dio);
  final Dio _dio;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.path = _normalizePath(options.path);
    final path = options.path;

    if (ApiClient._loggingOut) {
      if (_isAuthEndpoint(path)) {
        ApiClient._loggingOut = false;
      } else {
        return handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            error: const ApiException(ApiErrorType.loggingOut),
          ),
        );
      }
    }

    if (options.extra[_kSkipAuth] != true &&
        !options.headers.containsKey('Authorization')) {
      final token = await TokenStorage.instance.readAccessToken();
      final bearer = (token != null && token.isNotEmpty)
          ? token
          : Env.defaultApiToken;
      if (bearer.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $bearer';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final path = options.path;
    final status = err.response?.statusCode;
    final isRefreshRoute = path.contains('/session-auth/refresh');

    if (status != 401 || options.extra[_kRetried401] == true) {
      return handler.next(err);
    }
    if (ApiClient._loggingOut && !_isAuthEndpoint(path)) {
      return handler.next(err);
    }
    if (isRefreshRoute) {
      ApiClient._reportSessionTrouble(err);
      return handler.next(err);
    }

    // Social login 401 → retry once with the app token.
    if (path.contains('/session-auth/social')) {
      if (Env.defaultApiToken.isEmpty) return handler.next(err);
      return _retry(options, 'Bearer ${Env.defaultApiToken}', handler, err);
    }
    if (_isAuthEndpoint(path) || options.extra[_kSkipAuth] == true) {
      return handler.next(err);
    }

    final hasRefreshToken =
        (await TokenStorage.instance.readRefreshToken())?.isNotEmpty ?? false;
    // Pre-login: no session to refresh, and no reason to log out.
    if (!hasRefreshToken) return handler.next(err);

    try {
      final access = await ApiClient._refreshAccessToken();
      return _retry(options, 'Bearer $access', handler, err);
    } catch (refreshError) {
      // Whatever went wrong (no answer, a server error, a refused token),
      // the user stays signed in: "Server unreachable" + Retry instead.
      ApiClient._reportSessionTrouble(refreshError);
      return handler.next(err);
    }
  }

  Future<void> _retry(
    RequestOptions options,
    String authorization,
    ErrorInterceptorHandler handler,
    DioException original,
  ) async {
    options.headers['Authorization'] = authorization;
    options.extra[_kRetried401] = true;
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    } catch (_) {
      handler.next(original);
    }
  }
}

/// Retries GETs on transient failures (no response, timeout, 408/429/5xx)
/// with a short back-off — RN `getWithRetry`. 4xx are never retried.
class _TransientRetryInterceptor extends Interceptor {
  _TransientRetryInterceptor(this._dio);
  final Dio _dio;

  static const _maxRetries = 2;
  static const _baseDelay = Duration(milliseconds: 700);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final attempt = (options.extra[_kAttempt] as int?) ?? 0;
    final retryable =
        options.method == 'GET' &&
        options.extra[_kRetry] != false &&
        attempt < _maxRetries &&
        err.error is! ApiException &&
        ApiException.from(err).isTransient;
    if (!retryable) return handler.next(err);

    await Future<void>.delayed(_baseDelay * (attempt + 1));
    options.extra[_kAttempt] = attempt + 1;
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
