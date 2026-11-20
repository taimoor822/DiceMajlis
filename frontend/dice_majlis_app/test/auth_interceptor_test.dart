// Every request carries the access token; an expired one is refreshed once.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dice_majlis_app/core/network/auth_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers requests from a script and records the Authorization headers.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.answers);

  final List<(int, Map<String, dynamic>)> answers;
  final seenTokens = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seenTokens.add(options.headers['Authorization'] as String?);
    final (status, body) = answers.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Dio dio;
  late ScriptedAdapter adapter;
  late String current;
  late int refreshes;
  late int sessionsEnded;

  void setUpDio(List<(int, Map<String, dynamic>)> answers) {
    current = 'old';
    refreshes = 0;
    sessionsEnded = 0;
    adapter = ScriptedAdapter(answers);
    dio = Dio(BaseOptions(baseUrl: 'http://test/'))
      ..httpClientAdapter = adapter;
    dio.interceptors.add(
      AuthInterceptor(
        accessToken: () async => current,
        refreshAccess: () async {
          refreshes++;
          return current = 'new';
        },
        onSessionEnded: () async => sessionsEnded++,
        retry: dio.fetch,
      ),
    );
  }

  test('adds the access token to requests', () async {
    setUpDio([
      (200, {'ok': true}),
    ]);
    final response = await dio.get<dynamic>('me/');
    expect(response.statusCode, 200);
    expect(adapter.seenTokens, ['Bearer old']);
  });

  test('an expired token is refreshed and the request sent again', () async {
    setUpDio([
      (401, {'code': 'token_expired'}),
      (200, {'ok': true}),
    ]);
    final response = await dio.get<dynamic>('me/');
    expect(response.statusCode, 200);
    expect(refreshes, 1);
    expect(adapter.seenTokens, ['Bearer old', 'Bearer new']);
  });

  test('only one retry: a second 401 is passed on', () async {
    setUpDio([
      (401, {'code': 'token_expired'}),
      (401, {'code': 'token_expired'}),
    ]);
    await expectLater(dio.get<dynamic>('me/'), throwsA(isA<DioException>()));
    expect(refreshes, 1);
  });

  test('a session the server ended signs out, without a retry', () async {
    setUpDio([
      (401, {'code': 'session_revoked'}),
    ]);
    await expectLater(dio.get<dynamic>('me/'), throwsA(isA<DioException>()));
    expect(sessionsEnded, 1);
    expect(refreshes, 0);
  });

  test('other errors pass through untouched', () async {
    setUpDio([
      (403, {'code': 'not_in_room'}),
    ]);
    try {
      await dio.post<dynamic>('game/roll-dice/');
      fail('should throw');
    } on DioException catch (error) {
      expect(error.response?.statusCode, 403);
    }
    expect(refreshes, 0);
  });
}
