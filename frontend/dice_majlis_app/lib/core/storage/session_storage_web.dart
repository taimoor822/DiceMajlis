import 'dart:js_interop';

@JS('globalThis.localStorage')
external _Storage? get _localStorage;

extension type _Storage(JSObject _) implements JSObject {
  external void setItem(JSString key, JSString value);
  external JSString? getItem(JSString key);
  external void removeItem(JSString key);
}

class SessionStorage {
  static const _roomKey = 'dice_majlis_room_code';
  static const _playerKey = 'dice_majlis_player_id';
  static const _tokenKey = 'dice_majlis_player_token';
  static const _hostKey = 'dice_majlis_is_host';

  static void save({
    required String roomCode,
    required String playerId,
    required String playerToken,
    bool isHost = false,
  }) {
    final storage = _localStorage;
    if (storage == null) return;
    storage.setItem(_roomKey.toJS, roomCode.toJS);
    storage.setItem(_playerKey.toJS, playerId.toJS);
    storage.setItem(_tokenKey.toJS, playerToken.toJS);
    storage.setItem(_hostKey.toJS, (isHost ? '1' : '0').toJS);
  }

  static ({String roomCode, String playerId, String playerToken, bool isHost})?
  load() {
    final storage = _localStorage;
    if (storage == null) return null;

    final room = storage.getItem(_roomKey.toJS)?.toDart;
    final player = storage.getItem(_playerKey.toJS)?.toDart;
    final token = storage.getItem(_tokenKey.toJS)?.toDart;

    if (room == null || room.isEmpty || player == null || player.isEmpty) return null;
    // A session saved before seat secrets existed can't act any more.
    if (token == null || token.isEmpty) return null;
    final isHost = storage.getItem(_hostKey.toJS)?.toDart == '1';
    return (
      roomCode: room,
      playerId: player,
      playerToken: token,
      isHost: isHost,
    );
  }

  static void clear() {
    final storage = _localStorage;
    if (storage == null) return;
    storage.removeItem(_roomKey.toJS);
    storage.removeItem(_playerKey.toJS);
    storage.removeItem(_tokenKey.toJS);
    storage.removeItem(_hostKey.toJS);
  }
}
