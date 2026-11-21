import '../../../core/l10n/generated/app_localizations.dart';
import '../../ludo/domain/engine/ludo_engine.dart';
import '../domain/local_game_setup.dart';

/// "You" when one person plays, else "Player 1", "Player 2"…; the AI is
/// "Majlis AI" (numbered when there is more than one).
String localPlayerName(AppLocalizations l10n, LocalGameSetup setup, int seat) {
  final kind = setup.kinds[seat]!;
  final same = setup.seats.where((s) => setup.kinds[s] == kind).toList();
  final number = same.indexOf(seat) + 1;
  if (kind == LocalSeatKind.human) {
    return same.length == 1 ? l10n.playerTagYou : l10n.localNamePlayer(number);
  }
  return same.length == 1 ? l10n.localNameAi : l10n.localNameAiNumbered(number);
}

String seatColorName(AppLocalizations l10n, int seat) =>
    switch (LudoBoard.seatColors[seat]) {
      'red' => l10n.colorRed,
      'blue' => l10n.colorBlue,
      'green' => l10n.colorGreen,
      _ => l10n.colorYellow,
    };
