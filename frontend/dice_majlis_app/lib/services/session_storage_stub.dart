class SessionStorage {
  static String? _roomCode;
  static String? _playerId;

  static void save({required String roomCode, required String playerId}) {
    _roomCode = roomCode;
    _playerId = playerId;
  }

  static ({String roomCode, String playerId})? load() {
    final room = _roomCode;
    final player = _playerId;
    if (room == null || player == null) return null;
    return (roomCode: room, playerId: player);
  }

  static void clear() {
    _roomCode = null;
    _playerId = null;
  }
}

