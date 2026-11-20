import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Adds `Authorization: Bearer <access token>` to every request. If the server
/// still says the token is expired, gets a new one (one refresh for everyone
/// waiting) and sends the request once more. If the session has ended, signs
/// out.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.accessToken,
    required this.refreshAccess,
    required this.onSessionEnded,
    required this.retry,
  });

  final Future<String?> Function() accessToken;
  final Future<String?> Function() refreshAccess;
  final Future<void> Function() onSessionEnded;

  /// Sends a request again (through the same interceptors).
  final Future<Response<dynamic>> Function(RequestOptions options) retry;

  static const _retriedKey = 'auth_retried';

  /// Server codes meaning "this access token can't be used, get a new one".
  static const _refreshCodes = {'token_expired', 'invalid_token'};

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final token = await accessToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    } on ApiException catch (error) {
      // Couldn't refresh (offline): fail the request as a network error.
      handler.reject(
        DioException(
          requestOptions: options,
          error: error,
          type: DioExceptionType.connectionError,
        ),
      );
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final data = response?.data;
    final code = data is Map ? data['code'] : null;
    if (response?.statusCode != 401) return handler.next(err);

    if (code == 'session_revoked') {
      await onSessionEnded();
      return handler.next(err);
    }
    final options = err.requestOptions;
    if (!_refreshCodes.contains(code) || options.extra[_retriedKey] == true) {
      return handler.next(err);
    }

    try {
      final token = await refreshAccess();
      if (token == null) return handler.next(err); // signed out
      options.extra[_retriedKey] = true;
      handler.resolve(await retry(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    } on ApiException {
      handler.next(err);
    }
  }
}
