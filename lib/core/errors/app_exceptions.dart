// ============================================================
// KATIYA STATION RMS — APP EXCEPTION TYPES
// Typed exceptions for clean error handling across layers
// ============================================================

/// Base application exception
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic data;

  const AppException(this.message, {this.code, this.data});

  @override
  String toString() => message;
}

/// HTTP / Network exceptions from the API
class ApiException extends AppException {
  final int? statusCode;

  const ApiException(super.message, {super.code, super.data, this.statusCode});

  factory ApiException.fromStatusCode(int statusCode, String message,
      {String? code}) {
    return ApiException(message, statusCode: statusCode, code: code);
  }

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isUnprocessable => statusCode == 422;
  bool get isServerError => statusCode != null && statusCode! >= 500;
}

/// Network connectivity exception
class NetworkException extends AppException {
  const NetworkException(
      [super.message = 'No internet connection. Please check your network.'])
      : super(code: 'NETWORK_ERROR');
}

/// Authentication / Token exception
class AuthException extends AppException {
  const AuthException(
      [super.message = 'Authentication failed. Please login again.'])
      : super(code: 'AUTH_ERROR');
}

/// Authorization / RBAC exception
class PermissionException extends AppException {
  const PermissionException(
      [super.message = 'You do not have permission to perform this action.'])
      : super(code: 'PERMISSION_DENIED');
}

/// Validation exception (client-side)
class ValidationException extends AppException {
  final Map<String, String>? fieldErrors;

  const ValidationException(super.message,
      {this.fieldErrors, super.code = 'VALIDATION_ERROR'});
}

/// Cache / Local storage exception
class CacheException extends AppException {
  const CacheException([super.message = 'Local storage error occurred.'])
      : super(code: 'CACHE_ERROR');
}

/// Token refresh failure
class TokenRefreshException extends AppException {
  const TokenRefreshException(
      [super.message = 'Session expired. Please login again.'])
      : super(code: 'TOKEN_REFRESH_FAILED');
}

/// Offline mode exception
class OfflineException extends AppException {
  const OfflineException(
      [super.message = 'You are offline. This action has been queued.'])
      : super(code: 'OFFLINE');
}

/// Server-specific errors
class ServerException extends AppException {
  const ServerException(
      [super.message = 'Server error occurred. Please try again.'])
      : super(code: 'SERVER_ERROR');
}

/// Generic unknown exception wrapper
class UnknownException extends AppException {
  final Object? originalError;

  const UnknownException(super.message, {this.originalError})
      : super(code: 'UNKNOWN_ERROR');
}
