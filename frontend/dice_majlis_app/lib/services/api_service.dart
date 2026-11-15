import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../app/config.dart';

class ApiService {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.gameApiUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

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
  static Future<int> rollDice({
    required String roomCode,
    required String playerId,
  }) async {
    try {
      final response = await _dio.post(
        'roll-dice/',
        data: {'code': roomCode, 'player_id': playerId},
      );
      final data = response.data;
      if (data is Map && data['dice'] != null) {
        final dice = (data['dice'] as num).toInt();
        if (dice >= 1 && dice <= 6) return dice;
      }
      throw Exception('Invalid dice response');
    } on DioException catch (e) {
      debugPrint('ROLL DICE ERROR: ${e.response?.data}');
      throw Exception(e.response?.data ?? 'Failed to roll dice');
    }
  }

  // ================= MOVE TOKEN =================

  static Future<Map<String, dynamic>> moveToken({
    required String roomCode,
    required String playerId,
    required String tokenId,
  }) async {
    try {
      final response = await _dio.post(
        'move-token/',
        data: {'code': roomCode, 'player_id': playerId, 'token_id': tokenId},
      );
      final data = response.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return const <String, dynamic>{};
    } on DioException catch (e) {
      debugPrint('MOVE TOKEN ERROR: ${e.response?.data}');
      throw Exception(e.response?.data ?? 'Failed to move token');
    }
  }
}
