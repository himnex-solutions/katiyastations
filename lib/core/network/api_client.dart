// ============================================================
// KATIYA STATION RMS — DIO HTTP API CLIENT
// Enterprise HTTP client with JWT auth, auto-refresh,
// error mapping, logging, and timeout configuration
// ============================================================

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../constants/api_constants.dart';
import '../errors/app_exceptions.dart';
import '../storage/secure_storage.dart';

// ── Result Type for API calls ──────────────────────────────
typedef ApiResult<T> = Future<T>;

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  late final Dio _dio;
  bool _initialized = false;

  // ── Initialize (called in main.dart) ──────────────────────
  void initialize() {
    if (_initialized) return;

    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.apiBase,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        sendTimeout: ApiConstants.sendTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        // Only treat 2xx as success. The previous `status < 500` here
        // silently treated 401/403/404/409/422 as "successful" responses
        // (Dio never throws, so onError/_mapDioError never runs) — which
        // meant an expired access token never triggered the refresh
        // interceptor below at all: /auth/me would just come back with
        // the 401 error body parsed as if it were a real profile, hit
        // the "invalid" branch, and log the user out immediately instead
        // of silently refreshing. That's likely the actual cause of the
        // session-timeout/auto-logout behavior reported.
      ),
    );

    // ── Auth Interceptor (JWT + Auto-Refresh) ──────────────
    _dio.interceptors.add(_JwtInterceptor(_dio));

    // ── Logger (dev only) ──────────────────────────────────
    if (kDebugMode) {
      _dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: true,
          requestBody: true,
          responseBody: true,
          responseHeader: false,
          error: true,
          compact: true,
        ),
      );
    }

    _initialized = true;
  }

  Dio get dio {
    assert(_initialized, 'ApiClient must be initialized before use.');
    return _dio;
  }

  // ── GET ────────────────────────────────────────────────────
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── POST ───────────────────────────────────────────────────
  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── PUT ────────────────────────────────────────────────────
  Future<Response> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── PATCH ──────────────────────────────────────────────────
  Future<Response> patch(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.patch(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── DELETE ─────────────────────────────────────────────────
  Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── Upload multipart ───────────────────────────────────────
  Future<Response> upload(
    String path,
    FormData formData, {
    void Function(int, int)? onSendProgress,
  }) async {
    try {
      return await _dio.post(
        path,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
        onSendProgress: onSendProgress,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── Error Mapper ───────────────────────────────────────────
  AppException _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkException('Connection timed out. Please check your internet.');

      case DioExceptionType.connectionError:
        return const NetworkException('Cannot reach the server. Check your network connection.');

      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final responseData = e.response?.data;

        String message = 'An error occurred.';
        String? code;

        if (responseData is Map<String, dynamic>) {
          message = responseData['message'] as String? ??
              responseData['error'] as String? ??
              message;
          code = responseData['code'] as String?;
        }

        if (statusCode == 401) {
          return AuthException(message);
        } else if (statusCode == 403) {
          return PermissionException(message);
        } else if (statusCode == 404) {
          return ApiException(message, statusCode: 404, code: code ?? 'NOT_FOUND');
        } else if (statusCode == 409) {
          return ApiException(message, statusCode: 409, code: code ?? 'CONFLICT');
        } else if (statusCode == 422) {
          return ValidationException(message, code: code ?? 'VALIDATION_ERROR');
        } else if (statusCode != null && statusCode >= 500) {
          return const ServerException();
        }
        return ApiException(message, statusCode: statusCode, code: code);

      case DioExceptionType.cancel:
        return const AppExceptionCancelled();

      default:
        return UnknownException(
          e.message ?? 'An unknown error occurred.',
          originalError: e,
        );
    }
  }
}

// ── JWT Interceptor ────────────────────────────────────────
class _JwtInterceptor extends QueuedInterceptorsWrapper {
  final Dio _dio;

  // Shared by all concurrent requests: when a screen fires several API
  // calls at once (very common — dashboards mount many providers
  // together) and the access token has expired, they all 401 back
  // near-simultaneously. Coalescing onto one in-flight refresh means
  // every one of them awaits the *same* result and retries with the new
  // token, instead of only the first request refreshing while the rest
  // fail outright and (with nothing clearing storage) leave the app in
  // a half-authenticated state that looks like a random logout.
  Future<String?>? _refreshFuture;

  _JwtInterceptor(this._dio);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await SecureStorage.instance.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final path = err.requestOptions.path;
    final isAuthEndpoint = path == ApiConstants.login || path == ApiConstants.refresh;

    if (err.response?.statusCode != 401 || isAuthEndpoint) {
      handler.next(err);
      return;
    }

    _refreshFuture ??= _refreshToken();
    final newAccessToken = await _refreshFuture;
    _refreshFuture = null;

    if (newAccessToken == null) {
      // Refresh token is genuinely gone/expired/revoked — this is a real
      // logout, so leave the session cleared rather than stuck half-signed-in.
      await SecureStorage.instance.clearSession();
      handler.next(err);
      return;
    }

    try {
      final opts = err.requestOptions;
      opts.headers['Authorization'] = 'Bearer $newAccessToken';
      final response = await _dio.fetch(opts);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<String?> _refreshToken() async {
    final refreshToken = await SecureStorage.instance.getRefreshToken();
    if (refreshToken == null) return null;

    try {
      final response = await Dio().post(
        '${ApiConstants.apiBase}${ApiConstants.refresh}',
        data: {'refreshToken': refreshToken},
      );
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final accessToken = data['accessToken'] as String;
        final newRefreshToken = data['refreshToken'] as String?;

        await SecureStorage.instance.saveAccessToken(accessToken);
        if (newRefreshToken != null) {
          await SecureStorage.instance.saveRefreshToken(newRefreshToken);
        }
        return accessToken;
      }
    } catch (_) {}
    return null;
  }
}

// ── Cancelled Exception (non-error) ───────────────────────
class AppExceptionCancelled extends AppException {
  const AppExceptionCancelled() : super('Request was cancelled.', code: 'CANCELLED');
}
