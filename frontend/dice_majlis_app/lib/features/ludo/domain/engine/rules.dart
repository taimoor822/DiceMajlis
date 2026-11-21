import 'board.dart';

/// Configurable game rules: a Dart copy of `backend/core/ludo_engine/rules.py`.
///
/// The defaults must equal the server's; the shared test vectors check that,
/// so a rule changed in Python and not here fails the Flutter tests. A [Rules]
/// object travels inside every [GameState], so a game keeps the rules it
/// started with.
final class Rules {
  Rules({
    this.tokensPerPlayer = 4,
    Set<int> entryRolls = const {6},
    this.extraTurnOnSix = true,
    this.extraTurnOnCapture = true,
    this.extraTurnOnFinish = true,
    this.maxConsecutiveSixes = 3,
    this.captureEnabled = true,
    Set<int>? safeSquares,
    this.turnTimeoutSeconds = 30,
    this.timeoutWarningSeconds = 10,
    this.maxMissedTurns = 3,
    this.endWhenFirstPlayerFinishes = true,
  }) : entryRolls = Set.unmodifiable(entryRolls),
       safeSquares = Set.unmodifiable(
         safeSquares ?? LudoBoard.defaultSafeSquares(),
       ) {
    _validate();
  }

  /// The standard rules (the server's `DEFAULT_RULES`).
  static final Rules standard = Rules();

  final int tokensPerPlayer;

  /// Dice values that let a token leave base and enter on its start square.
  final Set<int> entryRolls;

  final bool extraTurnOnSix;
  final bool extraTurnOnCapture;
  final bool extraTurnOnFinish;

  /// Rolling this many sixes in a row ends the turn. 0 disables the rule.
  final int maxConsecutiveSixes;

  final bool captureEnabled;
  final Set<int> safeSquares;

  /// Used by the server's turn timer, not by the engine (it has no clock).
  final int turnTimeoutSeconds;
  final int timeoutWarningSeconds;

  /// After this many timed-out turns in a row a player forfeits. 0 disables.
  final int maxMissedTurns;

  /// True: the first player to bring every token home wins and the game ends.
  /// False: play continues and every player gets a finishing place.
  final bool endWhenFirstPlayerFinishes;

  void _validate() {
    if (tokensPerPlayer < 1 || tokensPerPlayer > 4) {
      throw ArgumentError('tokens_per_player must be 1..4');
    }
    if (entryRolls.isEmpty || !entryRolls.every((v) => v >= 1 && v <= 6)) {
      throw ArgumentError('entry_rolls must be a non-empty set of values 1..6');
    }
    if (!safeSquares.every((s) => s >= 0 && s < LudoBoard.trackLength)) {
      throw ArgumentError(
        'safe_squares must be track squares 0..${LudoBoard.trackLength - 1}',
      );
    }
    if (maxConsecutiveSixes < 0) {
      throw ArgumentError('max_consecutive_sixes must be >= 0');
    }
    if (maxMissedTurns < 0) {
      throw ArgumentError('max_missed_turns must be >= 0');
    }
    if (turnTimeoutSeconds <= 0) {
      throw ArgumentError('turn_timeout_seconds must be > 0');
    }
    if (timeoutWarningSeconds < 0 ||
        timeoutWarningSeconds >= turnTimeoutSeconds) {
      throw ArgumentError(
        'timeout_warning_seconds must be 0..turn_timeout_seconds-1',
      );
    }
  }

  Rules copyWith({
    int? tokensPerPlayer,
    Set<int>? entryRolls,
    bool? extraTurnOnSix,
    bool? extraTurnOnCapture,
    bool? extraTurnOnFinish,
    int? maxConsecutiveSixes,
    bool? captureEnabled,
    Set<int>? safeSquares,
    int? turnTimeoutSeconds,
    int? timeoutWarningSeconds,
    int? maxMissedTurns,
    bool? endWhenFirstPlayerFinishes,
  }) => Rules(
    tokensPerPlayer: tokensPerPlayer ?? this.tokensPerPlayer,
    entryRolls: entryRolls ?? this.entryRolls,
    extraTurnOnSix: extraTurnOnSix ?? this.extraTurnOnSix,
    extraTurnOnCapture: extraTurnOnCapture ?? this.extraTurnOnCapture,
    extraTurnOnFinish: extraTurnOnFinish ?? this.extraTurnOnFinish,
    maxConsecutiveSixes: maxConsecutiveSixes ?? this.maxConsecutiveSixes,
    captureEnabled: captureEnabled ?? this.captureEnabled,
    safeSquares: safeSquares ?? this.safeSquares,
    turnTimeoutSeconds: turnTimeoutSeconds ?? this.turnTimeoutSeconds,
    timeoutWarningSeconds: timeoutWarningSeconds ?? this.timeoutWarningSeconds,
    maxMissedTurns: maxMissedTurns ?? this.maxMissedTurns,
    endWhenFirstPlayerFinishes:
        endWhenFirstPlayerFinishes ?? this.endWhenFirstPlayerFinishes,
  );

