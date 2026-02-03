import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class SocketService {
  late WebSocketChannel channel;

  static String get _wsBaseUrl =>
      kIsWeb ? 'ws://127.0.0.1:8000' : 'ws://10.0.2.2:8000';

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
