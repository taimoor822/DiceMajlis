import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps what the app needs to stay signed in between launches: the refresh
/// token and this install's device id. The short-lived access token is never
/// stored; it lives in memory only.
abstract class TokenStore {
  Future<String?> readRefreshToken();
  Future<void> saveRefreshToken(String token);
  Future<void> clearRefreshToken();

  /// A random id made once per install. Names the device in the account's
  /// device list; it is not a secret.
  Future<String> deviceId();
}

/// The phone's secure storage (iOS Keychain, Android Keystore; encrypted
/// browser storage on the web). If it can't be used, tokens are kept in
/// memory for this launch only: the app still works, it just signs in again
/// next time.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _refreshKey = 'auth.refresh_token';
  static const _deviceKey = 'auth.device_id';

  final FlutterSecureStorage _storage;
  final Map<String, String> _fallback = {};

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key) ?? _fallback[key];
    } catch (error) {
      debugPrint('Secure storage unavailable ($error); using memory.');
      return _fallback[key];
    }
  }

  Future<void> _write(String key, String value) async {
    _fallback[key] = value;
    try {
      await _storage.write(key: key, value: value);
    } catch (error) {
      debugPrint('Secure storage unavailable ($error); using memory.');
    }
  }

  @override
  Future<String?> readRefreshToken() => _read(_refreshKey);

  @override
  Future<void> saveRefreshToken(String token) => _write(_refreshKey, token);

  @override
  Future<void> clearRefreshToken() async {
    _fallback.remove(_refreshKey);
    try {
      await _storage.delete(key: _refreshKey);
    } catch (error) {
      debugPrint('Secure storage unavailable ($error).');
    }
  }

  @override
  Future<String> deviceId() async {
    final saved = await _read(_deviceKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final id = newDeviceId();
    await _write(_deviceKey, id);
    return id;
  }
}

/// 32 random hex characters.
String newDeviceId([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(
    16,
    (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());
