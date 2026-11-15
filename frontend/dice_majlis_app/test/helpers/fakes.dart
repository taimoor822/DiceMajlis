import 'dart:async';
import 'dart:convert';

import 'package:dice_majlis_app/app.dart';
import 'package:dice_majlis_app/core/storage/session_storage.dart';
import 'package:dice_majlis_app/core/websocket/socket_providers.dart';
import 'package:dice_majlis_app/core/websocket/socket_service.dart';
import 'package:dice_majlis_app/features/multiplayer/data/room_repository.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Room API without a server. Records calls; can be told to fail.
class FakeRoomRepository extends RoomRepository {
  FakeRoomRepository({this.fail = false});

  bool fail;
  final calls = <String>[];

  RoomSession _session(String code, {required bool host, int? maxPlayers}) =>
      RoomSession(
        roomCode: code,
        playerId: host ? 'p-host' : 'p-guest',
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
  Future<RoomSession> createRoom({required int maxPlayers}) async {
    calls.add('create:$maxPlayers');
    if (fail) throw Exception('offline');
    return _session('AB12', host: true, maxPlayers: maxPlayers);
  }

  @override
  Future<RoomSession> joinRoom(String code) async {
    calls.add('join:$code');
    if (fail) throw Exception('offline');
    return _session(code, host: false, maxPlayers: 4);
  }

  @override
  Future<void> startGame(RoomSession session) async {
    calls.add('start:${session.roomCode}');
    if (fail) throw Exception('offline');
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
  void startGame() {}

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

/// The whole app with fakes in place of the network.
Widget testApp({
  required FakeRoomRepository repository,
  required FakeSockets sockets,
}) {
  SessionStorage.clear();
  return ProviderScope(
    overrides: [
      roomRepositoryProvider.overrideWithValue(repository),
      socketServiceFactoryProvider.overrideWithValue(sockets.create),
    ],
    child: const DiceMajlisApp(),
  );
}
