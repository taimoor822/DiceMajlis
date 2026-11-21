import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_exception.dart';
import 'account.dart';
import 'auth_api.dart';
import 'social_sign_in.dart';
import 'token_store.dart';

/// Where sign-in stands.
sealed class AuthState {
  const AuthState();
}

/// Checking the saved sign-in (app start).
final class AuthLoading extends AuthState {
  const AuthLoading();
}

/// The saved sign-in couldn't be checked because the server can't be reached.
/// It is kept; the splash screen offers to try again.
final class AuthOffline extends AuthState {
  const AuthOffline();
}

final class SignedOut extends AuthState {
  const SignedOut();
}

final class SignedIn extends AuthState {
  const SignedIn(this.account);

  final Account account;
}

/// Refresh answers that mean the saved sign-in is gone for good.
const _endedSessionCodes = {
  'invalid_refresh',
  'refresh_expired',
  'session_revoked',
  'invalid_input',
};

/// Signs in, keeps the access token fresh, signs out.
///
/// The access token (15 minutes) lives only in memory. The refresh token is
/// saved in [TokenStore]; every refresh returns a new one, saved straight away.
class AuthController extends Notifier<AuthState> {
  /// Refresh this long before the access token runs out.
  static const refreshEarly = Duration(seconds: 30);

  String? _access;
  DateTime? _accessExpiresAt;
  Future<String?>? _refreshing;

  @override
  AuthState build() => const AuthLoading();

  AuthApi get _api => ref.read(authApiProvider);
  TokenStore get _store => ref.read(tokenStoreProvider);

  /// App start: sign in again with the saved refresh token, if there is one.
  Future<AuthState> restore() async {
    state = const AuthLoading();
    final saved = await _store.readRefreshToken();
    if (saved == null || saved.isEmpty) return state = const SignedOut();
    try {
      await _accept(await _api.refresh(saved));
    } on ApiException catch (error) {
      if (_endedSessionCodes.contains(error.code)) {
        await _forget();
        return state = const SignedOut();
      }
      // No network or server trouble: keep the saved sign-in and try again later.
      return state = const AuthOffline();
    }
    return state;
  }

  /// "Play as guest": a new account with a permanent Player ID.
  Future<void> signInAsGuest() async {
    final tokens = await _api.signInAsGuest(
      deviceId: await _store.deviceId(),
      platform: devicePlatform(),
    );
    await _accept(tokens);
  }

  /// Sign in with email + password.
  Future<void> signInWithEmail(String email, String password) async {
    final tokens = await _api.login(
      email: email.trim(),
      password: password,
      deviceId: await _store.deviceId(),
      platform: devicePlatform(),
    );
    await _accept(tokens);
  }

  /// Sign in with Google or Apple: the phone asks them, the server checks
  /// the answer. Throws [SocialSignInCancelled] when the player backs out.
  Future<void> signInWithProvider(SocialProvider provider) async {
    final credential = await ref
        .read(socialSignInProvider)
        .credential(provider);
    final tokens = await _api.socialSignIn(
      provider: provider.key,
      idToken: credential.idToken,
      nonce: credential.nonce,
      deviceId: await _store.deviceId(),
      platform: devicePlatform(),
    );
    await _accept(tokens);
  }

  /// A new account with email + password.
  Future<void> createAccount(String email, String password) async {
    final tokens = await _api.register(
      email: email.trim(),
      password: password,
      deviceId: await _store.deviceId(),
      platform: devicePlatform(),
    );
    await _accept(tokens);
  }

  /// Forgotten password: set the new one with the emailed code, then sign in.
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _api.confirmPasswordReset(
      email: email.trim(),
      code: code.trim(),
      newPassword: newPassword,
    );
    await signInWithEmail(email, newPassword);
  }

  /// The server sent a newer copy of the account (profile edit, saved account).
  void accountChanged(Account account) {
    if (state is SignedIn) state = SignedIn(account);
  }

  /// An access token for the next request, refreshed first if it is about to
  /// run out. Null when signed out. Throws [ApiException] when offline.
  Future<String?> accessToken() async {
    if (state is! SignedIn) return null;
    final access = _access;
    final expiresAt = _accessExpiresAt;
    if (access != null &&
        expiresAt != null &&
        DateTime.now().isBefore(expiresAt.subtract(refreshEarly))) {
      return access;
    }
    return refreshAccess();
  }

  /// A new access token. Only one refresh runs at a time; everyone waiting
  /// shares it. Returns null (and signs out) if the session has ended.
  Future<String?> refreshAccess() =>
      _refreshing ??= _refreshOnce().whenComplete(() => _refreshing = null);

  Future<String?> _refreshOnce() async {
    final saved = await _store.readRefreshToken();
    if (saved == null || saved.isEmpty) {
      await signOutLocally();
      return null;
    }
    try {
      await _accept(await _api.refresh(saved));
      return _access;
    } on ApiException catch (error) {
      if (_endedSessionCodes.contains(error.code)) {
        await signOutLocally();
        return null;
      }
      rethrow; // offline: this request fails, but the player stays signed in
    }
  }

  Future<void> _accept(AuthTokens tokens) async {
    // Saved first: the old refresh token stopped working on the server.
    await _store.saveRefreshToken(tokens.refresh);
    _access = tokens.access;
    _accessExpiresAt = DateTime.now().add(tokens.accessExpiresIn);
    state = SignedIn(tokens.account);
  }

  /// Signs this device out, on the server too when it can be reached.
  Future<void> signOut() async {
    try {
      final access = await accessToken();
      if (access != null) await _api.signOut(access);
    } on ApiException {
      // Offline: forget the sign-in here anyway.
    }
    await signOutLocally();
  }

  /// The server ended this session (or the player signed out): forget it.
  Future<void> signOutLocally() async {
    await _forget();
    state = const SignedOut();
  }

  Future<void> _forget() async {
    _access = null;
    _accessExpiresAt = null;
    await _store.clearRefreshToken();
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// The signed-in account, or null.
final accountProvider = Provider<Account?>(
  (ref) => switch (ref.watch(authControllerProvider)) {
    SignedIn(:final account) => account,
    _ => null,
  },
);
