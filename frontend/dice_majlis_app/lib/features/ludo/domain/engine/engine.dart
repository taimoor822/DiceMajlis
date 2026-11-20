import 'board.dart';
import 'bot.dart';
import 'errors.dart';
import 'events.dart';
import 'rules.dart';
import 'state.dart';

/// The Ludo rules engine: a Dart copy of `backend/core/ludo_engine/engine.py`
/// for games played on the phone (vs AI, pass-and-play).
///
/// Pure functions only: no Flutter, no clock, no randomness. Each action takes
/// a [GameState] and returns a [Transition] (new state + events) or throws an
/// [EngineError] with the server's error code. The caller rolls the dice and
/// passes the value in, so the same actions always produce the same game.
///
/// The shared test vectors (`shared/ludo/engine_vectors.json`, exported from
/// the Python engine) must pass here unchanged: same vectors = same rules.

final class Capture {
  const Capture(this.playerId, this.tokenIndex);

  final String playerId;
  final int tokenIndex;

  Map<String, Object?> toJson() => {
    'player_id': playerId,
    'token_index': tokenIndex,
  };
}

final class Move {
  const Move({
    required this.tokenIndex,
    required this.fromProgress,
    required this.toProgress,
    required this.toSquare,
    this.captures = const [],
  });

  final int tokenIndex;
  final int fromProgress;
  final int toProgress;
  final int? toSquare;
  final List<Capture> captures;

  bool get entersBoard => fromProgress == LudoBoard.baseProgress;

  bool get finishesToken => LudoBoard.isHome(toProgress);

  Map<String, Object?> toJson() => {
    'token_index': tokenIndex,
    'from_progress': fromProgress,
    'to_progress': toProgress,
    'to_square': toSquare,
    'captures': [for (final c in captures) c.toJson()],
  };
}

abstract final class LudoEngine {
  // ---- moves ----

  /// Moves the current player may make right now (empty unless one is due).
  static List<Move> legalMoves(GameState state) {
    if (state.isFinished || state.phase != TurnPhase.awaitingMove) {
      return const [];
    }
    return _movesFor(state, state.currentIndex, state.diceValue!);
  }

  // ---- setup ----

  /// A game at version 0. Turn order is clockwise by seat; two players sit
  /// opposite each other (seats 0 and 2) unless [seats] says otherwise.
  static GameState newGame(
    String gameId,
    List<String> playerIds, {
    List<int>? seats,
    Rules? rules,
    String? firstPlayerId,
  }) {
    final ruleSet = rules ?? Rules.standard;
    final ids = [...playerIds];
    if (ids.length < LudoBoard.minPlayers ||
        ids.length > LudoBoard.maxPlayers) {
      throw InvalidSetup(
        'Ludo needs ${LudoBoard.minPlayers} to ${LudoBoard.maxPlayers} '
        'players, got ${ids.length}',
      );
    }
    if (ids.toSet().length != ids.length) {
      throw const InvalidSetup('player ids must be unique');
    }

    final seatList = seats != null
        ? [...seats]
        : LudoBoard.defaultSeatsFor(ids.length);
    if (seatList.length != ids.length) {
      throw const InvalidSetup('one seat per player is required');
    }
    for (final seat in seatList) {
      if (seat < 0 || seat >= LudoBoard.seatCount) {
        throw InvalidSetup(
          'seat must be 0..${LudoBoard.seatCount - 1}, got $seat',
        );
      }
    }
    if (seatList.toSet().length != seatList.length) {
      throw const InvalidSetup('seats must be unique');
    }

    final order = List<int>.generate(ids.length, (i) => i)
      ..sort((a, b) => seatList[a].compareTo(seatList[b]));
    var state = GameState(
      gameId: gameId,
      players: [
        for (final i in order)
          PlayerState(
            playerId: ids[i],
            seat: seatList[i],
            tokens: initialTokens(ruleSet),
          ),
      ],
      rules: ruleSet,
    );
    if (firstPlayerId != null) {
      state = state.copyWith(currentIndex: state.indexOf(firstPlayerId));
    }
    return state;
  }

  // ---- actions ----

