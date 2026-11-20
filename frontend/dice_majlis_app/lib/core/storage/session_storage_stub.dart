/// In-memory session for phones and tests. (Web keeps it in browser storage.)
/// Lasting sessions on phones arrive with accounts, plan step 1.6.
class SessionStorage {
  static String? _roomCode;
  static String? _playerId;
  static String? _playerToken;
  static bool _isHost = false;

  static void save({
    required String roomCode,
    required String playerId,
    required String playerToken,
    bool isHost = false,
  }) {
    _roomCode = roomCode;
    _playerId = playerId;
    _playerToken = playerToken;
    _isHost = isHost;
  }

  static ({String roomCode, String playerId, String playerToken, bool isHost})?
  load() {
    final room = _roomCode;
    final player = _playerId;
    final token = _playerToken;
    if (room == null || player == null || token == null) return null;
    return (
      roomCode: room,
      playerId: player,
      playerToken: token,
      isHost: _isHost,
    );
  }

  static void clear() {
    _roomCode = null;
    _playerId = null;
    _playerToken = null;
    _isHost = false;
  }
}
