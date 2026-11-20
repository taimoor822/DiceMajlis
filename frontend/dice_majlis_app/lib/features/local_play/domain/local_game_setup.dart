import '../../ludo/domain/engine/ludo_engine.dart';

/// Who plays a seat in a game on this phone.
enum LocalSeatKind { human, ai }

/// The players of an offline game: 2 to 4 seats, each a person or the AI.
/// Seats follow the engine's defaults (2 players sit opposite each other).
final class LocalGameSetup {
  LocalGameSetup({required Map<int, LocalSeatKind> kinds, this.playOn = false})
    : kinds = Map.unmodifiable(kinds) {
    if (kinds.length < LudoBoard.minPlayers ||
        kinds.length > LudoBoard.maxPlayers) {
      throw ArgumentError.value(kinds.length, 'kinds', 'needs 2 to 4 seats');
    }
  }

  /// You (red) against the Majlis AI.
  factory LocalGameSetup.standard() => LocalGameSetup.forPlayers(2);

  /// [count] players: the first seat is a person, the rest the AI.
  factory LocalGameSetup.forPlayers(int count, {bool playOn = false}) {
    final seats = LudoBoard.defaultSeatsFor(count);
    return LocalGameSetup(
      kinds: {
        for (final seat in seats)
          seat: seat == seats.first ? LocalSeatKind.human : LocalSeatKind.ai,
      },
      playOn: playOn,
    );
  }

  /// Seat → who plays it.
  final Map<int, LocalSeatKind> kinds;

  /// Keep playing after the first player gets home, for every place.
  final bool playOn;

  int get playerCount => kinds.length;

  List<int> get seats => kinds.keys.toList()..sort();

  int get humanCount =>
      kinds.values.where((k) => k == LocalSeatKind.human).length;

  /// The engine's standard rules; only the ending can be changed here.
  Rules get rules =>
      Rules.standard.copyWith(endWhenFirstPlayerFinishes: !playOn);

  static String playerIdFor(int seat) => 'seat-$seat';

  /// Same people where their seats remain; new seats are the AI.
  LocalGameSetup withPlayerCount(int count) => LocalGameSetup(
    kinds: {
      for (final seat in LudoBoard.defaultSeatsFor(count))
        seat: kinds[seat] ?? LocalSeatKind.ai,
    },
    playOn: playOn,
  );

  LocalGameSetup withKind(int seat, LocalSeatKind kind) =>
      LocalGameSetup(kinds: {...kinds, seat: kind}, playOn: playOn);

  LocalGameSetup withPlayOn(bool value) =>
      LocalGameSetup(kinds: kinds, playOn: value);
}
