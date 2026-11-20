import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ludo/domain/engine/ludo_engine.dart';
import 'local_game_controller.dart';
import 'local_game_setup.dart';

/// The players picked on the setup screen for the next offline game. Kept in
/// memory only: offline games aren't saved.
final localGameSetupProvider =
    NotifierProvider<LocalGameSetupController, LocalGameSetup?>(
      LocalGameSetupController.new,
    );

class LocalGameSetupController extends Notifier<LocalGameSetup?> {
  @override
  LocalGameSetup? build() => null;

  void set(LocalGameSetup setup) => state = setup;
}

/// Dice for offline games (tests swap in `ScriptedDice`).
final localDiceProvider = Provider<DiceRoller>((ref) => SecureDice());

/// How fast offline games are shown (tests use `LocalPlayTiming.instant`).
final localPlayTimingProvider = Provider<LocalPlayTiming>(
  (ref) => LocalPlayTiming.normal,
);
