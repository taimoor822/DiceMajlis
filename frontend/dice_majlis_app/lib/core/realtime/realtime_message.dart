import 'dart:convert';

/// The `/ws/v1/` message format (server: `realtime/protocol.py`).
abstract final class RealtimeProtocol {
  static const version = 1;

  /// Close codes the server uses.
  static const closeBadToken = 4401; // refresh the access token, then reconnect
  static const closeForbidden = 4403;
  static const closeAuthTimeout = 4408;
  static const closeRateLimited = 4429; // wait longer before reconnecting

  /// A request: `{"v":1,"type":…,"req_id":…,"data":{…}}`.
  static String encode(String type, String reqId, Map<String, Object?> data) =>
      jsonEncode({'v': version, 'type': type, 'req_id': reqId, 'data': data});
}

/// One message from the server: a reply (`ack`, `error`, `pong`, with
/// [reqId]) or an event on a [channel] (with the game state [version] when
/// there is one).
class RealtimeMessage {
  const RealtimeMessage({
    required this.type,
    this.reqId,
    this.channel,
    this.version,
    this.data = const {},
    this.code,
    this.message,
  });

  /// Null when [text] isn't a server message.
  static RealtimeMessage? tryParse(String text) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (raw is! Map || raw['type'] is! String) return null;
    final data = raw['data'];
    return RealtimeMessage(
      type: raw['type'] as String,
      reqId: raw['req_id'] as String?,
      channel: raw['channel'] as String?,
      version: (raw['version'] as num?)?.toInt(),
      data: data is Map ? Map<String, dynamic>.from(data) : const {},
      code: raw['code'] as String?,
      message: raw['message'] as String?,
    );
  }

  final String type;
  final String? reqId;
  final String? channel;
  final int? version;
  final Map<String, dynamic> data;

  /// Error replies: a stable code (the app switches on it).
  final String? code;
  final String? message;

  bool get isReply => reqId != null && channel == null;
}

/// A request the server refused (its `code`), or one that never got an answer
/// (`disconnected`, `timeout`).
class RealtimeException implements Exception {
  const RealtimeException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() =>
      'RealtimeException($code${message == null ? '' : ': $message'})';
}