  /// Throws unless [playerId] may roll now; returns their player index.
  /// Call it BEFORE rolling, so a refused request never uses the dice.
  static int checkRoll(GameState state, String playerId) {
    _requirePlaying(state);
    final index = _requireTurn(state, playerId);
    if (state.phase != TurnPhase.awaitingRoll) {
      throw const WrongPhase('dice already rolled: move a token');
    }
    return index;
  }

  /// Apply a rolled dice value for the current player.
  static Transition roll(GameState state, String playerId, int value) =>
      _roll(state, playerId, value);

  /// Move one of the current player's tokens by the rolled value.
  static Transition move(GameState state, String playerId, int tokenIndex) =>
      _move(state, playerId, tokenIndex);

  /// The current player's turn timer ran out. Counts a missed turn; after
  /// `rules.maxMissedTurns` in a row the player forfeits. Otherwise the engine
  /// plays for them: rolls [diceValue] (needed when a roll is due) and makes
  /// the bot's move. [expectedTurn] = the turn the timer was started for.
  static Transition timeout(
    GameState state, {
    int? diceValue,
    int? expectedTurn,
  }) => _timeout(state, diceValue, expectedTurn);

  /// Throws unless a timeout for [expectedTurn] can apply now.
  static void checkTimeout(GameState state, [Object? expectedTurn]) {
    _requirePlaying(state);
    if (expectedTurn != null && expectedTurn != state.turnNumber) {
      throw const InvalidAction('stale timeout: that turn is already over');
    }
  }

  /// A player leaves (or is removed). They take the lowest place still free.
  static Transition forfeit(
    GameState state,
    String playerId, {
    String reason = 'left',
  }) {
    _requirePlaying(state);
    final index = state.indexOf(playerId);
    final step = _Step(state);
    _applyForfeit(step, index, reason);
    return step.done();
  }

  /// One entry point for every action, same shapes as the server:
  ///   {"type": "roll", "player_id", "value"}
  ///   {"type": "move", "player_id", "token_index"}
  ///   {"type": "timeout", "dice_value"?, "turn_number"?}
  ///   {"type": "forfeit", "player_id", "reason"?}
  static Transition applyAction(GameState state, Map<String, Object?> action) {
    final kind = action['type'];
    Object? need(String key) {
      if (!action.containsKey(key)) {
        throw InvalidAction("$kind action is missing '$key'");
      }
      return action[key];
    }

    switch (kind) {
      case 'roll':
        final playerId = '${need('player_id')}';
        return _roll(state, playerId, need('value'));
      case 'move':
        final playerId = '${need('player_id')}';
        return _move(state, playerId, need('token_index'));
      case 'timeout':
        return _timeout(state, action['dice_value'], action['turn_number']);
      case 'forfeit':
        final playerId = '${need('player_id')}';
        final reason =
            '${action.containsKey('reason') ? action['reason'] : 'left'}';
        return forfeit(state, playerId, reason: reason);
    }
    throw InvalidAction('unknown action type "$kind"');
  }

  /// Rebuild a game from its starting state and recorded actions.
  static GameState replay(
    GameState initial,
    Iterable<Map<String, Object?>> actions,
  ) {
    var state = initial;
    for (final action in actions) {
      state = applyAction(state, action).state;
    }
    return state;
  }

  /// Places 1..n. Final once the game is finished; provisional before.
  static List<Map<String, Object?>> standings(GameState state) {
    final places = _finalPlaces(state);
    final order = List<int>.generate(state.players.length, (i) => i)
      ..sort((a, b) => places[a].compareTo(places[b]));
    return [
      for (final i in order)
        {
          'player_id': state.players[i].playerId,
          'place': places[i],
          'status': state.players[i].status.wire,
        },
    ];
  }

  // ---- internals ----

  static Transition _roll(GameState state, String playerId, Object? value) {
    final index = checkRoll(state, playerId);
    _checkDie(value);
    final step = _Step(_resetMissedTurns(state, index));
    _applyRoll(step, value! as int);
    return step.done();
  }

  static Transition _move(GameState state, String playerId, Object? token) {
    _requirePlaying(state);
    final index = _requireTurn(state, playerId);
    if (state.phase != TurnPhase.awaitingMove) {
      throw const WrongPhase('roll the dice first');
    }
    if (token is! int || token < 0 || token >= state.rules.tokensPerPlayer) {
      throw IllegalMove('no token $token');
    }
    final step = _Step(_resetMissedTurns(state, index));
    _applyMove(step, token);
    return step.done();
  }

