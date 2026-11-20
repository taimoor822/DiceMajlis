/// Engine errors: a Dart copy of `backend/core/ludo_engine/errors.py`.
///
/// Each has the same stable [code] as the server, so the app can show the same
/// text for a rejected local action as for a rejected online one.
class EngineError implements Exception {
  const EngineError(this.message);

  final String message;

  String get code => 'engine_error';

  @override
  String toString() => '$runtimeType($code): $message';
}

class InvalidSetup extends EngineError {
  const InvalidSetup(super.message);

  @override
  String get code => 'invalid_setup';
}

class InvalidAction extends EngineError {
  const InvalidAction(super.message);

  @override
  String get code => 'invalid_action';
}

class GameNotActive extends EngineError {
  const GameNotActive(super.message);

  @override
  String get code => 'game_not_active';
}

class UnknownPlayer extends EngineError {
  const UnknownPlayer(super.message);

  @override
  String get code => 'unknown_player';
}

class NotYourTurn extends EngineError {
  const NotYourTurn(super.message);

  @override
  String get code => 'not_your_turn';
}

/// Rolling when a move is due, or moving before rolling.
class WrongPhase extends EngineError {
  const WrongPhase(super.message);

  @override
  String get code => 'wrong_phase';
}

class InvalidDiceValue extends EngineError {
  const InvalidDiceValue(super.message);

  @override
  String get code => 'invalid_dice_value';
}

class IllegalMove extends EngineError {
  const IllegalMove(super.message);

  @override
  String get code => 'illegal_move';
}
