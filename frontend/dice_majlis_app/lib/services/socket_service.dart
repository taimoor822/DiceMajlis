import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class SocketService {
  late WebSocketChannel channel;

  void connect(String roomCode) {
    channel = WebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:8000/ws/lobby/$roomCode/'),
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
