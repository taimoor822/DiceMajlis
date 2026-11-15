import 'package:dice_majlis_app/core/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('development defaults per platform', () {
    expect(AppConfig.defaultServerUrl(isWeb: true), 'http://127.0.0.1:8000');
    expect(
      AppConfig.defaultServerUrl(
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      'http://10.0.2.2:8000',
    );
    expect(
      AppConfig.defaultServerUrl(isWeb: false, platform: TargetPlatform.iOS),
      'http://127.0.0.1:8000',
    );
  });

  test('WebSocket address follows the server address', () {
    expect(
      AppConfig.webSocketUrlFor('http://192.168.1.20:8000'),
      'ws://192.168.1.20:8000',
    );
    expect(
      AppConfig.webSocketUrlFor('https://api.dicemajlis.app'),
      'wss://api.dicemajlis.app',
    );
  });

  test('trailing slashes are removed', () {
    expect(AppConfig.trimTrailingSlash('http://x:8000/'), 'http://x:8000');
    expect(AppConfig.trimTrailingSlash('http://x:8000'), 'http://x:8000');
  });

  test('API_BASE_URL overrides the defaults; API and socket follow it', () {
    const override = String.fromEnvironment('API_BASE_URL');
    expect(
      AppConfig.serverUrl,
      override.isEmpty
          ? AppConfig.defaultServerUrl()
          : AppConfig.trimTrailingSlash(override),
    );
    expect(AppConfig.gameApiUrl, '${AppConfig.serverUrl}/api/game/');
    expect(
      AppConfig.webSocketUrl,
      AppConfig.webSocketUrlFor(AppConfig.serverUrl),
    );
  });
}
