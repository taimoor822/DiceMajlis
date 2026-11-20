import 'package:dice_majlis_app/core/l10n/api_error_text.dart';
import 'package:dice_majlis_app/core/l10n/generated/app_localizations_en.dart';
import 'package:dice_majlis_app/core/network/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('server error codes become friendly messages', () {
    expect(
      l10n.apiErrorText(const ApiException('room_full')),
      'That room is full.',
    );
    expect(
      l10n.apiErrorText(const ApiException('not_your_turn')),
      "It's not your turn.",
    );
    expect(
      l10n.apiErrorText(const ApiException(ApiException.networkError)),
      contains("Can't reach the server"),
    );
  });

  test('unknown codes and other errors get the generic message', () {
    expect(
      l10n.apiErrorText(const ApiException('something_new')),
      l10n.errorGeneric,
    );
    expect(l10n.apiErrorText(Exception('boom')), l10n.errorGeneric);
  });

  group('ApiException.fromDio', () {
    final request = RequestOptions(path: 'roll-dice/');

    test('reads the server code, keeps its text for logs only', () {
      final error = ApiException.fromDio(
        DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: 403,
            data: {'error': 'Not your turn', 'code': 'not_your_turn'},
          ),
        ),
      );
      expect(error.code, 'not_your_turn');
      expect(error.statusCode, 403);
      expect(error.serverMessage, 'Not your turn');
    });

    test('no response means the network failed', () {
      final error = ApiException.fromDio(
        DioException.connectionTimeout(
          timeout: const Duration(seconds: 10),
          requestOptions: request,
        ),
      );
      expect(error.code, ApiException.networkError);
    });

    test('a response without a code is unknown', () {
      final error = ApiException.fromDio(
        DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: 502,
            data: '<html>Bad gateway</html>',
          ),
        ),
      );
      expect(error.code, ApiException.unknownError);
    });
  });
}