  static Transition _timeout(
    GameState state,
    Object? diceValue,
    Object? expectedTurn,
  ) {
    checkTimeout(state, expectedTurn);
    if (state.phase == TurnPhase.awaitingRoll) {
      if (diceValue == null) {
        throw const InvalidDiceValue('a dice value is needed to auto-roll');
      }
      _checkDie(diceValue);
    }

    final index = state.currentIndex;
    final player = state.currentPlayer;
    final missed = player.missedTurns + 1;
    final step = _Step(
      state.withPlayer(index, player.copyWith(missedTurns: missed)),
    );
    step.emit(EventType.playerTimeout, {
      'player_id': player.playerId,
      'missed_turns': missed,
      'phase': state.phase.wire,
    });

    final limit = state.rules.maxMissedTurns;
    if (limit > 0 && missed >= limit) {
      _applyForfeit(step, index, 'timeout');
      return step.done();
    }

    if (step.state.phase == TurnPhase.awaitingRoll) {
      _applyRoll(step, diceValue! as int);
      if (step.state.phase != TurnPhase.awaitingMove) {
        return step.done(); // the roll ended the turn
      }
    }

    _applyMove(step, LudoBot.chooseMove(step.state).tokenIndex);
    return step.done();
  }

  static List<Move> _movesFor(GameState state, int playerIndex, int dice) {
    final player = state.players[playerIndex];
    final moves = <Move>[];
    for (var tokenIndex = 0; tokenIndex < player.tokens.length; tokenIndex++) {
      final progress = player.tokens[tokenIndex];
      if (LudoBoard.isHome(progress)) continue;
      final int toProgress;
      if (progress == LudoBoard.baseProgress) {
        if (!state.rules.entryRolls.contains(dice)) continue;
        toProgress = LudoBoard.startProgress;
      } else {
        toProgress = progress + dice;
        if (toProgress > LudoBoard.homeProgress) continue; // exact roll home
      }
      final toSquare = LudoBoard.absoluteSquare(player.seat, toProgress);
      moves.add(
        Move(
          tokenIndex: tokenIndex,
          fromProgress: progress,
          toProgress: toProgress,
          toSquare: toSquare,
          captures: _capturesAt(state, playerIndex, toSquare),
        ),
      );
    }
    return moves;
  }

  static List<Capture> _capturesAt(
    GameState state,
    int moverIndex,
    int? square,
  ) {
    final rules = state.rules;
    if (square == null ||
        !rules.captureEnabled ||
        rules.safeSquares.contains(square)) {
      return const [];
    }
    final captures = <Capture>[];
    for (var index = 0; index < state.players.length; index++) {
      final other = state.players[index];
      if (index == moverIndex || other.status == PlayerStatus.forfeited) {
        continue;
      }
      for (var t = 0; t < other.tokens.length; t++) {
        // Compare ABSOLUTE squares: equal progress means different squares.
        if (LudoBoard.absoluteSquare(other.seat, other.tokens[t]) == square) {
          captures.add(Capture(other.playerId, t));
        }
      }
    }
    return captures;
  }

  static void _applyRoll(_Step step, int value) {
    final state = step.state;
    final player = state.currentPlayer;
    final sixes = value == 6 ? state.consecutiveSixes + 1 : 0;
    final limit = state.rules.maxConsecutiveSixes;

    if (limit > 0 && sixes >= limit) {
      step.emit(EventType.diceResult, {
        'player_id': player.playerId,
        'value': value,
        'consecutive_sixes': sixes,
        'movable_tokens': <int>[],
      });
      step.state = state.copyWith(consecutiveSixes: sixes);
      _endTurn(step, TurnEndReason.tooManySixes, extraTurn: false);
      return;
    }

    final moves = _movesFor(state, state.currentIndex, value);
    step.emit(EventType.diceResult, {
      'player_id': player.playerId,
      'value': value,
      'consecutive_sixes': sixes,
      'movable_tokens': [for (final m in moves) m.tokenIndex],
    });
    if (moves.isEmpty) {
      step.state = state.copyWith(consecutiveSixes: sixes);
      _endTurn(step, TurnEndReason.noLegalMoves, extraTurn: false);
      return;
    }

    step.state = state.copyWith(
      phase: TurnPhase.awaitingMove,
      diceValue: value,
      consecutiveSixes: sixes,
    );
  }

