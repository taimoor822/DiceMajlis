import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../network/api_exception.dart';
import 'account.dart';

/// What the server returns when signing in or refreshing.
class AuthTokens {
  const AuthTokens({
    required this.access,
    required this.refresh,
    required this.accessExpiresIn,
    required this.account,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    access: json['access'] as String,
    refresh: json['refresh'] as String,
    accessExpiresIn: Duration(
      seconds: (json['access_expires_in'] as num).toInt(),
    ),
    account: Account.fromJson(
      Map<String, dynamic>.from(json['account'] as Map),
    ),
  );

  final String access;
  final String refresh;
  final Duration accessExpiresIn;
  final Account account;
}

/// The sign-in endpoints. Uses its own plain connection (no automatic token
/// handling), since these calls are what that handling is built on.
class AuthApi {
  AuthApi([Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.apiUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'Content-Type': 'application/json'},
            ),
          );

  final Dio _dio;

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? data,
    String? access,
  }) async {
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        options: Options(
          method: method,
          headers: access == null ? null : {'Authorization': 'Bearer $access'},
        ),
      );
      final body = response.data;
      if (body is Map) return Map<String, dynamic>.from(body);
      return const {};
    } on DioException catch (error) {
      final failure = ApiException.fromDio(error);
      debugPrint('$method $path failed: $failure');
      throw failure;
    }
  }

  /// "Play as guest": a new account with a permanent Player ID.
  Future<AuthTokens> signInAsGuest({
    required String deviceId,
    required String platform,
  }) async => AuthTokens.fromJson(
    await _send(
      'POST',
      'auth/guest/',
      data: {'device_id': deviceId, 'platform': platform},
    ),
  );

  /// A new account with email + password.
  Future<AuthTokens> register({
    required String email,
    required String password,
    required String deviceId,
    required String platform,
  }) async => AuthTokens.fromJson(
    await _send(
      'POST',
      'auth/register/',
      data: {
        'email': email,
        'password': password,
        'device_id': deviceId,
        'platform': platform,
      },
    ),
  );

  /// Sign in with email + password on this device.
  Future<AuthTokens> login({
    required String email,
    required String password,
    required String deviceId,
    required String platform,
  }) async => AuthTokens.fromJson(
    await _send(
      'POST',
      'auth/login/',
      data: {
        'email': email,
        'password': password,
        'device_id': deviceId,
        'platform': platform,
      },
    ),
  );

  /// Emails a 6-digit code if the address has an account (same answer if not).
  Future<void> requestPasswordReset(String email) =>
      _send('POST', 'auth/password-reset/', data: {'email': email});

  /// Sets a new password with the emailed code. Signs out everywhere.
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) => _send(
    'POST',
    'auth/password-reset/confirm/',
    data: {'email': email, 'code': code, 'new_password': newPassword},
  );

  /// Swaps the refresh token for new tokens (the old one stops working).
  Future<AuthTokens> refresh(String refreshToken) async => AuthTokens.fromJson(
    await _send('POST', 'auth/refresh/', data: {'refresh': refreshToken}),
  );

  Future<Account> me(String access) async =>
      Account.fromJson(await _send('GET', 'me/', access: access));

  /// Signs this device out on the server.
  Future<void> signOut(String access) =>
      _send('POST', 'auth/logout/', access: access);
}

final authApiProvider = Provider<AuthApi>((ref) => AuthApi());

/// The platform name the server records for this device.
String devicePlatform() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => 'desktop',
    _ => 'other',
  };
}
