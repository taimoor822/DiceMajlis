import 'board.dart';
import 'engine.dart';
import 'errors.dart';
import 'state.dart';

/// Deterministic move choice: a Dart copy of `backend/core/ludo_engine/bot.py`.
/// Used by the Majlis AI in local games and for auto-moves on timeout.
///
/// Same state in, same move out (ties go to the lowest token index), so the
/// shared test vectors can check every choice against the server's bot.
abstract final class LudoBot {
  static const int finishScore = 1000;
  static const int captureScore = 500;
  static const int enterScore = 300;
  static const int escapeDangerScore = 120;
  static const int safeLandingScore = 60;
  static const int dangerPenalty = 150;

  static Move chooseMove(GameState state) {
    final moves = LudoEngine.legalMoves(state);
    if (moves.isEmpty) {
      throw const IllegalMove('no legal moves to choose from');
    }
    var best = moves.first;
    var bestScore = scoreMove(state, best);
    for (final m in moves.skip(1)) {
      final score = scoreMove(state, m);
      if (score > bestScore ||
          (score == bestScore && m.tokenIndex < best.tokenIndex)) {
        best = m;
        bestScore = score;
      }
    }
    return best;
  }

  static int scoreMove(GameState state, Move move) {
    final seat = state.currentPlayer.seat;
    var score = _atLeastZero(move.toProgress) - _atLeastZero(move.fromProgress);

    if (move.finishesToken) score += finishScore;
    score += captureScore * move.captures.length;
    if (move.entersBoard) score += enterScore;

    final fromSquare = LudoBoard.absoluteSquare(seat, move.fromProgress);
    if (fromSquare != null && _isThreatened(state, fromSquare)) {
      score += escapeDangerScore;
    }

    final toSquare = move.toSquare;
    if (toSquare == null) {
      if (!move.finishesToken && !move.entersBoard) {
        score += safeLandingScore; // home column: nobody can reach it
      }
    } else if (state.rules.safeSquares.contains(toSquare)) {
      score += safeLandingScore;
    } else if (_isThreatened(state, toSquare, ignoreCaptured: move)) {
      score -= dangerPenalty;
    }
    return score;
  }

  /// Could an opponent land on [square] with one roll (1..6) next turn?
  static bool _isThreatened(
    GameState state,
    int square, {
    Move? ignoreCaptured,
  }) {
    if (state.rules.safeSquares.contains(square) ||
        !state.rules.captureEnabled) {
      return false;
    }
    final captured = {
      for (final c in ignoreCaptured?.captures ?? const <Capture>[])
        '${c.playerId}\u0000${c.tokenIndex}',
    };
    final me = state.currentPlayer.playerId;
    for (final other in state.players) {
      if (other.playerId == me || other.status != PlayerStatus.active) continue;
      for (var t = 0; t < other.tokens.length; t++) {
        if (captured.contains('${other.playerId}\u0000$t')) continue;
        final progress = other.tokens[t];
        final theirSquare = LudoBoard.absoluteSquare(other.seat, progress);
        if (theirSquare == null) continue;
        final distance = (square - theirSquare) % LudoBoard.trackLength;
        if (distance >= 1 &&
            distance <= 6 &&
            progress + distance <= LudoBoard.lastTrackProgress) {
          return true;
        }
      }
    }
    return false;
  }

  static int _atLeastZero(int value) => value < 0 ? 0 : value;
}