  static void _applyMove(_Step step, int tokenIndex) {
    var state = step.state;
    final index = state.currentIndex;
    final player = state.currentPlayer;
    final dice = state.diceValue!;

    Move? chosen;
    for (final m in _movesFor(state, index, dice)) {
      if (m.tokenIndex == tokenIndex) {
        chosen = m;
        break;
      }
    }
    if (chosen == null) {
      throw IllegalMove('token $tokenIndex cannot move $dice');
    }

    state = state.withPlayer(
      index,
      player.withToken(tokenIndex, chosen.toProgress),
    );
    step.emit(EventType.tokenMoved, {
      'player_id': player.playerId,
      'token_index': tokenIndex,
      'from_progress': chosen.fromProgress,
      'to_progress': chosen.toProgress,
      'from_square': LudoBoard.absoluteSquare(player.seat, chosen.fromProgress),
      'to_square': chosen.toSquare,
      'dice': dice,
    });

    for (final capture in chosen.captures) {
      final victimIndex = state.indexOf(capture.playerId);
      final victim = state.players[victimIndex];
      state = state.withPlayer(
        victimIndex,
        victim.withToken(capture.tokenIndex, LudoBoard.baseProgress),
      );
      step.emit(EventType.tokenCaptured, {
        'player_id': capture.playerId,
        'token_index': capture.tokenIndex,
        'square': chosen.toSquare,
        'by_player_id': player.playerId,
      });
    }

    if (chosen.finishesToken) {
      step.emit(EventType.tokenFinished, {
        'player_id': player.playerId,
        'token_index': tokenIndex,
      });
    }

    step.state = state;

    if (chosen.finishesToken && state.players[index].allTokensHome) {
      _playerFinished(step, index);
      if (!step.state.isFinished) {
        _endTurn(step, TurnEndReason.playerFinished, extraTurn: false);
      }
      return;
    }

    final rules = state.rules;
    final extraTurn =
        (dice == 6 && rules.extraTurnOnSix) ||
        (chosen.captures.isNotEmpty && rules.extraTurnOnCapture) ||
        (chosen.finishesToken && rules.extraTurnOnFinish);
    _endTurn(step, TurnEndReason.moved, extraTurn: extraTurn);
  }

  static void _endTurn(
    _Step step,
    TurnEndReason reason, {
    required bool extraTurn,
  }) {
    final state = step.state;
    final current = state.currentPlayer;
    final keepsTurn = extraTurn && current.status == PlayerStatus.active;

    step.emit(EventType.turnEnded, {
      'player_id': current.playerId,
      'reason': reason.wire,
      'extra_turn': keepsTurn,
    });

    final nextIndex = keepsTurn ? state.currentIndex : _nextActiveIndex(state);
    step.state = state.copyWith(
      currentIndex: nextIndex,
      phase: TurnPhase.awaitingRoll,
      diceValue: null,
      // Sixes keep counting through extra turns; a new player starts at zero.
      consecutiveSixes: keepsTurn ? state.consecutiveSixes : 0,
      turnNumber: state.turnNumber + 1,
    );
    step.emit(EventType.turnStarted, {
      'player_id': step.state.currentPlayer.playerId,
      'turn_number': step.state.turnNumber,
      'extra_turn': keepsTurn,
    });
  }

  static void _playerFinished(_Step step, int index) {
    final state = step.state;
    final place =
        1 +
        state.players
            .where(
              (p) => p.status == PlayerStatus.finished && p.finishPlace != null,
            )
            .length;
    final player = state.players[index].copyWith(
      status: PlayerStatus.finished,
      finishPlace: place,
    );
    step.state = state.withPlayer(index, player);
    step.emit(EventType.playerFinished, {
      'player_id': player.playerId,
      'place': place,
    });

    if (state.rules.endWhenFirstPlayerFinishes ||
        _activeCount(step.state) <= 1) {
      _finishGame(step);
    }
  }

