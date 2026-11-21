import 'dart:math';

/// Dice sources: a Dart copy of `backend/core/ludo_engine/dice.py`.
///
/// The engine never rolls dice itself; the caller rolls and passes the value
/// in. Local games roll with [SecureDice]; tests use [ScriptedDice].
abstract interface class DiceRoller {
  int roll();
}

/// Uses the platform's cryptographic random source, so rolls can't be guessed.
final class SecureDice implements DiceRoller {
  SecureDice() : _random = Random.secure();

  final Random _random;

  @override
  int roll() => _random.nextInt(6) + 1;
}

/// A fixed sequence of values, for tests and for replaying a recorded game.
final class ScriptedDice implements DiceRoller {
  ScriptedDice(Iterable<int> values) : _values = List.unmodifiable(values) {
    for (final value in _values) {
      if (value < 1 || value > 6) {
        throw ArgumentError.value(value, 'values', 'dice values must be 1..6');
      }
    }
  }

  final List<int> _values;
  int _next = 0;

  @override
  int roll() {
    if (_next >= _values.length) {
      throw StateError('ScriptedDice ran out of values');
    }
    return _values[_next++];
  }

  int get remaining => _values.length - _next;
}
