import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../domain/room_session.dart';

/// Room actions the screens use. Wraps ApiService so screens get typed
/// results, and tests can swap in a fake through [roomRepositoryProvider].
class RoomRepository {
  const RoomRepository();

  // TODO(1.6 accounts): name and colour come from the player's account.
  Future<RoomSession> createRoom({required int maxPlayers}) async {
    final response = await ApiService.createRoom(
      name: 'Player 1',
      color: 'red',
      maxPlayers: maxPlayers,
    );
    return RoomSession.fromRoomResponse(response);
  }

  Future<RoomSession> joinRoom(String code) async {
    final response = await ApiService.joinRoom(
      code: code,
      name: 'Player',
      color: 'blue',
    );
    return RoomSession.fromRoomResponse(response);
  }

  Future<void> startGame(RoomSession session) =>
      ApiService.startGame(code: session.roomCode, playerId: session.playerId);
}

final roomRepositoryProvider = Provider<RoomRepository>(
  (ref) => const RoomRepository(),
);
