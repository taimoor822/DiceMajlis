import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'api_exception.dart';

/// Raw calls to the game REST API. Returns the server's JSON; the feature
/// repositories turn it into typed objects. Every failure is an [ApiException].
///
/// The app only asks ("create a room", "roll", "move this token"). Sizes,
/// dice, positions, names and colours are decided by the server.
class ApiService {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.gameApiUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  static Future<Map<String, dynamic>> _send(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        options: Options(method: method),
      );
      final body = response.data;
      if (body is Map) return Map<String, dynamic>.from(body);
      throw ApiException(
        ApiException.unknownError,
        statusCode: response.statusCode,
      );
    } on DioException catch (error) {
      final failure = ApiException.fromDio(error);
      debugPrint('$method $path failed: $failure');
      throw failure;
    }
  }

  /// What the server allows when creating a room (e.g. the player counts).
  static Future<Map<String, dynamic>> roomOptions() =>
      _send('GET', 'room-options/');

  static Future<Map<String, dynamic>> createRoom({required int maxPlayers}) =>
      _send('POST', 'create-room/', {'max_players': maxPlayers});

  static Future<Map<String, dynamic>> joinRoom({required String code}) =>
      _send('POST', 'join-room/', {'code': code});

  static Future<Map<String, dynamic>> startGame({
    required String roomCode,
    required String playerId,
    required String playerToken,
  }) => _send('POST', 'start-game/', {
    'code': roomCode,
    'player_id': playerId,
    'player_token': playerToken,
  });

  static Future<Map<String, dynamic>> rollDice({
    required String roomCode,
    required String playerId,
    required String playerToken,
  }) => _send('POST', 'roll-dice/', {
    'code': roomCode,
    'player_id': playerId,
    'player_token': playerToken,
  });

  static Future<Map<String, dynamic>> moveToken({
    required String roomCode,
    required String playerId,
    required String playerToken,
    required String tokenId,
  }) => _send('POST', 'move-token/', {
    'code': roomCode,
    'player_id': playerId,
    'player_token': playerToken,
    'token_id': tokenId,
  });
}
