import 'dart:async';
import 'dart:convert';

import 'package:dice_majlis_app/app.dart';
import 'package:dice_majlis_app/core/network/api_exception.dart';
import 'package:dice_majlis_app/core/storage/session_storage.dart';
import 'package:dice_majlis_app/core/websocket/socket_providers.dart';
import 'package:dice_majlis_app/core/websocket/socket_service.dart';
import 'package:dice_majlis_app/features/multiplayer/data/room_repository.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Room API without a server. Records calls; [failWith] makes every call fail
/// with that server error code (e.g. `room_full`, `network_error`).
class FakeRoomRepository extends RoomRepository {
  FakeRoomRepository({
    this.failWith,
    this.options = const RoomOptions(
      playerCounts: [2, 3, 4],
      defaultPlayerCount: 4,
    ),
  });

  String? failWith;
  RoomOptions options;
  final calls = <String>[];

  void _maybeFail() {
    final code = failWith;
    if (code != null) throw ApiException(code);
  }

  RoomSession _session(String code, {required bool host, int? maxPlayers}) =>
      RoomSession(
        roomCode: code,
        playerId: host ? 'p-host' : 'p-guest',
        playerToken: host ? 'secret-host' : 'secret-guest',
        isHost: host,
        maxPlayers: maxPlayers,
        self: RoomPlayer(
          id: host ? 'p-host' : 'p-guest',
          name: host ? 'Player 1' : 'Player',
          color: host ? 'red' : 'blue',
          isHost: host,
        ),
      );

  @override
  Future<RoomOptions> roomOptions() async {
    calls.add('options');
    _maybeFail();
    return options;
  }

  @override
  Future<RoomSession> createRoom({required int maxPlayers}) async {
    calls.add('create:$maxPlayers');
    _maybeFail();
    return _session('AB12', host: true, maxPlayers: maxPlayers);
  }

  @override
  Future<RoomSession> joinRoom(String code) async {
    calls.add('join:$code');
    _maybeFail();
    return _session(code, host: false, maxPlayers: 4);
  }

  @override
  Future<void> startGame(RoomSession session) async {
    calls.add('start:${session.roomCode}');
    _maybeFail();
  }
}

/// A socket the test drives by hand: [emit] plays a server message.
class FakeSocketService extends SocketService {
  // sync: a message reaches the screen as soon as the test emits it.
  final _controller = StreamController<dynamic>.broadcast(sync: true);
  String? connectedRoom;
  bool disconnected = false;

  @override
  void connect(String roomCode) => connectedRoom = roomCode;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void disconnect() => disconnected = true;

  void emit(Map<String, dynamic> message) =>
      _controller.add(jsonEncode(message));
}

/// Every socket the app opened, newest last.
class FakeSockets {
  final opened = <FakeSocketService>[];
  FakeSocketService get last => opened.last;

  FakeSocketService create() {
    final socket = FakeSocketService();
    opened.add(socket);
    return socket;
  }
}

/// Provider overrides that swap the network for fakes.
List<Override> fakeNetwork({
  required FakeRoomRepository repository,
  required FakeSockets sockets,
}) => [
  roomRepositoryProvider.overrideWithValue(repository),
  socketServiceFactoryProvider.overrideWithValue(sockets.create),
];

/// The whole app with fakes in place of the network. [overrides] adds more
/// (e.g. settings storage).
Widget testApp({
  required FakeRoomRepository repository,
  required FakeSockets sockets,
  List<Override> overrides = const [],
}) {
  SessionStorage.clear();
  return ProviderScope(
    overrides: [
      ...fakeNetwork(repository: repository, sockets: sockets),
      ...overrides,
    ],
    child: const DiceMajlisApp(),
  );
}
