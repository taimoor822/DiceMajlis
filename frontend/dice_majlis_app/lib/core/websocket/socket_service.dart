import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';

class SocketService {
  late WebSocketChannel channel;

  static String get _wsBaseUrl => AppConfig.webSocketUrl;

  void connect(String roomCode) {
    channel = WebSocketChannel.connect(
      Uri.parse('$_wsBaseUrl/ws/lobby/$roomCode/'),
    );
  }

  Stream<dynamic> get stream => channel.stream;

  void startGame() {
    channel.sink.add(jsonEncode({'type': 'start_game'}));
  }

  void disconnect() {
    channel.sink.close();
  }
}
