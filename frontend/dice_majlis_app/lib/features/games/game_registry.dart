import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../ludo/ludo_module.dart';
import 'domain/game_catalog.dart';

/// Everything the app knows about one game: its names, its icon and its
/// screens. The server's game registry says which games exist online; the
/// app shows the ones it has a module for (PLATFORM §3).
///
/// Adding a game (Domino, Jackaroo) = its feature folder + a module here.
abstract class GameModule {
  const GameModule();

  /// The server's `game_type`.
  String get gameType;

  IconData get icon;

  /// "Ludo".
  String name(AppLocalizations l10n);

  /// One line for its Game Hub card.
  String description(AppLocalizations l10n);

  /// "Classic". A variant the app doesn't know yet shows its code.
  String variantName(AppLocalizations l10n, String code);

  /// The board for an online game in room [roomCode].
  Widget onlineGame(String roomCode);

  /// Route of its offline game on this phone, if it has one.
  String? get offlineRoute => null;
}

/// "Classic Ludo".
String gameTitle(AppLocalizations l10n, GameModule module, String variant) =>
    l10n.gameTitle(module.variantName(l10n, variant), module.name(l10n));

/// Every game this version of the app can draw, by `game_type`.
final gameModulesProvider = Provider<Map<String, GameModule>>(
  (ref) => const {GameChoice.ludo: LudoModule()},
);
