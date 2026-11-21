import 'package:flutter/foundation.dart';

import '../../ludo/domain/engine/ludo_engine.dart';
import 'local_game_setup.dart';

/// How long the board takes over each thing, so people can follow it.
final class LocalPlayTiming {
  const LocalPlayTiming({
    required this.aiThink,
    required this.showDice,
    required this.step,
    required this.capture,
  });

  static const normal = LocalPlayTiming(
    aiThink: Duration(milliseconds: 650),
    showDice: Duration(milliseconds: 600),
    step: Duration(milliseconds: 130),
    capture: Duration(milliseconds: 450),
  );

  /// No waiting at all (tests).
  static const instant = LocalPlayTiming(
    aiThink: Duration.zero,
    showDice: Duration.zero,
    step: Duration.zero,
    capture: Duration.zero,
  );

  /// Pause before the AI rolls or moves.
  final Duration aiThink;

  /// How long a roll with no move stays on screen before the turn passes.
  final Duration showDice;

  /// Per square when a token walks.
  final Duration step;

  /// How long a captured token flashes in its base.
  final Duration capture;
}

enum LocalNoticeKind { noMoves, tooManySixes, captured, home }

/// Something that just happened, shown in the status line for a moment.
final class LocalNotice {
  const LocalNotice(this.kind, this.playerIndex, {this.place});

  final LocalNoticeKind kind;
  final int playerIndex;
  final int? place;
}

/// Runs one offline game on the Dart engine: rolls the dice for each turn
/// (secure random), lets the AI play its seats, and walks tokens square by
/// square so everyone at the table can follow. Nothing here touches the
/// server, coins or ratings.
class LocalGameController extends ChangeNotifier {
  LocalGameController({
    required this.setup,
    required DiceRoller dice,
    this.timing = LocalPlayTiming.normal,
  }) : _dice = dice,
       _state = LudoEngine.newGame(
         'local',
         [for (final seat in setup.seats) LocalGameSetup.playerIdFor(seat)],
         seats: setup.seats,
         rules: setup.rules,
       ) {
    _shown = [
      for (final p in _state.players) [...p.tokens],
    ];
  }

  final LocalGameSetup setup;
  final LocalPlayTiming timing;
  final DiceRoller _dice;

  GameState _state;
  late List<List<int>> _shown;
  final Set<(int, int)> _flashing = {};
  int? _diceValue;
  bool _busy = false;
  int _actor = 0;
  bool _aiRunning = false;
  bool _disposed = false;
  LocalNotice? _notice;

  /// The engine's state. While a move is being shown it is already the
  /// state after the move; draw tokens with [shownProgress].
  GameState get state => _state;

  /// The last roll, until the next turn starts.
  int? get diceValue => _diceValue;

  /// True while a roll or a move is being shown.
  bool get busy => _busy;

  LocalNotice? get notice => _notice;

  /// Whose roll or move is on screen: while a move is being shown, the
  /// player who made it; otherwise the player whose turn it is.
  int get activePlayerIndex => _busy ? _actor : _state.currentIndex;

  LocalSeatKind kindOf(int playerIndex) =>
      setup.kinds[_state.players[playerIndex].seat]!;

  bool get isHumanTurn =>
      !_state.isFinished && kindOf(_state.currentIndex) == LocalSeatKind.human;

  bool get canRoll =>
      isHumanTurn && !_busy && _state.phase == TurnPhase.awaitingRoll;

  /// Tokens the current person may tap now.
  Set<int> get movableTokens {
    if (!isHumanTurn || _busy || _state.phase != TurnPhase.awaitingMove) {
      return const {};
    }
    return {for (final m in LudoEngine.legalMoves(_state)) m.tokenIndex};
  }

  /// Where a token is drawn right now (it may still be walking).
  int shownProgress(int playerIndex, int tokenIndex) =>
      _shown[playerIndex][tokenIndex];

  bool isFlashing(int playerIndex, int tokenIndex) =>
      _flashing.contains((playerIndex, tokenIndex));

  /// Places 1..n once the game is over.
  List<Map<String, Object?>> get standings => LudoEngine.standings(_state);

