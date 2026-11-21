import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'realtime_connection.dart';
import 'realtime_message.dart';

/// Where the live connection stands.
enum RealtimeStatus { offline, connecting, online }

/// Waiting times of [RealtimeClient] (tests use shorter ones).
class RealtimeTiming {
  const RealtimeTiming({
    this.firstRetry = const Duration(seconds: 1),
    this.maxRetry = const Duration(seconds: 30),
    this.requestTimeout = const Duration(seconds: 10),
    this.heartbeat = const Duration(seconds: 20),
  });

  /// After a lost connection: 1 s, 2 s, 4 s … up to [maxRetry], with jitter.
  final Duration firstRetry;
  final Duration maxRetry;

  /// A request without an answer in this time fails with `timeout`.
  final Duration requestTimeout;

  /// Ping interval until the server says its own (`heartbeat_seconds`).
  final Duration heartbeat;
}

/// The app's one live connection to the server (`/ws/v1/`).
///
/// - Signs in with the access token as the first message; when the server
///   says the token is bad (close 4401) it gets a fresh one and reconnects.
/// - Pings every 20 s; two pings without an answer = the connection is dead.
/// - Reconnects by itself (1 s, 2 s, 4 s … 30 s) and subscribes again to every
///   channel that is still listened to.
///
/// Features listen to channels with [channel] and ask with [request]; they
/// never see the socket. The server decides everything (rule 1): the app only
/// asks and listens.
class RealtimeClient {
  RealtimeClient({
    required RealtimeConnector connect,
    required Uri uri,
    required Future<String?> Function() accessToken,
    required Future<String?> Function() refreshAccess,
    this.timing = const RealtimeTiming(),
    Random? random,
  }) : _connect = connect,
       _uri = uri,
       _accessToken = accessToken,
       _refreshAccess = refreshAccess,
       _random = random ?? Random.secure() {
    _idPrefix = _random.nextInt(1 << 30).toRadixString(36);
  }

  final RealtimeConnector _connect;
  final Uri _uri;
  final Future<String?> Function() _accessToken;
  final Future<String?> Function() _refreshAccess;
  final Random _random;
  final RealtimeTiming timing;

  /// Offline / connecting / online (for "reconnecting…" hints later).
  final status = ValueNotifier(RealtimeStatus.offline);

  late final String _idPrefix;
  int _nextId = 0;

  bool _running = false;
  RealtimeConnection? _connection;
  StreamSubscription<String>? _listening;
  bool _signedIn = false;
  bool _freshTokenNeeded = false;
  int _attempt = 0;
  Timer? _retryTimer;
  Timer? _heartbeatTimer;
  int _unansweredPings = 0;
  final _pending = <String, _PendingRequest>{};
  final _channels = <String, StreamController<RealtimeMessage>>{};

  /// The newest version seen per channel: after a reconnect the subscription
  /// says `since`, so a channel that can (games) sends only what was missed.
  final _versions = <String, int>{};

  static const _tokenCodes = {'invalid_token', 'token_expired'};

  /// Connects and stays connected until [stop].
  void start() {
    if (_running) return;
    _running = true;
    _open();
  }

  /// Closes the connection for good (sign-out, or the app closing).
  Future<void> stop() async {
    _running = false;
    _retryTimer?.cancel();
    final connection = _connection;
    _detach();
    status.value = RealtimeStatus.offline;
    for (final controller in _channels.values) {
      unawaited(controller.close());
    }
    _channels.clear();
    _versions.clear();
    await connection?.close();
  }

  /// Events on [name] (e.g. `user/123456789`). Subscribes while someone
  /// listens, again after every reconnect, and unsubscribes when the last
  /// listener cancels. The first events are the channel's current state.
  Stream<RealtimeMessage> channel(String name) {
    final existing = _channels[name];
    if (existing != null) return existing.stream;
    late final StreamController<RealtimeMessage> controller;
    controller = StreamController<RealtimeMessage>.broadcast(
      onListen: () => _subscribe(name),
      onCancel: () {
        if (_channels[name] != controller) return;
        _channels.remove(name);
        _versions.remove(name);
        _unsubscribe(name);
        unawaited(controller.close());
      },
    );
    _channels[name] = controller;
    return controller.stream;
  }

