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
}
