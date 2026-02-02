import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  /// Change this depending on platform
  static const String _baseUrl = kIsWeb
      ? 'http://127.0.0.1:8000/api/game/'
      : 'http://10.0.2.2:8000/api/game/'; // Android emulator

  // ================= CREATE ROOM =================
  static Future<Map<String, dynamic>> createRoom({
    required String name,
    required String color,
  }) async {
    try {
      final response = await _dio.post(
        'create-room/',
        data: {'name': name, 'color': color, 'max_players': 4},
      );

      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      debugPrint('CREATE ROOM ERROR: ${e.response?.data}');
      throw Exception(e.response?.data ?? 'Failed to create room');
    }
  }

  // ================= JOIN ROOM =================
  static Future<Map<String, dynamic>> joinRoom({
    required String code,
    required String name,
    required String color,
  }) async {
    try {
      final response = await _dio.post(
        'join-room/',
        data: {'code': code, 'name': name, 'color': color},
      );

      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      debugPrint('JOIN ROOM ERROR: ${e.response?.data}');
      throw Exception(e.response?.data ?? 'Failed to join room');
    }
  }

  // ================= START GAME =================
  static Future<void> startGame({
    required String code,
    required String playerId,
  }) async {
    try {
      await _dio.post(
        'start-game/',
        data: {'code': code, 'player_id': playerId},
      );
    } on DioException catch (e) {
      debugPrint('START GAME ERROR: ${e.response?.data}');
      throw Exception(e.response?.data ?? 'Failed to start game');
    }
  }

  // ================= ROLL DICE =================
  static Future<Map<String, dynamic>> rollDice({
    required String gameId,
    required String playerId,
  }) async {
    try {
      final response = await _dio.post(
        'roll-dice/',
        data: {'game_id': gameId, 'player_id': playerId},
      );

      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      debugPrint('ROLL DICE ERROR: ${e.response?.data}');
      throw Exception(e.response?.data ?? 'Failed to roll dice');
    }
  }
}
