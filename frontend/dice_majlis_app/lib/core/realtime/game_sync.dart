import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The game version the app has drawn, per room code.
///
/// The room socket writes it (every event and snapshot carries the version);
/// game actions send it as `expected_version`, so the server refuses a move
/// made on an older picture of the board (`stale_version`) instead of
/// applying it. After such a refusal, [requestResync] asks the room's socket
/// to load the whole state again.
class GameSync {
  final _versions = <String, int>{};
  final _resyncs = StreamController<String>.broadcast(sync: true);

  /// The newest version seen for [roomCode], or null before the first one.
  int? version(String roomCode) => _versions[roomCode];

  /// An event or answer at [version] (versions only go up within a game).
  void saw(String roomCode, int version) {
    final old = _versions[roomCode];
    if (old == null || version > old) _versions[roomCode] = version;
  }

  /// A whole snapshot at [version]: replaces what was known (a new game in the
  /// same room starts again from its own versions).
  void reset(String roomCode, int version) => _versions[roomCode] = version;

  void forget(String roomCode) => _versions.remove(roomCode);

  /// Asks the room's socket to load the whole state again.
  void requestResync(String roomCode) => _resyncs.add(roomCode);

  /// Room codes whose state should be loaded again.
  Stream<String> get resyncRequests => _resyncs.stream;
}

final gameSyncProvider = Provider<GameSync>((ref) => GameSync());
