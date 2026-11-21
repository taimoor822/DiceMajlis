import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_service.dart';
import '../../../core/realtime/game_sync.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/realtime_message.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../games/domain/game_catalog.dart';
import '../domain/room_info.dart';
import '../domain/room_session.dart';

/// What the server allows when creating a room.
class RoomOptions {
  const RoomOptions({
    required this.playerCounts,
    required this.defaultPlayerCount,
  });

  factory RoomOptions.fromJson(Map<String, dynamic> json) {
    final counts = (json['player_counts'] as List)
        .map((count) => (count as num).toInt())
        .toList(growable: false);
    final fallback = counts.isEmpty ? 0 : counts.last;
    final preferred = json['default_player_count'];
    final defaultCount = preferred is num && counts.contains(preferred.toInt())
        ? preferred.toInt()
        : fallback;
    return RoomOptions(playerCounts: counts, defaultPlayerCount: defaultCount);
  }

  final List<int> playerCounts;
  final int defaultPlayerCount;
}

/// The server's answer to a roll.
class RollResult {
  const RollResult({required this.dice, required this.movableTokenIds});

  factory RollResult.fromJson(Map<String, dynamic> json) => RollResult(
    dice: (json['dice'] as num?)?.toInt(),
    movableTokenIds: [
      for (final id in (json['movable_token_ids'] as List? ?? const []))
        id.toString(),
    ],
  );

  final int? dice;

  /// The only tokens that may move with this roll (the server decides).
  final List<String> movableTokenIds;
}

/// Room actions the screens use, signed in as the current account (the
/// server finds your seat from it). Tests swap in a fake through
/// [roomRepositoryProvider].
abstract class RoomRepository {
  Future<RoomOptions> roomOptions(GameChoice game);
  Future<RoomSession> createRoom({
    required int maxPlayers,
    required GameChoice game,
  });
  Future<RoomSession> joinRoom(String code);
  Future<void> startGame(String roomCode);
  Future<RollResult> rollDice(String roomCode);
  Future<void> moveToken(String roomCode, String tokenId);

  /// Before the start: frees your seat. During a game: you forfeit.
  Future<void> leaveRoom(String roomCode);

  // ---- private rooms (1.13): over the live connection ----

  /// Guests only: ready (or not) to play.
  Future<void> setReady(String roomCode, {required bool ready});

  /// Host: removes a player before the start; they can't come back unless
  /// invited again.
  Future<void> kickPlayer(String roomCode, String playerId);

  /// Host: a locked room takes invited players only.
  Future<void> lockRoom(String roomCode, {required bool locked});

  /// Host: passes the host role to [playerId].
  Future<void> transferHost(String roomCode, String playerId);

  /// Host: picks the custom rules (from the choices the server offers).
  Future<void> changeRules(String roomCode, Map<String, Object?> options);

  /// Invites the account with this 9-digit Player ID.
  Future<void> invitePlayer(String roomCode, int playerId);

  Future<void> declineInvite(String roomCode);

  /// Invites to rooms the account can still join.
  Future<List<RoomInvite>> invites();

  /// After the game: asks (or stops asking) to play again.
  Future<RematchAnswer> rematch(String roomCode, {required bool want});
}

/// [RoomRepository] on the real server. Game actions (roll, move) go over the
/// live connection when there is one, with the version the board shows
/// ([GameSync]); everything else uses the REST API.
class ApiRoomRepository implements RoomRepository {
  const ApiRoomRepository(this._api, {RealtimeClient? realtime, GameSync? sync})
    : _realtime = realtime,
      _sync = sync;

  final ApiService _api;
  final RealtimeClient? _realtime;
  final GameSync? _sync;

  @override
  Future<RoomOptions> roomOptions(GameChoice game) async =>
      RoomOptions.fromJson(
        await _api.roomOptions(gameType: game.gameType, variant: game.variant),
      );

  @override
  Future<RoomSession> createRoom({
    required int maxPlayers,
    required GameChoice game,
  }) async => RoomSession.fromRoomResponse(
    await _api.createRoom(
      maxPlayers: maxPlayers,
      gameType: game.gameType,
      variant: game.variant,
    ),
  );

  @override
  Future<RoomSession> joinRoom(String code) async =>
      RoomSession.fromRoomResponse(await _api.joinRoom(code: code));

