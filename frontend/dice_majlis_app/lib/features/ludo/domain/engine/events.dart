import 'state.dart';

/// Events the engine emits for each accepted action: a Dart copy of
/// `backend/core/ludo_engine/events.py`. The wire names are the same as the
/// server's, and every event from one action carries the version it produced.
enum EventType {
  diceResult('dice_result'),
  tokenMoved('token_moved'),
  tokenCaptured('token_captured'),
  tokenFinished('token_finished'),
  turnEnded('turn_ended'),
  turnStarted('turn_started'),
  playerTimeout('player_timeout'),
  playerFinished('player_finished'),
  playerForfeited('player_forfeited'),
  gameFinished('game_finished');

  const EventType(this.wire);
  final String wire;
}

enum TurnEndReason {
  moved('moved'),
  noLegalMoves('no_legal_moves'),
  tooManySixes('too_many_sixes'),
  playerFinished('player_finished'),
  forfeited('forfeited');

  const TurnEndReason(this.wire);
  final String wire;
}

final class Event {
  const Event(this.type, this.version, this.data);

  final EventType type;
  final int version;

  /// JSON-safe payload, same keys as the server's.
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
    'type': type.wire,
    'version': version,
    'data': data,
  };

  @override
  String toString() => 'Event(${type.wire} v$version $data)';
}

/// Result of one accepted action: the new state and what happened, in order.
final class Transition {
  const Transition(this.state, this.events);

  final GameState state;
  final List<Event> events;

  List<String> get eventTypes => [for (final e in events) e.type.wire];
}
