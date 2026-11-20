import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';

/// Listens to a room's updates. Read-only: players act through the REST API,
/// which checks their seat secret.
class SocketService {
  late WebSocketChannel channel;

  static String get _wsBaseUrl => AppConfig.webSocketUrl;

  void connect(String roomCode) {
    channel = WebSocketChannel.connect(
      Uri.parse('$_wsBaseUrl/ws/lobby/$roomCode/'),
    );
  }

  Stream<dynamic> get stream => channel.stream;

  void disconnect() {
    channel.sink.close();
  }
}