  @override
  Future<void> startGame(String roomCode) => _api.startGame(roomCode: roomCode);

  @override
  Future<RollResult> rollDice(String roomCode) async {
    final client = _realtime;
    if (client == null) {
      return RollResult.fromJson(await _api.rollDice(roomCode: roomCode));
    }
    return RollResult.fromJson(await _game(client, 'roll_dice', roomCode));
  }

  @override
  Future<void> moveToken(String roomCode, String tokenId) async {
    final client = _realtime;
    if (client == null) {
      await _api.moveToken(roomCode: roomCode, tokenId: tokenId);
      return;
    }
    await _game(client, 'move_token', roomCode, {'token_id': tokenId});
  }

  /// One game action over the socket, with the version the board shows.
  Future<Map<String, dynamic>> _game(
    RealtimeClient client,
    String type,
    String roomCode, [
    Map<String, Object?> data = const {},
  ]) async {
    final expected = _sync?.version(roomCode);
    try {
      final answer = await _ask(type, {
        'code': roomCode,
        if (expected != null) 'expected_version': expected,
        ...data,
      }, client: client);
      final version = (answer['version'] as num?)?.toInt();
      if (version != null) _sync?.saw(roomCode, version);
      return answer;
    } on ApiException catch (error) {
      // The board was behind: load the whole game again, then the player
      // can act on what is really there.
      if (error.code == 'stale_version') _sync?.requestResync(roomCode);
      rethrow;
    }
  }

  /// One request over the socket. Refusals become [ApiException]s with the
  /// server's code, so screens show them like any other error.
  Future<Map<String, dynamic>> _ask(
    String type,
    Map<String, Object?> data, {
    RealtimeClient? client,
  }) async {
    final socket = client ?? _realtime;
    if (socket == null) throw const ApiException(ApiException.networkError);
    try {
      return await socket.request(
        type,
        data: data,
        reqId: socket.newRequestId(),
      );
    } on RealtimeException catch (error) {
      throw ApiException(
        switch (error.code) {
          'disconnected' || 'timeout' => ApiException.networkError,
          final code => code,
        },
        serverMessage: error.message,
      );
    }
  }

  @override
  Future<void> leaveRoom(String roomCode) => _api.leaveRoom(roomCode: roomCode);

  @override
  Future<void> setReady(String roomCode, {required bool ready}) =>
      _ask('set_ready', {'code': roomCode, 'ready': ready});

  @override
  Future<void> kickPlayer(String roomCode, String playerId) =>
      _ask('kick_player', {'code': roomCode, 'player_id': playerId});

  @override
  Future<void> lockRoom(String roomCode, {required bool locked}) =>
      _ask('lock_room', {'code': roomCode, 'locked': locked});

  @override
  Future<void> transferHost(String roomCode, String playerId) =>
      _ask('transfer_host', {'code': roomCode, 'player_id': playerId});

  @override
  Future<void> changeRules(String roomCode, Map<String, Object?> options) =>
      _ask('room_settings', {'code': roomCode, 'options': options});

  @override
  Future<void> invitePlayer(String roomCode, int playerId) =>
      _ask('invite_player', {'code': roomCode, 'player_id': playerId});

  @override
  Future<void> declineInvite(String roomCode) =>
      _ask('decline_invite', {'code': roomCode});

  @override
  Future<List<RoomInvite>> invites() async {
    final answer = await _api.roomInvites();
    return [
      for (final invite in answer['invites'] as List? ?? const [])
        RoomInvite.fromJson(Map<String, dynamic>.from(invite as Map)),
    ];
  }

  @override
  Future<RematchAnswer> rematch(String roomCode, {required bool want}) async =>
      RematchAnswer.fromJson(
        await _ask('rematch', {'code': roomCode, 'want': want}),
      );
}

final roomRepositoryProvider = Provider<RoomRepository>(
  (ref) => ApiRoomRepository(
    ref.watch(apiServiceProvider),
    realtime: ref.watch(realtimeClientProvider),
    sync: ref.watch(gameSyncProvider),
  ),
);

/// The create-room choices for a game and variant, loaded from the server once
/// per visit to the create screen.
final roomOptionsProvider = FutureProvider.autoDispose
    .family<RoomOptions, GameChoice>(
      (ref, game) => ref.watch(roomRepositoryProvider).roomOptions(game),
    );
