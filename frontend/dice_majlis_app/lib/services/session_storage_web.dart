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

  static void save({required String roomCode, required String playerId}) {
    final storage = _localStorage;
    if (storage == null) return;
    storage.setItem(_roomKey.toJS, roomCode.toJS);
    storage.setItem(_playerKey.toJS, playerId.toJS);
  }

  static ({String roomCode, String playerId})? load() {
    final storage = _localStorage;
    if (storage == null) return null;

    final room = storage.getItem(_roomKey.toJS)?.toDart;
    final player = storage.getItem(_playerKey.toJS)?.toDart;

    if (room == null || room.isEmpty || player == null || player.isEmpty) return null;
    return (roomCode: room, playerId: player);
  }

  static void clear() {
    final storage = _localStorage;
    if (storage == null) return;
    storage.removeItem(_roomKey.toJS);
    storage.removeItem(_playerKey.toJS);
  }
}
