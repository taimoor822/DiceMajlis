import 'board.dart';
import 'errors.dart';
import 'rules.dart';

/// Immutable game state: a Dart copy of `backend/core/ludo_engine/state.py`.
///
/// Every engine call takes a [GameState] and returns a new one; nothing is
/// changed in place. [GameState.version] goes up by exactly one per accepted
/// action. [GameState.toJson] has the same shape as the server's snapshot.

const int schemaVersion = 1;

enum GameStatus {
  playing('playing'),
  finished('finished');

  const GameStatus(this.wire);
  final String wire;

  static GameStatus fromWire(String value) =>
      values.firstWhere((s) => s.wire == value, orElse: () => _bad(value));
}

enum TurnPhase {
  awaitingRoll('awaiting_roll'),
  awaitingMove('awaiting_move');

  const TurnPhase(this.wire);
  final String wire;

  static TurnPhase fromWire(String value) =>
      values.firstWhere((s) => s.wire == value, orElse: () => _bad(value));
}

enum PlayerStatus {
  active('active'),

  /// Every token is home.
  finished('finished'),

  /// Left, or timed out too many times.
  forfeited('forfeited');

  const PlayerStatus(this.wire);
  final String wire;

  static PlayerStatus fromWire(String value) =>
      values.firstWhere((s) => s.wire == value, orElse: () => _bad(value));
}

Never _bad(String value) => throw InvalidSetup('unknown value "$value"');

/// Lets `copyWith` set a nullable field back to null.
const Object _keep = Object();

final class PlayerState {
  PlayerState({
    required this.playerId,
    required this.seat,
    required List<int> tokens,
    this.status = PlayerStatus.active,
    this.missedTurns = 0,
    this.finishPlace,
  }) : tokens = List.unmodifiable(tokens);

  final String playerId;
  final int seat;

  /// Progress of each token (see [LudoBoard]).
  final List<int> tokens;
  final PlayerStatus status;
  final int missedTurns;
  final int? finishPlace;

  String get color => LudoBoard.seatColors[seat];

  bool get allTokensHome => tokens.every(LudoBoard.isHome);

  PlayerState withToken(int index, int progress) {
    final next = [...tokens];
    next[index] = progress;
    return copyWith(tokens: next);
  }

  PlayerState copyWith({
    List<int>? tokens,
    PlayerStatus? status,
    int? missedTurns,
    Object? finishPlace = _keep,
  }) => PlayerState(
    playerId: playerId,
    seat: seat,
    tokens: tokens ?? this.tokens,
    status: status ?? this.status,
    missedTurns: missedTurns ?? this.missedTurns,
    finishPlace: identical(finishPlace, _keep)
        ? this.finishPlace
        : finishPlace as int?,
  );

  Map<String, Object?> toJson() => {
    'player_id': playerId,
    'seat': seat,
    'color': color, // derived, for clients
    'status': status.wire,
    'missed_turns': missedTurns,
    'finish_place': finishPlace,
    'tokens': [
      for (var i = 0; i < tokens.length; i++)
        {
          'index': i,
          'progress': tokens[i],
          'square': LudoBoard.absoluteSquare(seat, tokens[i]), // derived
        },
    ],
  };

  factory PlayerState.fromJson(Map<String, Object?> json) => PlayerState(
    playerId: json['player_id'].toString(),
    seat: json['seat'] as int,
    tokens: [
      for (final t in json['tokens'] as List)
        (t as Map<String, Object?>)['progress'] as int,
    ],
    status: PlayerStatus.fromWire(
      json['status'] as String? ?? PlayerStatus.active.wire,
    ),
    missedTurns: json['missed_turns'] as int? ?? 0,
    finishPlace: json['finish_place'] as int?,
  );

  @override
  bool operator ==(Object other) =>
      other is PlayerState &&
      other.playerId == playerId &&
      other.seat == seat &&
      _sameList(other.tokens, tokens) &&
      other.status == status &&
      other.missedTurns == missedTurns &&
      other.finishPlace == finishPlace;

  @override
  int get hashCode => Object.hash(
    playerId,
    seat,
    Object.hashAll(tokens),
    status,
    missedTurns,
    finishPlace,
  );
}

final class GameState {
  GameState({
    required this.gameId,
    required List<PlayerState> players,
    Rules? rules,
    this.status = GameStatus.playing,
    this.phase = TurnPhase.awaitingRoll,
    this.currentIndex = 0,
    this.turnNumber = 1,
    this.diceValue,
    this.consecutiveSixes = 0,
    this.winnerId,
    this.version = 0,
  }) : players = List.unmodifiable(players),
       rules = rules ?? Rules.standard {
    checkInvariants();
  }

  final String gameId;

  /// In turn order (clockwise by seat).
  final List<PlayerState> players;
  final Rules rules;
  final GameStatus status;
  final TurnPhase phase;
  final int currentIndex;
  final int turnNumber;
  final int? diceValue;
  final int consecutiveSixes;
  final String? winnerId;
  final int version;

  // ---- lookups ----

  PlayerState get currentPlayer => players[currentIndex];

  bool get isFinished => status == GameStatus.finished;

