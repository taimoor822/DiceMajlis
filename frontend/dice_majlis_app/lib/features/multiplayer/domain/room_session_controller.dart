import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/session_storage.dart';
import 'room_session.dart';

/// Holds the current [RoomSession] and keeps the saved copy in step
/// (browser storage on web, memory on phones until accounts arrive).
class RoomSessionController extends Notifier<RoomSession?> {
  @override
  RoomSession? build() {
    final saved = SessionStorage.load();
    if (saved == null) return null;
    return RoomSession(
      roomCode: saved.roomCode,
      playerId: saved.playerId,
      playerToken: saved.playerToken,
      isHost: saved.isHost,
    );
  }

  void start(RoomSession session) {
    SessionStorage.save(
      roomCode: session.roomCode,
      playerId: session.playerId,
      playerToken: session.playerToken,
      isHost: session.isHost,
    );
    state = session;
  }

  void clear() {
    SessionStorage.clear();
    state = null;
  }
}

final roomSessionProvider =
    NotifierProvider<RoomSessionController, RoomSession?>(
      RoomSessionController.new,
    );