  /// Asks the server; completes with the `ack` data or throws
  /// [RealtimeException] (the server's code, `disconnected` or `timeout`).
  /// Pass the same [reqId] again to retry a request that changes something:
  /// the server answers it once.
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, Object?> data = const {},
    String? reqId,
  }) {
    final connection = _connection;
    if (connection == null || !_signedIn) {
      return Future.error(const RealtimeException('disconnected'));
    }
    return _send(connection, type, data, reqId: reqId);
  }

  /// A new request id (unique for this app run).
  String newRequestId() => '$_idPrefix-${_nextId++}';

  // ---- connecting --------------------------------------------------------------

  Future<void> _open() async {
    if (!_running) return;
    status.value = RealtimeStatus.connecting;
    final String? token;
    final RealtimeConnection connection;
    try {
      token = _freshTokenNeeded ? await _refreshAccess() : await _accessToken();
    } on Object {
      _retryLater(); // offline: try again later
      return;
    }
    if (!_running) return;
    if (token == null) {
      unawaited(stop()); // signed out
      return;
    }
    _freshTokenNeeded = false;
    try {
      connection = await _connect(_uri);
    } on Object {
      _retryLater();
      return;
    }
    if (!_running) {
      unawaited(connection.close());
      return;
    }

    _connection = connection;
    _signedIn = false;
    _listening = connection.messages.listen(
      _onMessage,
      onError: (Object _) {},
      onDone: () => _onClosed(connection),
    );

    try {
      final hello = await _send(connection, 'auth', {'access_token': token});
      if (connection != _connection) return;
      _signedIn = true;
      _attempt = 0;
      status.value = RealtimeStatus.online;
      final seconds = (hello['heartbeat_seconds'] as num?)?.toInt();
      _startHeartbeat(
        seconds != null && seconds > 0
            ? Duration(seconds: seconds)
            : timing.heartbeat,
      );
      for (final name in _channels.keys) {
        _subscribe(name);
      }
    } on RealtimeException catch (error) {
      if (connection != _connection) return; // already handled as a close
      if (_tokenCodes.contains(error.code)) _freshTokenNeeded = true;
      _drop(connection);
    }
  }

  void _onClosed(RealtimeConnection connection) {
    if (connection != _connection) return;
    final code = connection.closeCode;
    _detach();
    if (!_running) return;
    if (code == RealtimeProtocol.closeBadToken) _freshTokenNeeded = true;
    _retryLater(longer: code == RealtimeProtocol.closeRateLimited);
  }

  /// Give up on [connection] now (a dead network may never report the close).
  void _drop(RealtimeConnection connection) {
    _onClosed(connection);
    unawaited(connection.close());
  }

  void _detach() {
    _connection = null;
    _signedIn = false;
    unawaited(_listening?.cancel());
    _listening = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _unansweredPings = 0;
    for (final pending in _pending.values) {
      pending.fail(const RealtimeException('disconnected'));
    }
    _pending.clear();
  }

  void _retryLater({bool longer = false}) {
    if (!_running) return;
    status.value = RealtimeStatus.connecting;
    final steps = min(_attempt, 10);
    _attempt++;
    var wait = timing.firstRetry * (1 << steps);
    if (wait > timing.maxRetry || longer) wait = timing.maxRetry;
    // Jitter (80–120 %), so phones that lost the server together don't all
    // come back in the same instant.
    final jitter = 0.8 + _random.nextDouble() * 0.4;
    _retryTimer?.cancel();
    _retryTimer = Timer(wait * jitter, _open);
  }

  void _startHeartbeat(Duration interval) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(interval, (_) {
      final connection = _connection;
      if (connection == null) return;
      if (_unansweredPings >= 2) {
        _drop(connection); // two missed pings: dead connection
        return;
      }
      _unansweredPings++;
      connection.send(RealtimeProtocol.encode('ping', newRequestId(), {}));
    });
  }

  // ---- messages ----------------------------------------------------------------

  Future<Map<String, dynamic>> _send(
    RealtimeConnection connection,
    String type,
    Map<String, Object?> data, {
    String? reqId,
  }) {
    final id = reqId ?? newRequestId();
    final pending = _PendingRequest(
      Timer(timing.requestTimeout, () {
        _pending.remove(id)?.fail(const RealtimeException('timeout'));
      }),
    );
    _pending[id] = pending;
    connection.send(RealtimeProtocol.encode(type, id, data));
    return pending.completer.future;
  }

  void _onMessage(String text) {
    final message = RealtimeMessage.tryParse(text);
    if (message == null) return;
    _unansweredPings = 0; // anything from the server means it's there
    final channel = message.channel;
    if (channel != null) {
      final version = message.version;
      final seen = _versions[channel];
      if (version != null && (seen == null || version > seen)) {
        _versions[channel] = version;
      }
      _channels[channel]?.add(message);
      return;
    }
    final id = message.reqId;
    if (id == null) return;
    final pending = _pending.remove(id);
    if (pending == null) return;
    if (message.type == 'error') {
      pending.fail(RealtimeException(message.code ?? 'error', message.message));
    } else {
      pending.succeed(message.data);
    }
  }

  void _subscribe(String name) {
    final connection = _connection;
    if (connection == null || !_signedIn) return; // sent after (re)connecting
    final since = _versions[name];
    _send(connection, 'subscribe', {
      'channel': name,
      if (since != null) 'since': since,
    }).then<void>(
      (_) {},
      onError: (Object error) {
        if (error is RealtimeException &&
            error.code != 'disconnected' &&
            error.code != 'timeout') {
          debugPrint('Realtime: subscribe $name refused (${error.code})');
        }
      },
    );
  }

  void _unsubscribe(String name) {
    final connection = _connection;
    if (connection == null || !_signedIn) return;
    _send(connection, 'unsubscribe', {
      'channel': name,
    }).then<void>((_) {}, onError: (Object _) {});
  }
}

class _PendingRequest {
  _PendingRequest(this.timer);

  final Timer timer;
  final completer = Completer<Map<String, dynamic>>();

  void succeed(Map<String, dynamic> data) {
    timer.cancel();
    if (!completer.isCompleted) completer.complete(data);
  }

  void fail(RealtimeException error) {
    timer.cancel();
    if (!completer.isCompleted) completer.completeError(error);
  }
}
