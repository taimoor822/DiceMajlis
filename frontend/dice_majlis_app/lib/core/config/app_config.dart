import 'package:flutter/foundation.dart';

/// Where the app finds the server, chosen when you build or run the app:
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
///
/// The WebSocket address is derived from it (http → ws, https → wss) unless
/// WS_BASE_URL is also given. Without any value the app uses the local
/// development defaults below.
class AppConfig {
  AppConfig._();

  static const String _apiBaseOverride = String.fromEnvironment('API_BASE_URL');
  static const String _wsBaseOverride = String.fromEnvironment('WS_BASE_URL');

  /// Server root without a trailing slash, e.g. `http://10.0.2.2:8000`.
  static String get serverUrl => trimTrailingSlash(
    _apiBaseOverride.isNotEmpty ? _apiBaseOverride : defaultServerUrl(),
  );

  /// Base for the game REST API, e.g. `http://10.0.2.2:8000/api/game/`.
  static String get gameApiUrl => '$serverUrl/api/game/';

  /// WebSocket root, e.g. `ws://10.0.2.2:8000`.
  static String get webSocketUrl => _wsBaseOverride.isNotEmpty
      ? trimTrailingSlash(_wsBaseOverride)
      : webSocketUrlFor(serverUrl);

  /// Local development defaults: browser and iOS simulator reach the computer
  /// at 127.0.0.1, the Android emulator at 10.0.2.2. A real phone needs
  /// API_BASE_URL with the computer's Wi-Fi IP.
  @visibleForTesting
  static String defaultServerUrl({
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
  }) {
    if (isWeb) return 'http://127.0.0.1:8000';
    final target = platform ?? defaultTargetPlatform;
    return target == TargetPlatform.android
        ? 'http://10.0.2.2:8000'
        : 'http://127.0.0.1:8000';
  }

  @visibleForTesting
  static String webSocketUrlFor(String httpUrl) {
    if (httpUrl.startsWith('https://')) {
      return 'wss://${httpUrl.substring('https://'.length)}';
    }
    if (httpUrl.startsWith('http://')) {
      return 'ws://${httpUrl.substring('http://'.length)}';
    }
    return httpUrl;
  }

  @visibleForTesting
  static String trimTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
