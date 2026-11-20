// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Dice Majlis';

  @override
  String get appTagline => 'PLAY · SOCIALISE · COMPETE';

  @override
  String get commonRetry => 'Try again';

  @override
  String get navHome => 'Home';

  @override
  String get navEvents => 'Events';

  @override
  String get navGameHub => 'Game Hub';

  @override
  String get navBattle => 'Battle';

  @override
  String get navChat => 'Chat';

  @override
  String get navSocial => 'Social';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get comingSoonBadge => 'Soon';

  @override
  String comingSoonNamed(String feature) {
    return '$feature is coming soon.';
  }

  @override
  String get homeSubtitle =>
      'Ludo in the Majlis. Play with friends or the Majlis AI.';

  @override
  String get homePlay => 'Play Ludo';

  @override
  String get homeJoinWithCode => 'Join with a code';

  @override
  String get homeProfileTitle => 'Your profile';

  @override
  String get homeProfileSoon =>
      'Your Player ID, level and coins arrive with accounts.';

  @override
  String get homeShortcuts => 'More';

  @override
  String get homeShop => 'Shop';

  @override
  String get homeCollection => 'Collection';

  @override
  String get homeRankings => 'Rankings';

  @override
  String get homeVip => 'VIP';

  @override
  String get homeNotifications => 'Notifications';

  @override
  String get homeSettings => 'Settings';

  @override
  String get hubTitle => 'Game Hub';

  @override
  String get hubClassicTitle => 'Classic Ludo';

  @override
  String get hubClassicBody =>
      'Play with friends in a private room, or start alone and the Majlis AI joins you.';

  @override
  String get hubCreateRoom => 'Create room';

  @override
  String get hubJoinRoom => 'Join room';

  @override
  String get hubMoreModes => 'More ways to play';

  @override
  String get hubLocalPlay => 'Local play';

  @override
  String get hubLocalPlayBody => 'Pass one phone around the table.';

  @override
  String get hubTeamLudo => 'Team Ludo';

  @override
  String get hubTeamLudoBody => 'Two against two, as partners.';

  @override
  String get hubTournaments => 'Tournaments';

  @override
  String get hubTournamentsBody => 'Brackets with prizes.';

  @override
  String get hubMoreGames => 'More games';

  @override
  String get hubMoreGamesBody => 'Domino and Jackaroo are next.';

  @override
  String get eventsTitle => 'Events';

  @override
  String get eventsBody =>
      'Live events, daily missions and rewards will appear here.';

  @override
  String get battleTitle => 'Battle';

  @override
  String get battleBody =>
      'Quick Match, Ranked and Team Battles are on the way. Until then, start a private room in Game Hub.';

  @override
  String get battleOpenHub => 'Open Game Hub';

  @override
  String get chatTitle => 'Chat';

  @override
  String get chatBody =>
      'Private and group chats with your friends will live here.';

  @override
  String get socialTitle => 'Social';

  @override
  String get socialBody =>
      'Find players, add friends and see what your Majlis is up to.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeSystem => 'Phone';

  @override
  String get settingsThemeHint =>
      'Phone follows your phone\'s dark mode setting.';

  @override
  String get createRoomTitle => 'Create room';

  @override
  String get createRoomMaxPlayers => 'How many players?';

  @override
  String get createRoomHint => 'Start alone and the Majlis AI joins you.';

  @override
  String get createRoomCreate => 'Create';

  @override
  String get createRoomOptionsFailed => 'Couldn\'t load the room options.';

  @override
  String get joinRoomTitle => 'Join room';

  @override
  String get joinRoomCodeLabel => 'Room code';

  @override
  String get joinRoomCodeHint => 'The code your friend shared';

  @override
  String get joinRoomCodeRequired => 'Enter the room code you were given.';

  @override
  String get joinRoomJoin => 'Join';

  @override
  String get waitingRoomTitle => 'Waiting room';

  @override
  String get waitingRoomCodeLabel => 'Room code';

  @override
  String get waitingRoomCopy => 'Copy room code';

  @override
  String get waitingRoomCopied => 'Room code copied';

  @override
  String get waitingRoomPlayers => 'Players';

  @override
  String get waitingRoomEmptySeat => 'Waiting for a player…';

  @override
  String get waitingRoomStart => 'Start game';

  @override
  String get waitingRoomWaitingForHost =>
      'Waiting for the host to start the game…';

  @override
  String get playerTagHost => 'Host';

  @override
  String get playerTagYou => 'You';

  @override
  String get playerTagBot => 'AI';

  @override
  String get gameStatusSyncing => 'Syncing…';

  @override
  String get gameStatusYourTurn => 'Your turn';

  @override
  String get gameStatusOpponentTurn => 'Opponent\'s turn';

  @override
  String gameStatusWithSeconds(String status, int seconds) {
    return '$status · ${seconds}s';
  }

  @override
  String get gameReconnecting => 'Reconnecting…';

  @override
  String get gameMoving => 'Moving…';

  @override
  String get gameRollDice => 'Roll the dice';

  @override
  String get gameUnknownPlayer => 'A player';

  @override
  String get gameOverTitle => 'Game over';

  @override
  String get gameOverWon => 'You win!';

  @override
  String get gameOverLost => 'You lost';

  @override
  String get gameOverHome => 'Back to home';

  @override
  String get gameTimeoutSelf => 'Time ran out, so we played for you.';

  @override
  String gameTimeoutSelfWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more turns',
      one: '1 more turn',
    );
    return 'Time ran out, so we played for you. Miss $_temp0 in a row and you leave the game.';
  }

  @override
  String gameTimeoutOther(String name) {
    return '$name ran out of time.';
  }

  @override
  String get gameRemovedSelfIdle =>
      'You were removed for missing too many turns.';

  @override
  String get gameLeftSelf => 'You left the game.';

  @override
  String gameRemovedOtherIdle(String name) {
    return '$name was removed for being idle.';
  }

  @override
  String gameLeftOther(String name) {
    return '$name left the game.';
  }

  @override
  String get errorNetwork =>
      'Can\'t reach the server. Check your connection and try again.';

  @override
  String get errorRoomNotFound =>
      'No room with that code. Check the code and try again.';

  @override
  String get errorRoomFull => 'That room is full.';

  @override
  String get errorGameAlreadyStarted => 'That game has already started.';

  @override
  String get errorGameNotStarted => 'The game hasn\'t started yet.';

  @override
  String get errorNotHost => 'Only the host can start the game.';

  @override
  String get errorNotYourSeat =>
      'This device isn\'t in that seat any more. Join the room again.';

  @override
  String get errorNotYourTurn => 'It\'s not your turn.';

  @override
  String get errorWrongPhase => 'You can\'t do that right now.';

  @override
  String get errorIllegalMove => 'That token can\'t move with this roll.';

  @override
  String get errorGameFinished => 'This game is over.';

  @override
  String get errorTryAgain => 'The game just changed. Please try again.';

  @override
  String get errorLegacyGame =>
      'This game was started before an update. Please start a new one.';

  @override
  String get errorInvalidInput =>
      'The server didn\'t accept that. Please check and try again.';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get notFoundTitle => 'Page not found';

  @override
  String get notFoundGoHome => 'Go home';
}
