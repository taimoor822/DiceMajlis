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
  String get commonCancel => 'Cancel';

  @override
  String get splashOffline =>
      'Can\'t reach the Majlis server. Check your connection and try again.';

  @override
  String get splashPlayOffline => 'Play offline';

  @override
  String get welcomeBody =>
      'Ludo in the Majlis. Play with friends, family or the Majlis AI.';

  @override
  String get welcomePlayAsGuest => 'Play as guest';

  @override
  String get welcomePlayOffline => 'Play offline on this phone';

  @override
  String get welcomeGuestHint =>
      'You get a permanent Player ID right away. Your guest account lives on this device; adding email, Google or Apple later will keep it safe.';

  @override
  String get welcomeEmail => 'Sign in with email';

  @override
  String get welcomeEmailSubtitle => 'Or create an account with your email';

  @override
  String get welcomeGoogle => 'Continue with Google';

  @override
  String get welcomeApple => 'Continue with Apple';

  @override
  String get emailTitle => 'Email';

  @override
  String get emailModeSignIn => 'Sign in';

  @override
  String get emailModeCreate => 'Create account';

  @override
  String get emailField => 'Email';

  @override
  String get emailFieldInvalid => 'Enter a valid email address.';

  @override
  String get passwordField => 'Password';

  @override
  String get newPasswordField => 'New password';

  @override
  String get passwordFieldEmpty => 'Enter your password.';

  @override
  String get passwordShow => 'Show password';

  @override
  String get passwordHide => 'Hide password';

  @override
  String get passwordHint => 'Use letters and numbers. Avoid common passwords.';

  @override
  String get emailSignIn => 'Sign in';

  @override
  String get emailCreate => 'Create account';

  @override
  String get emailForgot => 'Forgot password?';

  @override
  String get forgotTitle => 'Forgot password';

  @override
  String get forgotIntro =>
      'Enter your account\'s email. We\'ll send you a 6-digit code.';

  @override
  String get forgotSend => 'Send code';

  @override
  String forgotCodeSent(String email) {
    return 'If $email has an account, a code is on its way. It works for one hour.';
  }

  @override
  String get forgotCode => '6-digit code';

  @override
  String get forgotCodeInvalid => 'Enter the 6 digits from the email.';

  @override
  String get forgotChange => 'Change password';

  @override
  String get forgotResend => 'Send a new code';

  @override
  String get saveAccountTitle => 'Save your account';

  @override
  String get saveAccountIntro =>
      'Add your email and a password. You keep your Player ID and everything on this account, and you can sign in on any phone.';

  @override
  String get saveAccountButton => 'Save account';

  @override
  String get saveAccountDone =>
      'Account saved. You can now sign in with your email.';

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
  String homePlayerId(String id) {
    return 'Player ID $id';
  }

  @override
  String get homeCopyPlayerId => 'Copy Player ID';

  @override
  String get homePlayerIdCopied => 'Player ID copied';

  @override
  String get homeGuestTag => 'Guest';

  @override
  String get homeProfileHint => 'Tap to edit your profile';

  @override
  String homeLevel(int level) {
    return 'Level $level';
  }

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileName => 'Name';

  @override
  String get profileNameSave => 'Save name';

  @override
  String get profileSaved => 'Saved';

  @override
  String get profileAvatar => 'Avatar';

  @override
  String get profileAvatarPhotoSoon => 'Your own photo is coming soon.';

  @override
  String get profileCountry => 'Country';

  @override
  String get profileCountryNone => 'Not shown';

  @override
  String get profileCountryChoose => 'Choose';

  @override
  String get profileCountryHide => 'Don\'t show my country';

  @override
  String get profileLanguages => 'Languages you speak';

  @override
  String profileLanguagesHint(int count) {
    return 'Pick up to $count.';
  }

  @override
  String profileLevelXp(int xp, int next) {
    return '$xp / $next XP';
  }

  @override
  String get profileXpSoon => 'Earning XP from games is coming soon.';

  @override
  String get profileOptionsFailed => 'Couldn\'t load the profile choices.';

  @override
  String get languageEn => 'English';

  @override
  String get languageAr => 'Arabic';

  @override
  String get languageUr => 'Urdu';

  @override
  String get languagePa => 'Punjabi';

  @override
  String nameLength(int min, int max) {
    return 'Names are $min to $max characters.';
  }

  @override
  String get nameCharacters =>
      'Use letters, numbers, spaces and _ - . \' only, with at least one letter.';

  @override
  String get nameNotAllowed => 'That name isn\'t allowed. Please pick another.';

  @override
  String get homeShortcuts => 'More';

  @override
  String get homeWallet => 'Wallet';

  @override
  String get currencyGold => 'Gold';

  @override
  String get currencyDiamond => 'Diamonds';

  @override
  String get dailyTitle => 'Daily reward';

  @override
  String dailyDay(int day) {
    return 'Day $day';
  }

  @override
  String get dailyClaim => 'Claim';

  @override
  String dailyClaimed(int day) {
    return 'Claimed! Come back tomorrow for day $day.';
  }

  @override
  String dailyNextIn(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours',
      one: '1 hour',
      zero: 'less than an hour',
    );
    return 'Next reward in $_temp0';
  }

  @override
  String get dailyHint =>
      'Come back every day: rewards grow for 7 days in a row. Miss a day and it starts again.';

  @override
  String dailyGot(String amount) {
    return 'You got $amount';
  }

  @override
  String get dailyFailed => 'Couldn\'t load the daily reward.';

  @override
  String get walletTitle => 'Wallet';

  @override
  String get walletHistory => 'History';

  @override
  String get walletEmpty =>
      'Nothing yet. Claim your daily reward to get started.';

  @override
  String get walletLoadMore => 'Show more';

  @override
  String get walletFailed => 'Couldn\'t load your wallet.';

  @override
  String get walletEarnHint =>
      'Earn gold every day. Buying gold and diamonds comes later.';

  @override
  String get walletTypeDaily => 'Daily reward';

  @override
  String get walletTypeAdminGrant => 'From the Dice Majlis team';

  @override
  String get walletTypeAdminRevoke => 'Taken back by the team';

  @override
  String get walletTypeReversal => 'Correction';

  @override
  String get walletTypeOther => 'Other';

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
  String get hubCatalogFailed => 'Couldn\'t load the games';

  @override
  String get hubUpdateForGames =>
      'New games are available. Update the app to play them.';

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
  String get hubLocalPlay => 'Play on this phone';

  @override
  String get hubLocalPlayBody =>
      'Play the Majlis AI or pass one phone around the table. Works offline.';

  @override
  String get hubLocalPlayStart => 'Play offline';

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
  String get settingsAccount => 'Account';

  @override
  String get settingsGuestAccount => 'Guest account';

  @override
  String get settingsGuestSaveHint =>
      'Save your account so you don\'t lose it if you change or reset your phone.';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsSignOutTitle => 'Sign out?';

  @override
  String get settingsSignOutGuest =>
      'You\'re playing as a guest. If you sign out, this account and its Player ID can\'t be recovered.';

  @override
  String get settingsSignOutBody => 'You can sign in again any time.';

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
  String get waitingRoomLeave => 'Leave room';

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
  String get waitingRoomStatusWaiting => 'Waiting for everyone to be ready…';

  @override
  String get waitingRoomStatusReady => 'Everyone is ready.';

  @override
  String get waitingRoomStatusAlone =>
      'Start now and the Majlis AI plays with you, or invite friends first.';

  @override
  String waitingRoomStartingIn(int seconds) {
    return 'Starting in $seconds…';
  }

  @override
  String get waitingRoomReady => 'I\'m ready';

  @override
  String get waitingRoomUnready => 'Not ready yet';

  @override
  String get waitingRoomPlayerReady => 'Ready';

  @override
  String get waitingRoomPlayerNotReady => 'Not ready';

  @override
  String get waitingRoomLock => 'Lock the room';

  @override
  String get waitingRoomUnlock => 'Unlock the room';

  @override
  String get waitingRoomLocked => 'Locked: invited players only';

  @override
  String get waitingRoomInvite => 'Invite by Player ID';

  @override
  String get waitingRoomInviteHint => '9-digit Player ID';

  @override
  String get waitingRoomInviteSend => 'Send invite';

  @override
  String get waitingRoomInviteSent => 'Invite sent';

  @override
  String get waitingRoomInviteInvalid => 'Enter a 9-digit Player ID.';

  @override
  String get waitingRoomCancel => 'Cancel';

  @override
  String get waitingRoomPlayerMenu => 'Player options';

  @override
  String get waitingRoomMakeHost => 'Make host';

  @override
  String get waitingRoomRemove => 'Remove from the room';

  @override
  String get waitingRoomKicked => 'The host removed you from the room.';

  @override
  String get waitingRoomRules => 'Rules';

  @override
  String get waitingRoomRulesHint =>
      'Tap a rule to change it. Everyone gets ready again after a change.';

  @override
  String get ruleTurnTime => 'Turn time';

  @override
  String get ruleCaptures => 'Captures';

  @override
  String get ruleExtraTurnOnSix => 'Extra turn on a six';

  @override
  String get ruleGameEnds => 'The game ends';

  @override
  String get ruleEndsFirstHome => 'When the first player is home';

  @override
  String get ruleEndsAllPlaces => 'When every place is decided';

  @override
  String ruleSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String get ruleOn => 'On';

  @override
  String get ruleOff => 'Off';

  @override
  String get invitesTitle => 'Invites';

  @override
  String inviteFrom(String name, String game) {
    return '$name invited you to $game';
  }

  @override
  String get inviteJoin => 'Join';

  @override
  String get inviteDecline => 'Decline';

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
  String get gameLeave => 'Leave game';

  @override
  String get gameLeaveTitle => 'Leave this game?';

  @override
  String get gameLeaveBody =>
      'You\'ll lose this game and can\'t come back to it.';

  @override
  String get gameLeaveConfirm => 'Leave';

  @override
  String get gameOverTitle => 'Game over';

  @override
  String get gameOverWon => 'You win!';

  @override
  String get gameOverLost => 'You lost';

  @override
  String get gameOverHome => 'Back to home';

  @override
  String get gameOverPlayAgain => 'Play again';

  @override
  String get gameOverWaitingForOthers => 'Waiting for the others to say yes…';

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
  String get errorNotHost => 'Only the host can do that.';

  @override
  String get errorNotYourSeat => 'That isn\'t your seat.';

  @override
  String get errorNotInRoom => 'You\'re not in this room any more.';

  @override
  String get errorAlreadyInGame =>
      'You\'re still playing another game. Finish or leave it first.';

  @override
  String get errorSignedOut => 'You were signed out. Please sign in again.';

  @override
  String get errorRateLimited =>
      'Too many tries. Please wait a moment and try again.';

  @override
  String get errorInvalidCredentials => 'Wrong email or password.';

  @override
  String get errorEmailTaken =>
      'That email already has an account. Sign in instead.';

  @override
  String get errorAlreadySaved => 'This account is already saved.';

  @override
  String get errorInvalidCode =>
      'That code isn\'t right. Check the email and try again.';

  @override
  String get errorCodeExpired => 'That code has expired. Ask for a new one.';

  @override
  String get errorTooManyCodeTries =>
      'Too many wrong codes. Ask for a new one.';

  @override
  String get errorPasswordTooShort => 'That password is too short.';

  @override
  String get errorPasswordTooCommon => 'That password is too easy to guess.';

  @override
  String get errorPasswordNumeric => 'Use letters too, not only numbers.';

  @override
  String get errorPasswordSimilar =>
      'That password is too close to your email.';

  @override
  String get errorAlreadyClaimed => 'Today\'s reward is already claimed.';

  @override
  String get errorInsufficientFunds => 'You don\'t have enough for that.';

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
  String get errorNotEveryoneReady => 'Everyone has to be ready first.';

  @override
  String get errorPlayerKicked => 'The host removed you from this room.';

  @override
  String get errorRoomLocked => 'This room is for invited players only.';

  @override
  String get errorGameStarting => 'That game is starting. Try another room.';

  @override
  String get errorPlayerNotFound => 'No player with that ID.';

  @override
  String get errorCannotInviteYourself => 'That\'s your own Player ID.';

  @override
  String get errorAlreadyInRoom => 'They\'re already in this room.';

  @override
  String get errorInvalidOption => 'That rule can\'t be set that way.';

  @override
  String get errorGameNotFinished => 'The game isn\'t over yet.';

  @override
  String get errorRoomClosed => 'This room is closed.';

  @override
  String get errorInvalidInput =>
      'The server didn\'t accept that. Please check and try again.';

  @override
  String get gameLudo => 'Ludo';

  @override
  String get variantClassic => 'Classic';

  @override
  String gameTitle(String variant, String game) {
    return '$variant $game';
  }

  @override
  String get gameUnsupportedTitle => 'Update the app to play this game';

  @override
  String get gameUnsupportedBody =>
      'This room plays a game this version of Dice Majlis can\'t show yet. Update the app, or leave the game to play something else.';

  @override
  String get localSetupTitle => 'Play on this phone';

  @override
  String get localSetupBody =>
      'Play the Majlis AI, or pass one phone around the table. Offline games don\'t earn Gold or Diamonds and don\'t change your rating.';

  @override
  String get localSetupPlayers => 'Players';

  @override
  String get localSetupSeats => 'Who plays each colour';

  @override
  String get localSeatHuman => 'Player';

  @override
  String get localSeatAi => 'AI';

  @override
  String get localSetupPlayOn => 'Play on for every place';

  @override
  String get localSetupPlayOnBody =>
      'Keep playing after the first player gets home.';

  @override
  String get localSetupStart => 'Start game';

  @override
  String get colorRed => 'Red';

  @override
  String get colorBlue => 'Blue';

  @override
  String get colorGreen => 'Green';

  @override
  String get colorYellow => 'Yellow';

  @override
  String localNamePlayer(int number) {
    return 'Player $number';
  }

  @override
  String get localNameAi => 'Majlis AI';

  @override
  String localNameAiNumbered(int number) {
    return 'Majlis AI $number';
  }

  @override
  String get localGameTitle => 'Offline game';

  @override
  String get localStatusYourRoll => 'Your turn: roll the dice';

  @override
  String localStatusRoll(String name) {
    return '$name: roll the dice';
  }

  @override
  String get localStatusYourMove => 'Pick a token to move';

  @override
  String localStatusMove(String name) {
    return '$name: pick a token';
  }

  @override
  String localStatusAi(String name) {
    return '$name is playing…';
  }

  @override
  String localNoticeNoMoves(String name) {
    return '$name can\'t move';
  }

  @override
  String localNoticeTooManySixes(String name) {
    return '$name rolled too many sixes';
  }

  @override
  String localNoticeCaptured(String name) {
    return '$name sent a token back to base!';
  }

  @override
  String localNoticeHome(String name, int place) {
    return '$name got every token home: place $place!';
  }

  @override
  String localWinner(String name) {
    return '$name wins!';
  }

  @override
  String get localResultsTitle => 'Game over';

  @override
  String localPlaceShort(int place) {
    return '#$place';
  }

  @override
  String get localPlayAgain => 'Play again';

  @override
  String get localDone => 'Done';

  @override
  String get localLeaveTitle => 'Leave this game?';

  @override
  String get localLeaveBody =>
      'Offline games aren\'t saved, so this one will end.';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get notFoundTitle => 'Page not found';

  @override
  String get notFoundGoHome => 'Go home';
}
