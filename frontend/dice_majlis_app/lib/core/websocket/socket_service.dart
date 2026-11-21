import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';

/// A room's live updates for the room screens, as JSON text with `type` on
/// top: `players_updated`, `game_started` (the whole state) and the game's
/// events (`dice_rolled`, `token_moved`, … each with its `version`).
///
/// The app uses `RealtimeRoomSocket` (the `/ws/v1/` connection);
/// [LobbySocketService] is only for when there is no live connection.
abstract class SocketService {
  /// [roomId] is the room's server id (it names the `room/` channel).
  void connect(String roomCode, {String? roomId});

  Stream<dynamic> get stream;

  void disconnect();
}

/// The old read-only lobby socket (`/ws/lobby/<code>/`). Deprecated: the
/// server still feeds it, but the app talks over `/ws/v1/` since step 1.12.
class LobbySocketService implements SocketService {
  late WebSocketChannel channel;

  static String get _wsBaseUrl => AppConfig.webSocketUrl;

  @override
  void connect(String roomCode, {String? roomId}) {
    channel = WebSocketChannel.connect(
      Uri.parse('$_wsBaseUrl/ws/lobby/$roomCode/'),
    );
  }

  @override
  Stream<dynamic> get stream => channel.stream;

  @override
  void disconnect() {
    channel.sink.close();
  }
}
