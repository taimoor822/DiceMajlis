import 'dart:async';
import 'dart:convert';

import '../websocket/socket_service.dart';
import 'game_sync.dart';
import 'realtime_client.dart';
import 'realtime_message.dart';
import 'realtime_providers.dart';

/// A room's updates over the app's one live connection (`/ws/v1/`), in the
/// message shapes the room screens already read (see [SocketService]):
///
/// - `room/<room id>`: `players_updated`, and `game_started` when it starts;
/// - `game/<game id>`: the game's events, each with its state `version`.
///
/// Versions keep the board right: an event the board already has is dropped,
/// and a gap (a missed event) loads the whole state again (`request_state`),
/// which reaches the screen as `game_started`. Snapshots of the same version
/// as the board's are not sent twice.
class RealtimeRoomSocket implements SocketService {
  RealtimeRoomSocket(this._client, {required GameSync sync}) : _sync = sync;

  final RealtimeClient _client;
  final GameSync _sync;
  final _out = StreamController<dynamic>.broadcast(sync: true);

  String? _roomCode;
  String? _roomId;
  String? _gameId;
  StreamSubscription<RealtimeMessage>? _room;
  StreamSubscription<RealtimeMessage>? _game;
  StreamSubscription<String>? _resyncRequests;

  /// The game version the screen has drawn (null: nothing drawn yet).
  int? _version;

  /// The newest version any game message mentioned (dropped ones included).
  int _newestSeen = -1;

  /// True while the screen shows a snapshot with no event applied since.
  bool _fromSnapshot = false;
  bool _resyncing = false;
  bool _closed = false;

  @override
  Stream<dynamic> get stream => _out.stream;

  @override
  void connect(String roomCode, {String? roomId}) {
    _roomCode = roomCode;
    _resyncRequests = _sync.resyncRequests
        .where((code) => code == roomCode)
        .listen((_) => _resync(force: true));
    if (roomId != null) _listenRoom(roomId);
    // The current state, even when another screen already listens to the
    // same channels (a shared channel sends its first events only once).
    _resync();
  }

  @override
  void disconnect() {
    _closed = true;
    // Not awaited (a broadcast cancel can finish outside a test's fake clock).
    unawaited(_room?.cancel());
    unawaited(_game?.cancel());
    unawaited(_resyncRequests?.cancel());
    unawaited(_out.close());
  }

  void _listenRoom(String roomId) {
    if (_roomId == roomId || _closed) return;
    unawaited(_room?.cancel());
    _roomId = roomId;
    _room = _client.channel(RealtimeChannels.room(roomId)).listen(_onRoom);
  }

  void _listenGame(String gameId) {
    if (_gameId == gameId || _closed) return;
    unawaited(_game?.cancel());
    // Another game in this room (a rematch): its versions start again.
    _gameId = gameId;
    _version = null;
    _newestSeen = -1;
    _fromSnapshot = false;
    _game = _client.channel(RealtimeChannels.game(gameId)).listen(_onGame);
  }

  void _onRoom(RealtimeMessage message) {
    switch (message.type) {
      case 'players_updated':
        _emit({'type': 'players_updated', ...message.data});
      case 'game_started':
        _onSnapshot(message.data);
    }
  }

  void _onGame(RealtimeMessage message) {
    if (message.type == 'state_snapshot') {
      _onSnapshot(message.data);
      return;
    }
    final version = message.version;
    if (version != null && version > _newestSeen) _newestSeen = version;
    final drawn = _version;
    // Nothing drawn yet, or a full state is on its way: that state covers it.
    if (drawn == null || _resyncing) return;
    if (version != null) {
      if (version < drawn) return; // already on the board
      if (version > drawn + 1) {
        _resync(force: true); // missed at least one action
        return;
      }
      _version = version;
      _sync.saw(_roomCode!, version);
    }
    _fromSnapshot = false;
    _emit({
      'type': message.type,
      ...message.data,
      if (version != null) 'version': version,
    });
  }

  /// A whole state (`game_started` / `state_snapshot` / `request_state`).
  void _onSnapshot(Map<String, dynamic> data, {bool force = false}) {
    final roomId = data['room_id']?.toString();
    if (roomId != null) _listenRoom(roomId);
    final gameId = data['game_id']?.toString();
    if (gameId == null) {
      // Not started: only who is seated.
      if (data['players'] is List) {
        _emit({'type': 'players_updated', 'players': data['players']});
      }
      return;
    }
    _listenGame(gameId);
    final version = (data['version'] as num?)?.toInt();
    final drawn = _version;
    if (version != null && drawn != null) {
      if (version < drawn) return; // older than the board
      if (version == drawn && _fromSnapshot && !force) return; // same picture
    }
    if (version != null) {
      _version = version;
      _sync.reset(_roomCode!, version);
    }
    _fromSnapshot = true;
    _emit({...data, 'type': 'game_started'});
    // Events newer than this state went by before it: load again.
    if (version != null && version < _newestSeen) _resync(force: true);
  }

  Future<void> _resync({bool force = false}) async {
    if (_resyncing || _closed) return;
    _resyncing = true;
    try {
      final data = await _client.request(
        'request_state',
        data: {'code': _roomCode},
      );
      _resyncing = false;
      if (!_closed) _onSnapshot(data, force: force);
    } on RealtimeException {
      // Offline or refused: the next event or reconnection brings the state.
      _resyncing = false;
    }
  }

  void _emit(Map<String, dynamic> message) {
    if (!_closed) _out.add(jsonEncode(message));
  }
}
