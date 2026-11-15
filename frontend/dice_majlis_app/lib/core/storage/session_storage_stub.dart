class SessionStorage {
  static String? _roomCode;
  static String? _playerId;
  static bool _isHost = false;

  static void save({
    required String roomCode,
    required String playerId,
    bool isHost = false,
  }) {
    _roomCode = roomCode;
    _playerId = playerId;
    _isHost = isHost;
  }

  static ({String roomCode, String playerId, bool isHost})? load() {
    final room = _roomCode;
    final player = _playerId;
    if (room == null || player == null) return null;
    return (roomCode: room, playerId: player, isHost: _isHost);
  }

  static void clear() {
    _roomCode = null;
    _playerId = null;
    _isHost = false;
  }
}