  static void _applyForfeit(_Step step, int index, String reason) {
    var state = step.state;
    final player = state.players[index];
    if (player.status != PlayerStatus.active) {
      throw InvalidAction('player "${player.playerId}" is not active');
    }

    final alreadyOut = state.players
        .where((p) => p.status == PlayerStatus.forfeited)
        .length;
    final place = state.players.length - alreadyOut; // from the bottom
    state = state.withPlayer(
      index,
      player.copyWith(status: PlayerStatus.forfeited, finishPlace: place),
    );
    step.state = state;
    step.emit(EventType.playerForfeited, {
      'player_id': player.playerId,
      'reason': reason,
      'place': place,
    });

    if (_activeCount(state) <= 1) {
      _finishGame(step);
    } else if (index == state.currentIndex) {
      _endTurn(step, TurnEndReason.forfeited, extraTurn: false);
    }
  }

  static void _finishGame(_Step step) {
    final state = step.state;
    final places = _finalPlaces(state);
    final players = [
      for (var i = 0; i < state.players.length; i++)
        state.players[i].finishPlace != null
            ? state.players[i]
            : state.players[i].copyWith(finishPlace: places[i]),
    ];
    final winner = players.firstWhere((p) => p.finishPlace == 1);
    step.state = state.copyWith(
      players: players,
      status: GameStatus.finished,
      phase: TurnPhase.awaitingRoll,
      diceValue: null,
      winnerId: winner.playerId,
    );
    step.emit(EventType.gameFinished, {
      'winner_id': winner.playerId,
      'standings': standings(step.state),
    });
  }

  /// Fixed places (finished/forfeited) stay; the rest are ranked by progress.
  static List<int> _finalPlaces(GameState state) {
    final count = state.players.length;
    final places = [for (final p in state.players) p.finishPlace];
    final taken = places.toSet();
    final free = [
      for (var k = 1; k <= count; k++)
        if (!taken.contains(k)) k,
    ];
    final unplaced = [
      for (var i = 0; i < count; i++)
        if (places[i] == null) i,
    ];
    unplaced.sort((a, b) {
      final byScore = _progressScore(
        state.players[b],
      ).compareTo(_progressScore(state.players[a]));
      if (byScore != 0) return byScore;
      return state.players[a].seat.compareTo(state.players[b].seat);
    });
    for (var k = 0; k < free.length && k < unplaced.length; k++) {
      places[unplaced[k]] = free[k];
    }
    return [for (final p in places) p!];
  }

  /// Base = 0, home = 57 per token.
  static int _progressScore(PlayerState player) =>
      player.tokens.fold(0, (sum, progress) => sum + progress + 1);

  static int _nextActiveIndex(GameState state) {
    final count = state.players.length;
    for (var step = 1; step <= count; step++) {
      final candidate = (state.currentIndex + step) % count;
      if (state.players[candidate].status == PlayerStatus.active) {
        return candidate;
      }
    }
    return state.currentIndex;
  }

  static int _activeCount(GameState state) =>
      state.players.where((p) => p.status == PlayerStatus.active).length;

  static GameState _resetMissedTurns(GameState state, int index) {
    final player = state.players[index];
    if (player.missedTurns == 0) return state;
    return state.withPlayer(index, player.copyWith(missedTurns: 0));
  }

  static void _requirePlaying(GameState state) {
    if (state.isFinished) throw const GameNotActive('the game is finished');
  }

  static int _requireTurn(GameState state, String playerId) {
    final index = state.indexOf(playerId);
    if (index != state.currentIndex) {
      throw NotYourTurn("it is ${state.currentPlayer.playerId}'s turn");
    }
    return index;
  }

  static void _checkDie(Object? value) {
    if (value is! int || value < 1 || value > 6) {
      throw InvalidDiceValue('dice value must be 1..6, got $value');
    }
  }
}

/// Collects the events of ONE action; the whole action gets one new version.
final class _Step {
  _Step(this.state) : version = state.version + 1;

  GameState state;
  final int version;
  final List<Event> events = [];

  void emit(EventType type, Map<String, Object?> data) =>
      events.add(Event(type, version, data));

  Transition done() =>
      Transition(state.copyWith(version: version), List.unmodifiable(events));
}
