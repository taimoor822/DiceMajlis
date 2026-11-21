import 'package:flutter/material.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/routing/app_routes.dart';
import '../games/domain/game_catalog.dart';
import '../games/game_registry.dart';
import 'presentation/game_board_screen.dart';

/// Ludo in the app's game registry.
class LudoModule extends GameModule {
  const LudoModule();

  @override
  String get gameType => GameChoice.ludo;

  @override
  IconData get icon => Icons.casino;

  @override
  String name(AppLocalizations l10n) => l10n.gameLudo;

  @override
  String description(AppLocalizations l10n) => l10n.hubClassicBody;

  @override
  String variantName(AppLocalizations l10n, String code) => switch (code) {
    GameChoice.classic => l10n.variantClassic,
    _ => code,
  };

  @override
  Widget onlineGame(String roomCode) => GameBoardScreen(roomCode: roomCode);

  @override
  String? get offlineRoute => AppRoutes.localPlay;

  // Keys are the server's rule names (ludo_engine/rules.py).
  @override
  String? ruleName(AppLocalizations l10n, String key) => switch (key) {
    'turn_timeout_seconds' => l10n.ruleTurnTime,
    'capture_enabled' => l10n.ruleCaptures,
    'extra_turn_on_six' => l10n.ruleExtraTurnOnSix,
    'end_when_first_player_finishes' => l10n.ruleGameEnds,
    _ => null,
  };

  @override
  String ruleValue(AppLocalizations l10n, String key, Object? value) =>
      switch ((key, value)) {
        ('turn_timeout_seconds', final int seconds) => l10n.ruleSeconds(
          seconds,
        ),
        ('end_when_first_player_finishes', true) => l10n.ruleEndsFirstHome,
        ('end_when_first_player_finishes', false) => l10n.ruleEndsAllPlaces,
        _ => super.ruleValue(l10n, key, value),
      };
}