  int indexOf(String playerId) {
    for (var i = 0; i < players.length; i++) {
      if (players[i].playerId == playerId) return i;
    }
    throw UnknownPlayer('player "$playerId" is not in game "$gameId"');
  }

  PlayerState player(String playerId) => players[indexOf(playerId)];

  GameState withPlayer(int index, PlayerState player) {
    final next = [...players];
    next[index] = player;
    return copyWith(players: next);
  }

  GameState copyWith({
    List<PlayerState>? players,
    GameStatus? status,
    TurnPhase? phase,
    int? currentIndex,
    int? turnNumber,
    Object? diceValue = _keep,
    int? consecutiveSixes,
    Object? winnerId = _keep,
    int? version,
  }) => GameState(
    gameId: gameId,
    players: players ?? this.players,
    rules: rules,
    status: status ?? this.status,
    phase: phase ?? this.phase,
    currentIndex: currentIndex ?? this.currentIndex,
    turnNumber: turnNumber ?? this.turnNumber,
    diceValue: identical(diceValue, _keep) ? this.diceValue : diceValue as int?,
    consecutiveSixes: consecutiveSixes ?? this.consecutiveSixes,
    winnerId: identical(winnerId, _keep) ? this.winnerId : winnerId as String?,
    version: version ?? this.version,
  );

  // ---- integrity ----

  /// Rejects states that can never happen (e.g. a tampered snapshot).
  void checkInvariants() {
    if (players.length < 2 || players.length > LudoBoard.seatColors.length) {
      throw const InvalidSetup('a game needs 2 to 4 players');
    }
    final ids = players.map((p) => p.playerId).toList();
    final seats = players.map((p) => p.seat).toList();
    if (ids.toSet().length != ids.length) {
      throw const InvalidSetup('player ids must be unique');
    }
    final sorted = [...seats]..sort();
    if (seats.toSet().length != seats.length || !_sameList(seats, sorted)) {
      throw const InvalidSetup('seats must be unique and in turn order');
    }
    if (currentIndex < 0 || currentIndex >= players.length) {
      throw const InvalidSetup('current_index out of range');
    }
    for (final p in players) {
      if (p.tokens.length != rules.tokensPerPlayer) {
        throw InvalidSetup(
          'player "${p.playerId}" has the wrong number of tokens',
        );
      }
      if (!p.tokens.every(LudoBoard.isValidProgress)) {
        throw InvalidSetup('player "${p.playerId}" has a token off the board');
      }
    }
    if (phase == TurnPhase.awaitingMove && diceValue == null) {
      throw const InvalidSetup('awaiting_move needs a dice value');
    }
    if (phase == TurnPhase.awaitingRoll && diceValue != null) {
      throw const InvalidSetup('awaiting_roll must not carry a dice value');
    }
    if (version < 0) {
      throw const InvalidSetup('version must be >= 0');
    }
  }

  // ---- serialisation ----

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'game_id': gameId,
    'version': version,
    'status': status.wire,
    'phase': phase.wire,
    'turn_number': turnNumber,
    'current_player_id': currentPlayer.playerId,
    'dice_value': diceValue,
    'consecutive_sixes': consecutiveSixes,
    'winner_id': winnerId,
    'players': [for (final p in players) p.toJson()],
    'rules': rules.toJson(),
  };

  factory GameState.fromJson(Map<String, Object?> json) {
    if (json['schema_version'] != schemaVersion) {
      throw InvalidSetup(
        'unsupported schema_version ${json['schema_version']}',
      );
    }
    final players = [
      for (final p in json['players'] as List)
        PlayerState.fromJson(p as Map<String, Object?>),
    ];
    final currentId = json['current_player_id'].toString();
    final currentIndex = players.indexWhere((p) => p.playerId == currentId);
    if (currentIndex < 0) {
      throw const InvalidSetup('current_player_id is not one of the players');
    }
    return GameState(
      gameId: json['game_id'].toString(),
      players: players,
      rules: Rules.fromJson(
        (json['rules'] as Map<String, Object?>?) ?? const {},
      ),
      status: GameStatus.fromWire(json['status'] as String),
      phase: TurnPhase.fromWire(json['phase'] as String),
      currentIndex: currentIndex,
      turnNumber: json['turn_number'] as int,
      diceValue: json['dice_value'] as int?,
      consecutiveSixes: json['consecutive_sixes'] as int? ?? 0,
      winnerId: json['winner_id'] as String?,
      version: json['version'] as int,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GameState &&
      other.gameId == gameId &&
      _sameList(other.players, players) &&
      other.rules == rules &&
      other.status == status &&
      other.phase == phase &&
      other.currentIndex == currentIndex &&
      other.turnNumber == turnNumber &&
      other.diceValue == diceValue &&
      other.consecutiveSixes == consecutiveSixes &&
      other.winnerId == winnerId &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
    gameId,
    Object.hashAll(players),
    rules,
    status,
    phase,
    currentIndex,
    turnNumber,
    diceValue,
    consecutiveSixes,
    winnerId,
    version,
  );
}

List<int> initialTokens(Rules rules) =>
    List<int>.filled(rules.tokensPerPlayer, LudoBoard.baseProgress);

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
