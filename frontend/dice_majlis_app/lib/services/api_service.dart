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
    int maxPlayers = 4,
  }) async {
    try {
      final response = await _dio.post(
        'create-room/',
        data: {'name': name, 'color': color, 'max_players': maxPlayers},
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
  static Future<void> rollDice({
    required String roomCode,
    required String playerId,
  }) async {
    try {
      await _dio.post(
        'roll-dice/',
        data: {'code': roomCode, 'player_id': playerId},
      );
    } on DioException catch (e) {
      debugPrint('ROLL DICE ERROR: ${e.response?.data}');
      throw Exception(e.response?.data ?? 'Failed to roll dice');
    }
  }

  // ================= MOVE TOKEN =================

  static Future<void> moveToken({
    required String code,
    required String playerId,
    required String tokenId,
  }) async {
    try {
      await _dio.post(
        'move-token/',
        data: {'code': code, 'player_id': playerId, 'token_id': tokenId},
      );
    } on DioException catch (e) {
      debugPrint('MOVE TOKEN ERROR: ${e.response?.data}');
      throw Exception(e.response?.data ?? 'Failed to move token');
    }
  }
}
