import 'package:dio/dio.dart';

class ApiService {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'http://10.0.2.2:8000/api/game/',
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  static Future<Map<String, dynamic>> createRoom({
    required String name,
    required String color,
    int maxPlayers = 4,
  }) async {
    final response = await _dio.post(
      'create-room/',
      data: {
        'name': name,
        'color': color,
        'max_players': maxPlayers,
      },
    );
    return response.data;
  }

  static Future<Map<String, dynamic>> joinRoom({
    required String code,
    required String name,
    required String color,
  }) async {
    final response = await _dio.post(
      'join-room/',
      data: {
        'code': code,
        'name': name,
        'color': color,
      },
    );
    return response.data;
  }
}