  /// Same keys as the server's `Rules.to_dict()` (sets as sorted lists).
  Map<String, Object?> toJson() => {
    'tokens_per_player': tokensPerPlayer,
    'entry_rolls': entryRolls.toList()..sort(),
    'extra_turn_on_six': extraTurnOnSix,
    'extra_turn_on_capture': extraTurnOnCapture,
    'extra_turn_on_finish': extraTurnOnFinish,
    'max_consecutive_sixes': maxConsecutiveSixes,
    'capture_enabled': captureEnabled,
    'safe_squares': safeSquares.toList()..sort(),
    'turn_timeout_seconds': turnTimeoutSeconds,
    'timeout_warning_seconds': timeoutWarningSeconds,
    'max_missed_turns': maxMissedTurns,
    'end_when_first_player_finishes': endWhenFirstPlayerFinishes,
  };

  /// Missing keys take the default; unknown keys are ignored (like the server).
  factory Rules.fromJson(Map<String, Object?> json) {
    final d = standard;
    Set<int>? ints(Object? value) =>
        value == null ? null : {for (final v in value as List) v as int};
    return Rules(
      tokensPerPlayer: json['tokens_per_player'] as int? ?? d.tokensPerPlayer,
      entryRolls: ints(json['entry_rolls']) ?? d.entryRolls,
      extraTurnOnSix: json['extra_turn_on_six'] as bool? ?? d.extraTurnOnSix,
      extraTurnOnCapture:
          json['extra_turn_on_capture'] as bool? ?? d.extraTurnOnCapture,
      extraTurnOnFinish:
          json['extra_turn_on_finish'] as bool? ?? d.extraTurnOnFinish,
      maxConsecutiveSixes:
          json['max_consecutive_sixes'] as int? ?? d.maxConsecutiveSixes,
      captureEnabled: json['capture_enabled'] as bool? ?? d.captureEnabled,
      safeSquares: ints(json['safe_squares']) ?? d.safeSquares,
      turnTimeoutSeconds:
          json['turn_timeout_seconds'] as int? ?? d.turnTimeoutSeconds,
      timeoutWarningSeconds:
          json['timeout_warning_seconds'] as int? ?? d.timeoutWarningSeconds,
      maxMissedTurns: json['max_missed_turns'] as int? ?? d.maxMissedTurns,
      endWhenFirstPlayerFinishes:
          json['end_when_first_player_finishes'] as bool? ??
          d.endWhenFirstPlayerFinishes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Rules &&
      other.tokensPerPlayer == tokensPerPlayer &&
      _sameSet(other.entryRolls, entryRolls) &&
      other.extraTurnOnSix == extraTurnOnSix &&
      other.extraTurnOnCapture == extraTurnOnCapture &&
      other.extraTurnOnFinish == extraTurnOnFinish &&
      other.maxConsecutiveSixes == maxConsecutiveSixes &&
      other.captureEnabled == captureEnabled &&
      _sameSet(other.safeSquares, safeSquares) &&
      other.turnTimeoutSeconds == turnTimeoutSeconds &&
      other.timeoutWarningSeconds == timeoutWarningSeconds &&
      other.maxMissedTurns == maxMissedTurns &&
      other.endWhenFirstPlayerFinishes == endWhenFirstPlayerFinishes;

  @override
  int get hashCode => Object.hash(
    tokensPerPlayer,
    Object.hashAllUnordered(entryRolls),
    extraTurnOnSix,
    extraTurnOnCapture,
    extraTurnOnFinish,
    maxConsecutiveSixes,
    captureEnabled,
    Object.hashAllUnordered(safeSquares),
    turnTimeoutSeconds,
    timeoutWarningSeconds,
    maxMissedTurns,
    endWhenFirstPlayerFinishes,
  );
}

bool _sameSet(Set<int> a, Set<int> b) =>
    a.length == b.length && a.containsAll(b);
