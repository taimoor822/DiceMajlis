/// Board geometry: a Dart copy of `backend/core/ludo_engine/board.py`.
///
/// Every token position is its *progress* from its own seat's start square:
///   -1        in base
///   0..50     shared track (0 is the seat's start square)
///   51..55    the seat's private home column (cannot be captured)
///   56        home (finished)
///
/// Progress is relative to the seat, so compare two players' tokens with
/// [LudoBoard.absoluteSquare], never with raw progress.
///
/// The Python engine is the source of truth; the shared test vectors
/// (`shared/ludo/engine_vectors.json`) check that these numbers match it.
abstract final class LudoBoard {
  static const int trackLength = 52;
  static const int seatCount = 4;
  static const int minPlayers = 2;
  static const int maxPlayers = seatCount;
  static const int seatSpacing = trackLength ~/ seatCount; // 13

  static const int baseProgress = -1;
  static const int startProgress = 0;
  static const int lastTrackProgress = 50;
  static const int firstHomeColumnProgress = 51;
  static const int homeColumnLength = 5;
  static const int homeProgress =
      firstHomeColumnProgress + homeColumnLength; // 56

  /// Seat order around the track (clockwise).
  static const List<String> seatColors = ['red', 'blue', 'green', 'yellow'];

  /// The star (safe) square sits 8 squares after each seat's start square.
  static const int starOffsetFromStart = 8;

  static void _checkSeat(int seat) {
    if (seat < 0 || seat >= seatCount) {
      throw ArgumentError.value(seat, 'seat', 'must be 0..${seatCount - 1}');
    }
  }

  /// Absolute track square where a seat's tokens enter the board.
  static int startSquare(int seat) {
    _checkSeat(seat);
    return seat * seatSpacing;
  }

  static bool isInBase(int progress) => progress == baseProgress;

  static bool isOnTrack(int progress) =>
      progress >= startProgress && progress <= lastTrackProgress;

  static bool isInHomeColumn(int progress) =>
      progress >= firstHomeColumnProgress && progress < homeProgress;

  static bool isHome(int progress) => progress == homeProgress;

  static bool isValidProgress(int progress) =>
      progress == baseProgress ||
      (progress >= startProgress && progress <= homeProgress);

  /// Shared-track square (0..51) for a token, or null when the token is in
  /// base, in its private home column, or home. Only tokens with a square can
  /// meet (and capture) tokens of other seats.
  static int? absoluteSquare(int seat, int progress) {
    _checkSeat(seat);
    if (!isOnTrack(progress)) return null;
    return (progress + seat * seatSpacing) % trackLength;
  }

  /// Every seat's start square plus every star square.
  static Set<int> defaultSafeSquares() {
    final starts = {
      for (var seat = 0; seat < seatCount; seat++) seat * seatSpacing,
    };
    final stars = {
      for (final s in starts) (s + starOffsetFromStart) % trackLength,
    };
    return {...starts, ...stars};
  }

  /// Seats used when the caller does not choose them: 2 players sit opposite.
  static List<int> defaultSeatsFor(int playerCount) {
    if (playerCount == 2) return const [0, 2];
    if (playerCount == 3 || playerCount == 4) {
      return List<int>.generate(playerCount, (i) => i);
    }
    throw ArgumentError.value(
      playerCount,
      'playerCount',
      'Ludo needs $minPlayers to $maxPlayers players',
    );
  }
}
