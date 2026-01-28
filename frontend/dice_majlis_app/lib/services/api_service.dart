import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'http://172.20.10.3:8000/api/game/', // ⚠️ CHANGE THIS IP
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
      },
    ),
  );

  static Future<Map<String, dynamic>> createRoom({
    required String name,
    required String color,
    int maxPlayers = 4,
  }) async {
    try {
      final response = await _dio.post(
        'create-room/',
        data: {
          'name': name,
          'color': color,
          'max_players': maxPlayers,
        },
      );
      return response.data;
    } catch (e) {
      debugPrint('CREATE ROOM ERROR: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> joinRoom({
    required String code,
    required String name,
    required String color,
  }) async {
    try {
      final response = await _dio.post(
        'join-room/',
        data: {
          'code': code,
          'name': name,
          'color': color,
        },
      );
      return response.data;
    } catch (e) {
      debugPrint('JOIN ROOM ERROR: $e');
      rethrow;
    }
  }
}
