import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../config/app_config.dart';
import 'auth_api.dart';

/// Google and Apple sign-in (step 1.15). The phone asks Google or Apple; the
/// answer is an ID token that only the server trusts, after checking it
/// (`backend/core/accounts/social.py`).
enum SocialProvider {
  google,
  apple;

  /// The server's name for it (`/api/auth/social/<name>/`).
  String get key => name;

  static SocialProvider? fromKey(String key) {
    for (final provider in values) {
      if (provider.key == key) return provider;
    }
    return null;
  }
}

/// What Google or Apple gave the phone.
class SocialCredential {
  const SocialCredential({required this.idToken, this.nonce});

  final String idToken;

  /// The random value sent to Apple with the sign-in; the server checks the
  /// token carries it (so a token can't be reused from another sign-in).
  final String? nonce;
}

/// The player closed the Google/Apple sheet: nothing to show.
class SocialSignInCancelled implements Exception {
  const SocialSignInCancelled();
}

/// Google/Apple said no, or isn't set up in this build (shown as an error).
class SocialSignInFailed implements Exception {
  const SocialSignInFailed(this.reason);

  final String reason;

  @override
  String toString() => 'SocialSignInFailed($reason)';
}

/// The phone side of Google and Apple sign-in. Tests swap in a fake through
/// [socialSignInProvider].
abstract class SocialSignIn {
  /// Whether this build, on this phone, can sign in with [provider].
  Future<bool> canUse(SocialProvider provider);

  /// Asks Google or Apple. Throws [SocialSignInCancelled] when the player
  /// backs out and [SocialSignInFailed] when it can't be done.
  Future<SocialCredential> credential(SocialProvider provider);
}

/// [SocialSignIn] with the `google_sign_in` and `sign_in_with_apple` plugins.
///
/// Google works on Android and iOS once the build has its client IDs
/// (`AppConfig.googleServerClientId`, and on iOS `googleIosClientId` plus the
/// URL scheme in Info.plist). Apple works on iOS (and macOS) with the "Sign in
/// with Apple" capability; Android needs Apple's web flow, which comes later.
class PluginSocialSignIn implements SocialSignIn {
  Future<void>? _googleReady;

  bool get _isApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _isPhone =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _google() => _googleReady ??= GoogleSignIn.instance.initialize(
    clientId: defaultTargetPlatform == TargetPlatform.iOS
        ? AppConfig.googleIosClientId
        : null,
    serverClientId: AppConfig.googleServerClientId,
  );

  @override
  Future<bool> canUse(SocialProvider provider) async {
    try {
      switch (provider) {
        case SocialProvider.google:
          if (!_isPhone || AppConfig.googleServerClientId.isEmpty) return false;
          if (defaultTargetPlatform == TargetPlatform.iOS &&
              AppConfig.googleIosClientId.isEmpty) {
            return false;
          }
          await _google();
          return GoogleSignIn.instance.supportsAuthenticate();
        case SocialProvider.apple:
          return _isApple && await SignInWithApple.isAvailable();
      }
    } catch (error) {
      debugPrint('Sign-in with ${provider.key} unavailable: $error');
      return false;
    }
  }

  @override
  Future<SocialCredential> credential(SocialProvider provider) =>
      switch (provider) {
        SocialProvider.google => _googleCredential(),
        SocialProvider.apple => _appleCredential(),
      };

  Future<SocialCredential> _googleCredential() async {
    try {
      await _google();
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null) throw const SocialSignInFailed('no_id_token');
      return SocialCredential(idToken: token);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const SocialSignInCancelled();
      }
      throw SocialSignInFailed(error.code.name);
    }
  }

  Future<SocialCredential> _appleCredential() async {
    final nonce = randomNonce();
    try {
      final result = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email],
        nonce: sha256Hex(nonce),
      );
      final token = result.identityToken;
      if (token == null) throw const SocialSignInFailed('no_id_token');
      return SocialCredential(idToken: token, nonce: nonce);
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const SocialSignInCancelled();
      }
      throw SocialSignInFailed(error.code.name);
    }
  }
}

/// 32 random bytes, URL-safe (Apple's nonce; only its hash goes to Apple).
@visibleForTesting
String randomNonce([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => source.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

@visibleForTesting
String sha256Hex(String value) => sha256.convert(utf8.encode(value)).toString();

final socialSignInProvider = Provider<SocialSignIn>(
  (ref) => PluginSocialSignIn(),
);

/// The sign-in buttons to show: set up on the server AND usable on this
/// phone. Empty when the server can't be asked (the buttons just stay away).
final socialProvidersProvider = FutureProvider<List<SocialProvider>>((
  ref,
) async {
  final Map<String, dynamic> server;
  try {
    server = await ref.read(authApiProvider).providers();
  } catch (_) {
    return const [];
  }
  final phone = ref.read(socialSignInProvider);
  return [
    for (final provider in SocialProvider.values)
      if (server[provider.key] == true && await phone.canUse(provider))
        provider,
  ];
});
