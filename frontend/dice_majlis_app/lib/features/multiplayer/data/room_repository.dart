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

/// Room actions the screens use. Wraps ApiService so screens get typed
/// results, and tests can swap in a fake through [roomRepositoryProvider].
///
/// The server picks each player's name and seat colour.
// TODO(1.6 accounts / 1.7 profile): send the player's own name.
class RoomRepository {
  const RoomRepository();

  Future<RoomOptions> roomOptions() async =>
      RoomOptions.fromJson(await ApiService.roomOptions());

  Future<RoomSession> createRoom({required int maxPlayers}) async =>
      RoomSession.fromRoomResponse(
        await ApiService.createRoom(maxPlayers: maxPlayers),
      );

  Future<RoomSession> joinRoom(String code) async =>
      RoomSession.fromRoomResponse(await ApiService.joinRoom(code: code));

  Future<void> startGame(RoomSession session) => ApiService.startGame(
    roomCode: session.roomCode,
    playerId: session.playerId,
    playerToken: session.playerToken,
  );
}

final roomRepositoryProvider = Provider<RoomRepository>(
  (ref) => const RoomRepository(),
);

/// The create-room choices, loaded from the server once per visit to the
/// create screen.
final roomOptionsProvider = FutureProvider.autoDispose<RoomOptions>(
  (ref) => ref.watch(roomRepositoryProvider).roomOptions(),
);