  /// Lets the AI play if one of its seats goes first. Completes when a person
  /// has to act or the game is over.
  Future<void> start() => _runAi();

  /// The current person rolls.
  Future<void> roll() async {
    if (!canRoll) return;
    final playerId = _state.currentPlayer.playerId;
    await _show(LudoEngine.roll(_state, playerId, _dice.roll()));
    await _runAi();
  }

  /// The current person moves [tokenIndex] by their roll.
  Future<void> moveToken(int tokenIndex) async {
    if (!movableTokens.contains(tokenIndex)) return;
    final playerId = _state.currentPlayer.playerId;
    await _show(LudoEngine.move(_state, playerId, tokenIndex));
    await _runAi();
  }

  Future<void> _runAi() async {
    if (_aiRunning) return;
    _aiRunning = true;
    try {
      while (!_disposed &&
          !_state.isFinished &&
          kindOf(_state.currentIndex) == LocalSeatKind.ai) {
        await _wait(timing.aiThink);
        if (_disposed) return;
        final playerId = _state.currentPlayer.playerId;
        final transition = _state.phase == TurnPhase.awaitingRoll
            ? LudoEngine.roll(_state, playerId, _dice.roll())
            : LudoEngine.move(
                _state,
                playerId,
                LudoBot.chooseMove(_state).tokenIndex,
              );
        await _show(transition);
      }
    } finally {
      _aiRunning = false;
    }
  }

  /// Plays a transition's events on the board, one after another.
  Future<void> _show(Transition transition) async {
    final before = _state;
    _actor = before.currentIndex;
    _state = transition.state;
    _busy = true;
    _notice = null;
    _notify();

    for (final event in transition.events) {
      if (_disposed) return;
      final data = event.data;
      switch (event.type) {
        case EventType.diceResult:
          _diceValue = data['value']! as int;
          _notify();
          if ((data['movable_tokens']! as List).isEmpty) {
            await _wait(timing.showDice);
          }
        case EventType.tokenMoved:
          await _walk(
            before.indexOf(data['player_id']! as String),
            data['token_index']! as int,
            data['from_progress']! as int,
            data['to_progress']! as int,
          );
        case EventType.tokenCaptured:
          final victim = before.indexOf(data['player_id']! as String);
          final token = data['token_index']! as int;
          _shown[victim][token] = LudoBoard.baseProgress;
          _flashing.add((victim, token));
          _notice = LocalNotice(
            LocalNoticeKind.captured,
            before.indexOf(data['by_player_id']! as String),
          );
          _notify();
          await _wait(timing.capture);
          _flashing.remove((victim, token));
        case EventType.turnEnded:
          final player = before.indexOf(data['player_id']! as String);
          if (data['reason'] == TurnEndReason.noLegalMoves.wire) {
            _notice = LocalNotice(LocalNoticeKind.noMoves, player);
          } else if (data['reason'] == TurnEndReason.tooManySixes.wire) {
            _notice = LocalNotice(LocalNoticeKind.tooManySixes, player);
          }
        case EventType.playerFinished:
          _notice = LocalNotice(
            LocalNoticeKind.home,
            before.indexOf(data['player_id']! as String),
            place: data['place']! as int,
          );
        case EventType.turnStarted:
          _diceValue = null;
        default:
          break;
      }
    }
    if (_disposed) return;

    // The walk ends where the engine says every token is.
    _shown = [
      for (final p in _state.players) [...p.tokens],
    ];
    _busy = false;
    _notify();
  }

  Future<void> _walk(int player, int token, int from, int to) async {
    if (from == LudoBoard.baseProgress) {
      _shown[player][token] = LudoBoard.startProgress;
      _notify();
      await _wait(timing.step);
      return;
    }
    for (var p = from + 1; p <= to; p++) {
      if (_disposed) return;
      _shown[player][token] = p;
      _notify();
      await _wait(timing.step);
    }
  }

  Future<void> _wait(Duration duration) =>
      duration == Duration.zero ? Future.value() : Future.delayed(duration);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
