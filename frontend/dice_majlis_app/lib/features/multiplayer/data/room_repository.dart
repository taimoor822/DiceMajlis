import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
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
  Future<RoomOptions> roomOptions();
  Future<RoomSession> createRoom({required int maxPlayers});
  Future<RoomSession> joinRoom(String code);
  Future<void> startGame(String roomCode);
  Future<RollResult> rollDice(String roomCode);
  Future<void> moveToken(String roomCode, String tokenId);

  /// Before the start: frees your seat. During a game: you forfeit.
  Future<void> leaveRoom(String roomCode);
}

/// [RoomRepository] on the real server.
class ApiRoomRepository implements RoomRepository {
  const ApiRoomRepository(this._api);

  final ApiService _api;

  @override
  Future<RoomOptions> roomOptions() async =>
      RoomOptions.fromJson(await _api.roomOptions());

  @override
  Future<RoomSession> createRoom({required int maxPlayers}) async =>
      RoomSession.fromRoomResponse(
        await _api.createRoom(maxPlayers: maxPlayers),
      );

  @override
  Future<RoomSession> joinRoom(String code) async =>
      RoomSession.fromRoomResponse(await _api.joinRoom(code: code));

  @override
  Future<void> startGame(String roomCode) => _api.startGame(roomCode: roomCode);

  @override
  Future<RollResult> rollDice(String roomCode) async =>
      RollResult.fromJson(await _api.rollDice(roomCode: roomCode));

  @override
  Future<void> moveToken(String roomCode, String tokenId) =>
      _api.moveToken(roomCode: roomCode, tokenId: tokenId);

  @override
  Future<void> leaveRoom(String roomCode) => _api.leaveRoom(roomCode: roomCode);
}

final roomRepositoryProvider = Provider<RoomRepository>(
  (ref) => ApiRoomRepository(ref.watch(apiServiceProvider)),
);

/// The create-room choices, loaded from the server once per visit to the
/// create screen.
final roomOptionsProvider = FutureProvider.autoDispose<RoomOptions>(
  (ref) => ref.watch(roomRepositoryProvider).roomOptions(),
);
