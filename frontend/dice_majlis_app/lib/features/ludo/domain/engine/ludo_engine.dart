/// The Ludo rules engine in Dart, for games played on the phone.
///
/// A copy of the server's Python engine (`backend/core/ludo_engine/`) with the
/// same rules, error codes and event names. The server stays the authority for
/// online games; this one runs offline games (vs AI, pass-and-play), which
/// never touch Gold, Diamonds or ratings. The shared test vectors in
/// `shared/ludo/engine_vectors.json` keep the two engines in step.
library;

export 'board.dart';
export 'bot.dart';
export 'dice.dart';
export 'engine.dart';
export 'errors.dart';
export 'events.dart';
export 'rules.dart';
export 'state.dart';
