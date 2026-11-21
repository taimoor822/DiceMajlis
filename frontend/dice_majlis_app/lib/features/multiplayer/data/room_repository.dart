import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_service.dart';
import '../../../core/realtime/game_sync.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/realtime_message.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../games/domain/game_catalog.dart';
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
    return RollResult.fromJson(await _act(client, 'roll_dice', roomCode));
  }

  @override
  Future<void> moveToken(String roomCode, String tokenId) async {
    final client = _realtime;
    if (client == null) {
      await _api.moveToken(roomCode: roomCode, tokenId: tokenId);
      return;
    }
    await _act(client, 'move_token', roomCode, {'token_id': tokenId});
  }

  /// One game action over the socket. Refusals become [ApiException]s with
  /// the server's code, so screens show them like any other error.
  Future<Map<String, dynamic>> _act(
    RealtimeClient client,
    String type,
    String roomCode, [
    Map<String, Object?> data = const {},
  ]) async {
    final expected = _sync?.version(roomCode);
    try {
      final answer = await client.request(
        type,
        data: {
          'code': roomCode,
          if (expected != null) 'expected_version': expected,
          ...data,
        },
        reqId: client.newRequestId(),
      );
      final version = (answer['version'] as num?)?.toInt();
      if (version != null) _sync?.saw(roomCode, version);
      return answer;
    } on RealtimeException catch (error) {
      // The board was behind: load the whole game again, then the player
      // can act on what is really there.
      if (error.code == 'stale_version') _sync?.requestResync(roomCode);
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
