import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

/// One open socket. Tests swap in a fake (see `test/helpers/fakes.dart`).
abstract interface class RealtimeConnection {
  /// Text messages from the server; done when the socket closes.
  Stream<String> get messages;

  /// Why the socket closed (after [messages] is done), e.g. 4401.
  int? get closeCode;

  void send(String text);

  Future<void> close();
}

/// Opens a socket to [uri]. Throws when the server can't be reached.
typedef RealtimeConnector = Future<RealtimeConnection> Function(Uri uri);

/// The real socket (package `web_socket_channel`).
class WebSocketRealtimeConnection implements RealtimeConnection {
  WebSocketRealtimeConnection._(this._channel);

  static Future<RealtimeConnection> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    return WebSocketRealtimeConnection._(channel);
  }

  final WebSocketChannel _channel;

  @override
  Stream<String> get messages =>
      _channel.stream.where((message) => message is String).cast<String>();

  @override
  int? get closeCode => _channel.closeCode;

  @override
  void send(String text) => _channel.sink.add(text);

  @override
  Future<void> close() async => _channel.sink.close();
}
