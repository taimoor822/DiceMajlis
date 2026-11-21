import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../config/app_config.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';

/// Raw calls to the game REST API, signed in as the current account. Returns
/// the server's JSON; the feature repositories turn it into typed objects.
/// Every failure is an [ApiException].
///
/// The app only asks ("create a room", "roll", "move this token"). Sizes,
/// dice, positions, names and colours are decided by the server, and the
/// server finds your seat from your account.
class ApiService {
  ApiService(AuthController auth, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.apiUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'Content-Type': 'application/json'},
            ),
          ) {
    _dio.interceptors.add(
      AuthInterceptor(
        accessToken: auth.accessToken,
        refreshAccess: auth.refreshAccess,
        onSessionEnded: auth.signOutLocally,
        retry: _dio.fetch,
      ),
    );
  }

  final Dio _dio;

  Future<Map<String, dynamic>> _send(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        options: Options(method: method),
      );
      final body = response.data;
      if (body is Map) return Map<String, dynamic>.from(body);
      throw ApiException(
        ApiException.unknownError,
        statusCode: response.statusCode,
      );
    } on DioException catch (error) {
      final cause = error.error;
      final failure = cause is ApiException
          ? cause
          : ApiException.fromDio(error);
      debugPrint('$method $path failed: $failure');
      throw failure;
    }
  }

  /// Every game and variant the server can run (its game registry).
  Future<Map<String, dynamic>> gameCatalog() => _send('GET', 'game/catalog/');

  /// What the server allows when creating a room for a game and variant
  /// (e.g. the player counts).
  Future<Map<String, dynamic>> roomOptions({
    required String gameType,
    required String variant,
  }) => _send(
    'GET',
    Uri(
      path: 'game/room-options/',
      queryParameters: {'game_type': gameType, 'variant': variant},
    ).toString(),
  );

  Future<Map<String, dynamic>> createRoom({
    required int maxPlayers,
    required String gameType,
    required String variant,
  }) => _send('POST', 'game/create-room/', {
    'max_players': maxPlayers,
    'game_type': gameType,
    'variant': variant,
  });

  Future<Map<String, dynamic>> joinRoom({required String code}) =>
      _send('POST', 'game/join-room/', {'code': code});

  Future<Map<String, dynamic>> startGame({required String roomCode}) =>
      _send('POST', 'game/start-game/', {'code': roomCode});

  Future<Map<String, dynamic>> rollDice({required String roomCode}) =>
      _send('POST', 'game/roll-dice/', {'code': roomCode});

  Future<Map<String, dynamic>> moveToken({
    required String roomCode,
    required String tokenId,
  }) => _send('POST', 'game/move-token/', {
    'code': roomCode,
    'token_id': tokenId,
  });

  /// Before the start: frees your seat. During a game: you forfeit.
  Future<Map<String, dynamic>> leaveRoom({required String roomCode}) =>
      _send('POST', 'game/leave-room/', {'code': roomCode});

  /// Invites to rooms you can still join (by Player ID).
  Future<Map<String, dynamic>> roomInvites() => _send('GET', 'game/invites/');

  /// What a profile may hold (avatars, languages, name length).
  Future<Map<String, dynamic>> profileOptions() =>
      _send('GET', 'profile/options/');

  /// Changes your own profile; returns your account.
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> changes) =>
      _send('PATCH', 'me/profile/', changes);

  /// Your balances: `{"balances": {"gold": n, "diamond": n}}`.
  Future<Map<String, dynamic>> wallet() => _send('GET', 'wallet/');

  /// Your statistics from real online games, and your latest results.
  Future<Map<String, dynamic>> myStats() => _send('GET', 'me/stats/');

  /// Your achievements, with progress and rewards.
  Future<Map<String, dynamic>> myAchievements() =>
      _send('GET', 'me/achievements/');

  /// What you own and wear (cosmetics today).
  Future<Map<String, dynamic>> myItems() => _send('GET', 'me/items/');

  /// Wear [item] in [slot]; null puts the slot back to its default.
  Future<Map<String, dynamic>> equipItem(String slot, String? item) =>
      _send('POST', 'me/items/equip/', {'slot': slot, 'item': item});

  /// Your ledger, newest first; [before] is the last id of the previous page.
  Future<Map<String, dynamic>> walletTransactions({String? before}) => _send(
    'GET',
    before == null
        ? 'wallet/transactions/'
        : 'wallet/transactions/?before=$before',
  );

  /// Today's daily reward: day in the cycle, claimed or not, the 7 days.
  Future<Map<String, dynamic>> dailyReward() => _send('GET', 'rewards/daily/');

  /// Claims today's reward. The server decides what it is.
  Future<Map<String, dynamic>> claimDailyReward() =>
      _send('POST', 'rewards/daily/claim/');

  /// A guest adds email + password; returns the account (same Player ID).
  Future<Map<String, dynamic>> saveAccount({
    required String email,
    required String password,
  }) => _send('POST', 'auth/save-account/', {
    'email': email,
    'password': password,
  });

  /// Attach Google or Apple ([provider]) to the signed-in account.
  Future<Map<String, dynamic>> linkSocial({
    required String provider,
    required String idToken,
    String? nonce,
  }) => _send('POST', 'me/link/$provider/', {
    'id_token': idToken,
    'nonce': ?nonce,
  });

  /// Detach Google or Apple (refused if it is the only way to sign in).
  Future<Map<String, dynamic>> unlinkSocial(String provider) =>
      _send('POST', 'me/unlink/$provider/');
}

final apiServiceProvider = Provider<ApiService>(
  (ref) => ApiService(ref.read(authControllerProvider.notifier)),
);
