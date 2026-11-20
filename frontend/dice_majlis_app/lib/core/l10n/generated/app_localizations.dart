import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Dice Majlis'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'PLAY · SOCIALISE · COMPETE'**
  String get appTagline;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonRetry;

  /// No description provided for @homeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ludo in the Majlis. Play with friends or the Majlis AI.'**
  String get homeSubtitle;

  /// No description provided for @homeCreateRoom.
  ///
  /// In en, this message translates to:
  /// **'Create room'**
  String get homeCreateRoom;

  /// No description provided for @homeJoinRoom.
  ///
  /// In en, this message translates to:
  /// **'Join room'**
  String get homeJoinRoom;

  /// No description provided for @createRoomTitle.
  ///
  /// In en, this message translates to:
  /// **'Create room'**
  String get createRoomTitle;

  /// No description provided for @createRoomMaxPlayers.
  ///
  /// In en, this message translates to:
  /// **'How many players?'**
  String get createRoomMaxPlayers;

  /// No description provided for @createRoomHint.
  ///
  /// In en, this message translates to:
  /// **'Start alone and the Majlis AI joins you.'**
  String get createRoomHint;

  /// No description provided for @createRoomCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createRoomCreate;

  /// No description provided for @createRoomOptionsFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the room options.'**
  String get createRoomOptionsFailed;

  /// No description provided for @joinRoomTitle.
  ///
  /// In en, this message translates to:
  /// **'Join room'**
  String get joinRoomTitle;

  /// No description provided for @joinRoomCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Room code'**
  String get joinRoomCodeLabel;

  /// No description provided for @joinRoomCodeHint.
  ///
  /// In en, this message translates to:
  /// **'The code your friend shared'**
  String get joinRoomCodeHint;

  /// No description provided for @joinRoomCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the room code you were given.'**
  String get joinRoomCodeRequired;

  /// No description provided for @joinRoomJoin.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get joinRoomJoin;

  /// No description provided for @waitingRoomTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting room'**
  String get waitingRoomTitle;

  /// No description provided for @waitingRoomCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Room code'**
  String get waitingRoomCodeLabel;

  /// No description provided for @waitingRoomCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy room code'**
  String get waitingRoomCopy;

  /// No description provided for @waitingRoomCopied.
  ///
  /// In en, this message translates to:
  /// **'Room code copied'**
  String get waitingRoomCopied;

  /// No description provided for @waitingRoomPlayers.
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get waitingRoomPlayers;

  /// No description provided for @waitingRoomEmptySeat.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a player…'**
  String get waitingRoomEmptySeat;

  /// No description provided for @waitingRoomStart.
  ///
  /// In en, this message translates to:
  /// **'Start game'**
  String get waitingRoomStart;

  /// No description provided for @waitingRoomWaitingForHost.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the host to start the game…'**
  String get waitingRoomWaitingForHost;

  /// No description provided for @playerTagHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get playerTagHost;

  /// No description provided for @playerTagYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get playerTagYou;

  /// No description provided for @playerTagBot.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get playerTagBot;

  /// No description provided for @gameStatusSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get gameStatusSyncing;

  /// No description provided for @gameStatusYourTurn.
  ///
  /// In en, this message translates to:
  /// **'Your turn'**
  String get gameStatusYourTurn;

  /// No description provided for @gameStatusOpponentTurn.
  ///
  /// In en, this message translates to:
  /// **'Opponent\'s turn'**
  String get gameStatusOpponentTurn;

  /// No description provided for @gameStatusWithSeconds.
  ///
  /// In en, this message translates to:
  /// **'{status} · {seconds}s'**
  String gameStatusWithSeconds(String status, int seconds);

  /// No description provided for @gameReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get gameReconnecting;

  /// No description provided for @gameMoving.
  ///
  /// In en, this message translates to:
  /// **'Moving…'**
  String get gameMoving;

  /// No description provided for @gameRollDice.
  ///
  /// In en, this message translates to:
  /// **'Roll the dice'**
  String get gameRollDice;

  /// No description provided for @gameUnknownPlayer.
  ///
  /// In en, this message translates to:
  /// **'A player'**
  String get gameUnknownPlayer;

  /// No description provided for @gameOverTitle.
  ///
  /// In en, this message translates to:
  /// **'Game over'**
  String get gameOverTitle;

  /// No description provided for @gameOverWon.
  ///
  /// In en, this message translates to:
  /// **'You win!'**
  String get gameOverWon;

  /// No description provided for @gameOverLost.
  ///
  /// In en, this message translates to:
  /// **'You lost'**
  String get gameOverLost;

  /// No description provided for @gameOverHome.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get gameOverHome;

  /// No description provided for @gameTimeoutSelf.
  ///
  /// In en, this message translates to:
  /// **'Time ran out, so we played for you.'**
  String get gameTimeoutSelf;

  /// No description provided for @gameTimeoutSelfWarning.
  ///
  /// In en, this message translates to:
  /// **'Time ran out, so we played for you. Miss {count, plural, =1{1 more turn} other{{count} more turns}} in a row and you leave the game.'**
  String gameTimeoutSelfWarning(int count);

  /// No description provided for @gameTimeoutOther.
  ///
  /// In en, this message translates to:
  /// **'{name} ran out of time.'**
  String gameTimeoutOther(String name);

  /// No description provided for @gameRemovedSelfIdle.
  ///
  /// In en, this message translates to:
  /// **'You were removed for missing too many turns.'**
  String get gameRemovedSelfIdle;

  /// No description provided for @gameLeftSelf.
  ///
  /// In en, this message translates to:
  /// **'You left the game.'**
  String get gameLeftSelf;

  /// No description provided for @gameRemovedOtherIdle.
  ///
  /// In en, this message translates to:
  /// **'{name} was removed for being idle.'**
  String gameRemovedOtherIdle(String name);

  /// No description provided for @gameLeftOther.
  ///
  /// In en, this message translates to:
  /// **'{name} left the game.'**
  String gameLeftOther(String name);

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. Check your connection and try again.'**
  String get errorNetwork;

  /// No description provided for @errorRoomNotFound.
  ///
  /// In en, this message translates to:
  /// **'No room with that code. Check the code and try again.'**
  String get errorRoomNotFound;

  /// No description provided for @errorRoomFull.
  ///
  /// In en, this message translates to:
  /// **'That room is full.'**
  String get errorRoomFull;

  /// No description provided for @errorGameAlreadyStarted.
  ///
  /// In en, this message translates to:
  /// **'That game has already started.'**
  String get errorGameAlreadyStarted;

  /// No description provided for @errorGameNotStarted.
  ///
  /// In en, this message translates to:
  /// **'The game hasn\'t started yet.'**
  String get errorGameNotStarted;

  /// No description provided for @errorNotHost.
  ///
  /// In en, this message translates to:
  /// **'Only the host can start the game.'**
  String get errorNotHost;

  /// No description provided for @errorNotYourSeat.
  ///
  /// In en, this message translates to:
  /// **'This device isn\'t in that seat any more. Join the room again.'**
  String get errorNotYourSeat;

  /// No description provided for @errorNotYourTurn.
  ///
  /// In en, this message translates to:
  /// **'It\'s not your turn.'**
  String get errorNotYourTurn;

  /// No description provided for @errorWrongPhase.
  ///
  /// In en, this message translates to:
  /// **'You can\'t do that right now.'**
  String get errorWrongPhase;

  /// No description provided for @errorIllegalMove.
  ///
  /// In en, this message translates to:
  /// **'That token can\'t move with this roll.'**
  String get errorIllegalMove;

  /// No description provided for @errorGameFinished.
  ///
  /// In en, this message translates to:
  /// **'This game is over.'**
  String get errorGameFinished;

  /// No description provided for @errorTryAgain.
  ///
  /// In en, this message translates to:
  /// **'The game just changed. Please try again.'**
  String get errorTryAgain;

  /// No description provided for @errorLegacyGame.
  ///
  /// In en, this message translates to:
  /// **'This game was started before an update. Please start a new one.'**
  String get errorLegacyGame;

  /// No description provided for @errorInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'The server didn\'t accept that. Please check and try again.'**
  String get errorInvalidInput;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// No description provided for @notFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get notFoundTitle;

  /// No description provided for @notFoundGoHome.
  ///
  /// In en, this message translates to:
  /// **'Go home'**
  String get notFoundGoHome;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
