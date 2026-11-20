import 'package:dio/dio.dart';

/// A failed server call. [code] is the server's stable error code
/// (`room_full`, `not_your_turn`, ...) or one of the local codes below; screens
/// turn it into a translated message with `l10n.apiErrorText(error)`.
class ApiException implements Exception {
  const ApiException(this.code, {this.statusCode, this.serverMessage});

  /// The server could not be reached (offline, timeout, wrong address).
  static const networkError = 'network_error';

  /// The server answered, but not in a way the app understands.
  static const unknownError = 'unknown_error';

  final String code;
  final int? statusCode;

  /// The server's English text. For logs only; never shown to players.
  final String? serverMessage;

  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    if (response == null) return const ApiException(networkError);
    final data = response.data;
    if (data is Map && data['code'] is String) {
      return ApiException(
        data['code'] as String,
        statusCode: response.statusCode,
        serverMessage: data['error']?.toString(),
      );
    }
    return ApiException(unknownError, statusCode: response.statusCode);
  }

  @override
  String toString() =>
      'ApiException($code'
      '${statusCode == null ? '' : ', HTTP $statusCode'}'
      '${serverMessage == null ? '' : ', $serverMessage'})';
}
