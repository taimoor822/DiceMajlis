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

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @splashOffline.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the Majlis server. Check your connection and try again.'**
  String get splashOffline;

  /// No description provided for @splashPlayOffline.
  ///
  /// In en, this message translates to:
  /// **'Play offline'**
  String get splashPlayOffline;

  /// No description provided for @welcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Ludo in the Majlis. Play with friends, family or the Majlis AI.'**
  String get welcomeBody;

  /// No description provided for @welcomePlayAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Play as guest'**
  String get welcomePlayAsGuest;

  /// No description provided for @welcomePlayOffline.
  ///
  /// In en, this message translates to:
  /// **'Play offline on this phone'**
  String get welcomePlayOffline;

  /// No description provided for @welcomeGuestHint.
  ///
  /// In en, this message translates to:
  /// **'You get a permanent Player ID right away. Your guest account lives on this device; adding email, Google or Apple later will keep it safe.'**
  String get welcomeGuestHint;

  /// No description provided for @welcomeEmail.
  ///
  /// In en, this message translates to:
  /// **'Sign in with email'**
  String get welcomeEmail;

  /// No description provided for @welcomeEmailSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Or create an account with your email'**
  String get welcomeEmailSubtitle;

  /// No description provided for @welcomeGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get welcomeGoogle;

  /// No description provided for @welcomeApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get welcomeApple;

  /// No description provided for @providerGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get providerGoogle;

  /// No description provided for @providerApple.
  ///
  /// In en, this message translates to:
  /// **'Apple'**
  String get providerApple;

  /// No description provided for @socialSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'That sign-in didn\'t work. Please try again.'**
  String get socialSignInFailed;

  /// No description provided for @linkButton.
  ///
  /// In en, this message translates to:
  /// **'Link {provider}'**
  String linkButton(String provider);

  /// No description provided for @saveWith.
  ///
  /// In en, this message translates to:
  /// **'Save with {provider}'**
  String saveWith(String provider);

  /// No description provided for @linkedWith.
  ///
  /// In en, this message translates to:
  /// **'Linked with {provider}'**
  String linkedWith(String provider);

  /// No description provided for @linkDone.
  ///
  /// In en, this message translates to:
  /// **'{provider} is linked. Sign in with it on any phone.'**
  String linkDone(String provider);

  /// No description provided for @unlinkButton.
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get unlinkButton;

  /// No description provided for @unlinkDone.
  ///
  /// In en, this message translates to:
  /// **'{provider} is no longer linked.'**
  String unlinkDone(String provider);

  /// No description provided for @emailTitle.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailTitle;

  /// No description provided for @emailModeSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get emailModeSignIn;

  /// No description provided for @emailModeCreate.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get emailModeCreate;

  /// No description provided for @emailField.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailField;

  /// No description provided for @emailFieldInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get emailFieldInvalid;

  /// No description provided for @passwordField.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordField;

  /// No description provided for @newPasswordField.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPasswordField;

  /// No description provided for @passwordFieldEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter your password.'**
  String get passwordFieldEmpty;

  /// No description provided for @passwordShow.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get passwordShow;

  /// No description provided for @passwordHide.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get passwordHide;

  /// No description provided for @passwordHint.
  ///
  /// In en, this message translates to:
  /// **'Use letters and numbers. Avoid common passwords.'**
  String get passwordHint;

  /// No description provided for @emailSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get emailSignIn;

  /// No description provided for @emailCreate.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get emailCreate;

  /// No description provided for @emailForgot.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get emailForgot;

  /// No description provided for @forgotTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgot password'**
  String get forgotTitle;

  /// No description provided for @forgotIntro.
  ///
  /// In en, this message translates to:
  /// **'Enter your account\'s email. We\'ll send you a 6-digit code.'**
  String get forgotIntro;

  /// No description provided for @forgotSend.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get forgotSend;

  /// No description provided for @forgotCodeSent.
  ///
  /// In en, this message translates to:
  /// **'If {email} has an account, a code is on its way. It works for one hour.'**
  String forgotCodeSent(String email);

  /// No description provided for @forgotCode.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get forgotCode;

  /// No description provided for @forgotCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6 digits from the email.'**
  String get forgotCodeInvalid;

  /// No description provided for @forgotChange.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get forgotChange;

  /// No description provided for @forgotResend.
  ///
  /// In en, this message translates to:
  /// **'Send a new code'**
  String get forgotResend;

  /// No description provided for @saveAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Save your account'**
  String get saveAccountTitle;

  /// No description provided for @saveAccountIntro.
  ///
  /// In en, this message translates to:
  /// **'Add your email and a password. You keep your Player ID and everything on this account, and you can sign in on any phone.'**
  String get saveAccountIntro;

  /// No description provided for @saveAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Save account'**
  String get saveAccountButton;

  /// No description provided for @saveAccountDone.
  ///
  /// In en, this message translates to:
  /// **'Account saved. You can now sign in with your email.'**
  String get saveAccountDone;

  /// No description provided for @navEvents.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get navEvents;

  /// No description provided for @navGameHub.
  ///
  /// In en, this message translates to:
  /// **'Game Hub'**
  String get navGameHub;

  /// No description provided for @navBattle.
  ///
  /// In en, this message translates to:
  /// **'Battle'**
  String get navBattle;

  /// No description provided for @navChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get navChat;

  /// No description provided for @navSocial.
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get navSocial;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @comingSoonBadge.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get comingSoonBadge;

  /// No description provided for @comingSoonNamed.
  ///
  /// In en, this message translates to:
  /// **'{feature} is coming soon.'**
  String comingSoonNamed(String feature);

  /// No description provided for @homeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ludo in the Majlis. Play with friends or the Majlis AI.'**
  String get homeSubtitle;

  /// No description provided for @homePlay.
  ///
  /// In en, this message translates to:
  /// **'Play Ludo'**
  String get homePlay;

  /// No description provided for @homeJoinWithCode.
  ///
  /// In en, this message translates to:
  /// **'Join with a code'**
  String get homeJoinWithCode;

  /// No description provided for @homePlayerId.
  ///
  /// In en, this message translates to:
  /// **'Player ID {id}'**
  String homePlayerId(String id);

  /// No description provided for @homeCopyPlayerId.
  ///
  /// In en, this message translates to:
  /// **'Copy Player ID'**
  String get homeCopyPlayerId;

  /// No description provided for @homePlayerIdCopied.
  ///
  /// In en, this message translates to:
  /// **'Player ID copied'**
  String get homePlayerIdCopied;

  /// No description provided for @homeGuestTag.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get homeGuestTag;

  /// No description provided for @homeProfileHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to edit your profile'**
  String get homeProfileHint;

  /// No description provided for @homeLevel.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String homeLevel(int level);

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get profileName;

  /// No description provided for @profileNameSave.
  ///
  /// In en, this message translates to:
  /// **'Save name'**
  String get profileNameSave;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get profileSaved;

  /// No description provided for @profileAvatar.
  ///
  /// In en, this message translates to:
  /// **'Avatar'**
  String get profileAvatar;

  /// No description provided for @profileAvatarPhotoSoon.
  ///
  /// In en, this message translates to:
  /// **'Your own photo is coming soon.'**
  String get profileAvatarPhotoSoon;

  /// No description provided for @profileCountry.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get profileCountry;

  /// No description provided for @profileCountryNone.
  ///
  /// In en, this message translates to:
  /// **'Not shown'**
  String get profileCountryNone;

  /// No description provided for @profileCountryChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get profileCountryChoose;

  /// No description provided for @profileCountryHide.
  ///
  /// In en, this message translates to:
  /// **'Don\'t show my country'**
  String get profileCountryHide;

  /// No description provided for @profileLanguages.
  ///
  /// In en, this message translates to:
  /// **'Languages you speak'**
  String get profileLanguages;

  /// No description provided for @profileLanguagesHint.
  ///
  /// In en, this message translates to:
  /// **'Pick up to {count}.'**
  String profileLanguagesHint(int count);

  /// No description provided for @profileLevelXp.
  ///
  /// In en, this message translates to:
  /// **'{xp} / {next} XP'**
  String profileLevelXp(int xp, int next);

  /// No description provided for @profileXpHow.
  ///
  /// In en, this message translates to:
  /// **'Earn XP by playing online games against other people.'**
  String get profileXpHow;

  /// No description provided for @profileCustomise.
  ///
  /// In en, this message translates to:
  /// **'Customise'**
  String get profileCustomise;

  /// No description provided for @profileCustomiseHint.
  ///
  /// In en, this message translates to:
  /// **'Dice, board and profile frame'**
  String get profileCustomiseHint;

  /// No description provided for @customiseTitle.
  ///
  /// In en, this message translates to:
  /// **'Customise'**
  String get customiseTitle;

  /// No description provided for @customiseDice.
  ///
  /// In en, this message translates to:
  /// **'Dice'**
  String get customiseDice;

  /// No description provided for @customiseBoard.
  ///
  /// In en, this message translates to:
  /// **'Board'**
  String get customiseBoard;

  /// No description provided for @customiseFrame.
  ///
  /// In en, this message translates to:
  /// **'Profile frame'**
  String get customiseFrame;

  /// No description provided for @customiseNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get customiseNone;

  /// No description provided for @customiseWearing.
  ///
  /// In en, this message translates to:
  /// **'Wearing'**
  String get customiseWearing;

  /// No description provided for @customiseMoreSoon.
  ///
  /// In en, this message translates to:
  /// **'More items will come from achievements and rewards (coming soon).'**
  String get customiseMoreSoon;

  /// No description provided for @itemRarity.
  ///
  /// In en, this message translates to:
  /// **'{rarity, select, common{Common} rare{Rare} epic{Epic} legendary{Legendary} other{Special}}'**
  String itemRarity(String rarity);

  /// No description provided for @itemExpires.
  ///
  /// In en, this message translates to:
  /// **'Until {date}'**
  String itemExpires(DateTime date);

  /// No description provided for @profileOptionsFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the profile choices.'**
  String get profileOptionsFailed;

  /// No description provided for @languageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @languageAr.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get languageAr;

  /// No description provided for @languageUr.
  ///
  /// In en, this message translates to:
  /// **'Urdu'**
  String get languageUr;

  /// No description provided for @languagePa.
  ///
  /// In en, this message translates to:
  /// **'Punjabi'**
  String get languagePa;

  /// No description provided for @nameLength.
  ///
  /// In en, this message translates to:
  /// **'Names are {min} to {max} characters.'**
  String nameLength(int min, int max);

  /// No description provided for @nameCharacters.
  ///
  /// In en, this message translates to:
  /// **'Use letters, numbers, spaces and _ - . \' only, with at least one letter.'**
  String get nameCharacters;

  /// No description provided for @nameNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'That name isn\'t allowed. Please pick another.'**
  String get nameNotAllowed;

  /// No description provided for @homeShortcuts.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get homeShortcuts;

  /// No description provided for @homeWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get homeWallet;

  /// No description provided for @currencyGold.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get currencyGold;

  /// No description provided for @currencyDiamond.
  ///
  /// In en, this message translates to:
  /// **'Diamonds'**
  String get currencyDiamond;

  /// No description provided for @dailyTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily reward'**
  String get dailyTitle;

  /// No description provided for @dailyDay.
  ///
  /// In en, this message translates to:
  /// **'Day {day}'**
  String dailyDay(int day);

  /// No description provided for @dailyClaim.
  ///
  /// In en, this message translates to:
  /// **'Claim'**
  String get dailyClaim;

  /// No description provided for @dailyClaimed.
  ///
  /// In en, this message translates to:
  /// **'Claimed! Come back tomorrow for day {day}.'**
  String dailyClaimed(int day);

  /// No description provided for @dailyNextIn.
  ///
  /// In en, this message translates to:
  /// **'Next reward in {hours, plural, =0{less than an hour} =1{1 hour} other{{hours} hours}}'**
  String dailyNextIn(int hours);

  /// No description provided for @dailyHint.
  ///
  /// In en, this message translates to:
  /// **'Come back every day: rewards grow for 7 days in a row. Miss a day and it starts again.'**
  String get dailyHint;

  /// No description provided for @dailyGot.
  ///
  /// In en, this message translates to:
  /// **'You got {amount}'**
  String dailyGot(String amount);

  /// No description provided for @dailyFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the daily reward.'**
  String get dailyFailed;

  /// No description provided for @walletTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get walletTitle;

  /// No description provided for @walletHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get walletHistory;

  /// No description provided for @walletEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet. Claim your daily reward to get started.'**
  String get walletEmpty;

  /// No description provided for @walletLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get walletLoadMore;

  /// No description provided for @walletFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your wallet.'**
  String get walletFailed;

  /// No description provided for @walletEarnHint.
  ///
  /// In en, this message translates to:
  /// **'Earn gold every day. Buying gold and diamonds comes later.'**
  String get walletEarnHint;

  /// No description provided for @walletTypeDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily reward'**
  String get walletTypeDaily;

  /// No description provided for @walletTypeAdminGrant.
  ///
  /// In en, this message translates to:
  /// **'From the Dice Majlis team'**
  String get walletTypeAdminGrant;

  /// No description provided for @walletTypeAdminRevoke.
  ///
  /// In en, this message translates to:
  /// **'Taken back by the team'**
  String get walletTypeAdminRevoke;

  /// No description provided for @walletTypeReversal.
  ///
  /// In en, this message translates to:
  /// **'Correction'**
  String get walletTypeReversal;

  /// No description provided for @walletTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get walletTypeOther;

  /// No description provided for @homeShop.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get homeShop;

  /// No description provided for @homeCollection.
  ///
  /// In en, this message translates to:
  /// **'Collection'**
  String get homeCollection;

  /// No description provided for @homeRankings.
  ///
  /// In en, this message translates to:
  /// **'Rankings'**
  String get homeRankings;

  /// No description provided for @homeVip.
  ///
  /// In en, this message translates to:
  /// **'VIP'**
  String get homeVip;

  /// No description provided for @homeNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get homeNotifications;

  /// No description provided for @homeSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get homeSettings;

  /// No description provided for @hubTitle.
  ///
  /// In en, this message translates to:
  /// **'Game Hub'**
  String get hubTitle;

  /// No description provided for @hubCatalogFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the games'**
  String get hubCatalogFailed;

  /// No description provided for @hubUpdateForGames.
  ///
  /// In en, this message translates to:
  /// **'New games are available. Update the app to play them.'**
  String get hubUpdateForGames;

  /// No description provided for @hubClassicBody.
  ///
  /// In en, this message translates to:
  /// **'Play with friends in a private room, or start alone and the Majlis AI joins you.'**
  String get hubClassicBody;

  /// No description provided for @hubCreateRoom.
  ///
  /// In en, this message translates to:
  /// **'Create room'**
  String get hubCreateRoom;

  /// No description provided for @hubJoinRoom.
  ///
  /// In en, this message translates to:
  /// **'Join room'**
  String get hubJoinRoom;

  /// No description provided for @hubMoreModes.
  ///
  /// In en, this message translates to:
  /// **'More ways to play'**
  String get hubMoreModes;

  /// No description provided for @hubLocalPlay.
  ///
  /// In en, this message translates to:
  /// **'Play on this phone'**
  String get hubLocalPlay;

  /// No description provided for @hubLocalPlayBody.
  ///
  /// In en, this message translates to:
  /// **'Play the Majlis AI or pass one phone around the table. Works offline.'**
  String get hubLocalPlayBody;

  /// No description provided for @hubLocalPlayStart.
  ///
  /// In en, this message translates to:
  /// **'Play offline'**
  String get hubLocalPlayStart;

  /// No description provided for @hubTeamLudo.
  ///
  /// In en, this message translates to:
  /// **'Team Ludo'**
  String get hubTeamLudo;

  /// No description provided for @hubTeamLudoBody.
  ///
  /// In en, this message translates to:
  /// **'Two against two, as partners.'**
  String get hubTeamLudoBody;

  /// No description provided for @hubTournaments.
  ///
  /// In en, this message translates to:
  /// **'Tournaments'**
  String get hubTournaments;

  /// No description provided for @hubTournamentsBody.
  ///
  /// In en, this message translates to:
  /// **'Brackets with prizes.'**
  String get hubTournamentsBody;

  /// No description provided for @hubMoreGames.
  ///
  /// In en, this message translates to:
  /// **'More games'**
  String get hubMoreGames;

  /// No description provided for @hubMoreGamesBody.
  ///
  /// In en, this message translates to:
  /// **'Domino and Jackaroo are next.'**
  String get hubMoreGamesBody;

  /// No description provided for @eventsTitle.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get eventsTitle;

  /// No description provided for @eventsBody.
  ///
  /// In en, this message translates to:
  /// **'Live events, daily missions and rewards will appear here.'**
  String get eventsBody;

  /// No description provided for @chatTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatTitle;

  /// No description provided for @chatBody.
  ///
  /// In en, this message translates to:
  /// **'Private and group chats with your friends will live here.'**
  String get chatBody;

  /// No description provided for @socialTitle.
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get socialTitle;

  /// No description provided for @socialBody.
  ///
  /// In en, this message translates to:
  /// **'Find players, add friends and see what your Majlis is up to.'**
  String get socialBody;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeHint.
  ///
  /// In en, this message translates to:
  /// **'Phone follows your phone\'s dark mode setting.'**
  String get settingsThemeHint;

  /// No description provided for @settingsAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccount;

  /// No description provided for @settingsGuestAccount.
  ///
  /// In en, this message translates to:
  /// **'Guest account'**
  String get settingsGuestAccount;

  /// No description provided for @settingsGuestSaveHint.
  ///
  /// In en, this message translates to:
  /// **'Save your account so you don\'t lose it if you change or reset your phone.'**
  String get settingsGuestSaveHint;

  /// No description provided for @settingsSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsSignOut;

  /// No description provided for @settingsSignOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get settingsSignOutTitle;

  /// No description provided for @settingsSignOutGuest.
  ///
  /// In en, this message translates to:
  /// **'You\'re playing as a guest. If you sign out, this account and its Player ID can\'t be recovered.'**
  String get settingsSignOutGuest;

  /// No description provided for @settingsSignOutBody.
  ///
  /// In en, this message translates to:
  /// **'You can sign in again any time.'**
  String get settingsSignOutBody;

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

  /// No description provided for @waitingRoomLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave room'**
  String get waitingRoomLeave;

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

  /// No description provided for @playerTagAway.
  ///
  /// In en, this message translates to:
  /// **'Away'**
  String get playerTagAway;

  /// No description provided for @gamePlayerDisconnected.
  ///
  /// In en, this message translates to:
  /// **'{name} lost connection. Their seat is kept.'**
  String gamePlayerDisconnected(String name);

  /// No description provided for @gamePlayerReconnected.
  ///
  /// In en, this message translates to:
  /// **'{name} is back.'**
  String gamePlayerReconnected(String name);

  /// No description provided for @waitingRoomStatusWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for everyone to be ready…'**
  String get waitingRoomStatusWaiting;

  /// No description provided for @waitingRoomStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Everyone is ready.'**
  String get waitingRoomStatusReady;

  /// No description provided for @waitingRoomStatusAlone.
  ///
  /// In en, this message translates to:
  /// **'Start now and the Majlis AI plays with you, or invite friends first.'**
  String get waitingRoomStatusAlone;

  /// No description provided for @waitingRoomStartingIn.
  ///
  /// In en, this message translates to:
  /// **'Starting in {seconds}…'**
  String waitingRoomStartingIn(int seconds);

  /// No description provided for @waitingRoomReady.
  ///
  /// In en, this message translates to:
  /// **'I\'m ready'**
  String get waitingRoomReady;

  /// No description provided for @waitingRoomUnready.
  ///
  /// In en, this message translates to:
  /// **'Not ready yet'**
  String get waitingRoomUnready;

  /// No description provided for @waitingRoomPlayerReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get waitingRoomPlayerReady;

  /// No description provided for @waitingRoomPlayerNotReady.
  ///
  /// In en, this message translates to:
  /// **'Not ready'**
  String get waitingRoomPlayerNotReady;

  /// No description provided for @waitingRoomLock.
  ///
  /// In en, this message translates to:
  /// **'Lock the room'**
  String get waitingRoomLock;

  /// No description provided for @waitingRoomUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock the room'**
  String get waitingRoomUnlock;

  /// No description provided for @waitingRoomLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked: invited players only'**
  String get waitingRoomLocked;

  /// No description provided for @waitingRoomInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite by Player ID'**
  String get waitingRoomInvite;

  /// No description provided for @waitingRoomInviteHint.
  ///
  /// In en, this message translates to:
  /// **'9-digit Player ID'**
  String get waitingRoomInviteHint;

  /// No description provided for @waitingRoomInviteSend.
  ///
  /// In en, this message translates to:
  /// **'Send invite'**
  String get waitingRoomInviteSend;

  /// No description provided for @waitingRoomInviteSent.
  ///
  /// In en, this message translates to:
  /// **'Invite sent'**
  String get waitingRoomInviteSent;

  /// No description provided for @waitingRoomInviteInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a 9-digit Player ID.'**
  String get waitingRoomInviteInvalid;

  /// No description provided for @waitingRoomCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get waitingRoomCancel;

  /// No description provided for @waitingRoomPlayerMenu.
  ///
  /// In en, this message translates to:
  /// **'Player options'**
  String get waitingRoomPlayerMenu;

  /// No description provided for @waitingRoomMakeHost.
  ///
  /// In en, this message translates to:
  /// **'Make host'**
  String get waitingRoomMakeHost;

  /// No description provided for @waitingRoomRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from the room'**
  String get waitingRoomRemove;

  /// No description provided for @waitingRoomKicked.
  ///
  /// In en, this message translates to:
  /// **'The host removed you from the room.'**
  String get waitingRoomKicked;

  /// No description provided for @waitingRoomRules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get waitingRoomRules;

  /// No description provided for @waitingRoomRulesHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a rule to change it. Everyone gets ready again after a change.'**
  String get waitingRoomRulesHint;

  /// No description provided for @ruleTurnTime.
  ///
  /// In en, this message translates to:
  /// **'Turn time'**
  String get ruleTurnTime;

  /// No description provided for @ruleCaptures.
  ///
  /// In en, this message translates to:
  /// **'Captures'**
  String get ruleCaptures;

  /// No description provided for @ruleExtraTurnOnSix.
  ///
  /// In en, this message translates to:
  /// **'Extra turn on a six'**
  String get ruleExtraTurnOnSix;

  /// No description provided for @ruleGameEnds.
  ///
  /// In en, this message translates to:
  /// **'The game ends'**
  String get ruleGameEnds;

  /// No description provided for @ruleEndsFirstHome.
  ///
  /// In en, this message translates to:
  /// **'When the first player is home'**
  String get ruleEndsFirstHome;

  /// No description provided for @ruleEndsAllPlaces.
  ///
  /// In en, this message translates to:
  /// **'When every place is decided'**
  String get ruleEndsAllPlaces;

  /// No description provided for @ruleSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String ruleSeconds(int seconds);

  /// No description provided for @ruleOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get ruleOn;

  /// No description provided for @ruleOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get ruleOff;

  /// No description provided for @invitesTitle.
  ///
  /// In en, this message translates to:
  /// **'Invites'**
  String get invitesTitle;

  /// No description provided for @inviteFrom.
  ///
  /// In en, this message translates to:
  /// **'{name} invited you to {game}'**
  String inviteFrom(String name, String game);

  /// No description provided for @inviteJoin.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get inviteJoin;

  /// No description provided for @inviteDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get inviteDecline;

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

  /// No description provided for @gameLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave game'**
  String get gameLeave;

  /// No description provided for @gameLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave this game?'**
  String get gameLeaveTitle;

  /// No description provided for @gameLeaveBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll lose this game and can\'t come back to it.'**
  String get gameLeaveBody;

  /// No description provided for @gameLeaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get gameLeaveConfirm;

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

  /// No description provided for @gameOverPlayAgain.
  ///
  /// In en, this message translates to:
  /// **'Play again'**
  String get gameOverPlayAgain;

  /// No description provided for @gameOverWaitingForOthers.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the others to say yes…'**
  String get gameOverWaitingForOthers;

  /// No description provided for @gameOverXpGained.
  ///
  /// In en, this message translates to:
  /// **'+{amount} XP'**
  String gameOverXpGained(int amount);

  /// No description provided for @gameOverLevelUp.
  ///
  /// In en, this message translates to:
  /// **'Level up! You\'re now level {level}'**
  String gameOverLevelUp(int level);

  /// No description provided for @gameOverNoXpWithAi.
  ///
  /// In en, this message translates to:
  /// **'Games with the AI don\'t give XP.'**
  String get gameOverNoXpWithAi;

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
  /// **'Only the host can do that.'**
  String get errorNotHost;

  /// No description provided for @errorNotYourSeat.
  ///
  /// In en, this message translates to:
  /// **'That isn\'t your seat.'**
  String get errorNotYourSeat;

  /// No description provided for @errorNotInRoom.
  ///
  /// In en, this message translates to:
  /// **'You\'re not in this room any more.'**
  String get errorNotInRoom;

  /// No description provided for @errorAlreadyInGame.
  ///
  /// In en, this message translates to:
  /// **'You\'re still playing another game. Finish or leave it first.'**
  String get errorAlreadyInGame;

  /// No description provided for @errorSignedOut.
  ///
  /// In en, this message translates to:
  /// **'You were signed out. Please sign in again.'**
  String get errorSignedOut;

  /// No description provided for @errorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many tries. Please wait a moment and try again.'**
  String get errorRateLimited;

  /// No description provided for @errorInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Wrong email or password.'**
  String get errorInvalidCredentials;

  /// No description provided for @errorEmailTaken.
  ///
  /// In en, this message translates to:
  /// **'That email already has an account. Sign in instead.'**
  String get errorEmailTaken;

  /// No description provided for @errorItemNotOwned.
  ///
  /// In en, this message translates to:
  /// **'You don\'t own that item.'**
  String get errorItemNotOwned;

  /// No description provided for @errorItemUnavailable.
  ///
  /// In en, this message translates to:
  /// **'That item isn\'t available.'**
  String get errorItemUnavailable;

  /// No description provided for @errorSocialAccountTaken.
  ///
  /// In en, this message translates to:
  /// **'That account is already linked to another player.'**
  String get errorSocialAccountTaken;

  /// No description provided for @errorAlreadyLinked.
  ///
  /// In en, this message translates to:
  /// **'A different account of this kind is already linked.'**
  String get errorAlreadyLinked;

  /// No description provided for @errorLastSignInMethod.
  ///
  /// In en, this message translates to:
  /// **'This is your only way to sign in, so it can\'t be unlinked.'**
  String get errorLastSignInMethod;

  /// No description provided for @errorSignInNotSetUp.
  ///
  /// In en, this message translates to:
  /// **'This sign-in isn\'t available right now.'**
  String get errorSignInNotSetUp;

  /// No description provided for @errorAlreadySaved.
  ///
  /// In en, this message translates to:
  /// **'This account is already saved.'**
  String get errorAlreadySaved;

  /// No description provided for @errorInvalidCode.
  ///
  /// In en, this message translates to:
  /// **'That code isn\'t right. Check the email and try again.'**
  String get errorInvalidCode;

  /// No description provided for @errorCodeExpired.
  ///
  /// In en, this message translates to:
  /// **'That code has expired. Ask for a new one.'**
  String get errorCodeExpired;

  /// No description provided for @errorTooManyCodeTries.
  ///
  /// In en, this message translates to:
  /// **'Too many wrong codes. Ask for a new one.'**
  String get errorTooManyCodeTries;

  /// No description provided for @errorPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'That password is too short.'**
  String get errorPasswordTooShort;

  /// No description provided for @errorPasswordTooCommon.
  ///
  /// In en, this message translates to:
  /// **'That password is too easy to guess.'**
  String get errorPasswordTooCommon;

  /// No description provided for @errorPasswordNumeric.
  ///
  /// In en, this message translates to:
  /// **'Use letters too, not only numbers.'**
  String get errorPasswordNumeric;

  /// No description provided for @errorPasswordSimilar.
  ///
  /// In en, this message translates to:
  /// **'That password is too close to your email.'**
  String get errorPasswordSimilar;

  /// No description provided for @errorAlreadyClaimed.
  ///
  /// In en, this message translates to:
  /// **'Today\'s reward is already claimed.'**
  String get errorAlreadyClaimed;

  /// No description provided for @errorInsufficientFunds.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have enough for that.'**
  String get errorInsufficientFunds;

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

  /// No description provided for @errorNotEveryoneReady.
  ///
  /// In en, this message translates to:
  /// **'Everyone has to be ready first.'**
  String get errorNotEveryoneReady;

  /// No description provided for @errorPlayerKicked.
  ///
  /// In en, this message translates to:
  /// **'The host removed you from this room.'**
  String get errorPlayerKicked;

  /// No description provided for @errorRoomLocked.
  ///
  /// In en, this message translates to:
  /// **'This room is for invited players only.'**
  String get errorRoomLocked;

  /// No description provided for @errorGameStarting.
  ///
  /// In en, this message translates to:
  /// **'That game is starting. Try another room.'**
  String get errorGameStarting;

  /// No description provided for @errorPlayerNotFound.
  ///
  /// In en, this message translates to:
  /// **'No player with that ID.'**
  String get errorPlayerNotFound;

  /// No description provided for @errorCannotInviteYourself.
  ///
  /// In en, this message translates to:
  /// **'That\'s your own Player ID.'**
  String get errorCannotInviteYourself;

  /// No description provided for @errorAlreadyInRoom.
  ///
  /// In en, this message translates to:
  /// **'They\'re already in this room.'**
  String get errorAlreadyInRoom;

  /// No description provided for @errorInvalidOption.
  ///
  /// In en, this message translates to:
  /// **'That rule can\'t be set that way.'**
  String get errorInvalidOption;

  /// No description provided for @errorGameNotFinished.
  ///
  /// In en, this message translates to:
  /// **'The game isn\'t over yet.'**
  String get errorGameNotFinished;

  /// No description provided for @errorRoomClosed.
  ///
  /// In en, this message translates to:
  /// **'This room is closed.'**
  String get errorRoomClosed;

  /// No description provided for @errorInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'The server didn\'t accept that. Please check and try again.'**
  String get errorInvalidInput;

  /// No description provided for @gameLudo.
  ///
  /// In en, this message translates to:
  /// **'Ludo'**
  String get gameLudo;

  /// No description provided for @variantClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get variantClassic;

  /// A game with its variant, e.g. Classic Ludo
  ///
  /// In en, this message translates to:
  /// **'{variant} {game}'**
  String gameTitle(String variant, String game);

  /// No description provided for @gameUnsupportedTitle.
  ///
  /// In en, this message translates to:
  /// **'Update the app to play this game'**
  String get gameUnsupportedTitle;

  /// No description provided for @gameUnsupportedBody.
  ///
  /// In en, this message translates to:
  /// **'This room plays a game this version of Dice Majlis can\'t show yet. Update the app, or leave the game to play something else.'**
  String get gameUnsupportedBody;

  /// No description provided for @localSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Play on this phone'**
  String get localSetupTitle;

  /// No description provided for @localSetupBody.
  ///
  /// In en, this message translates to:
  /// **'Play the Majlis AI, or pass one phone around the table. Offline games don\'t earn Gold or Diamonds and don\'t change your rating.'**
  String get localSetupBody;

  /// No description provided for @localSetupPlayers.
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get localSetupPlayers;

  /// No description provided for @localSetupSeats.
  ///
  /// In en, this message translates to:
  /// **'Who plays each colour'**
  String get localSetupSeats;

  /// No description provided for @localSeatHuman.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get localSeatHuman;

  /// No description provided for @localSeatAi.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get localSeatAi;

  /// No description provided for @localSetupPlayOn.
  ///
  /// In en, this message translates to:
  /// **'Play on for every place'**
  String get localSetupPlayOn;

  /// No description provided for @localSetupPlayOnBody.
  ///
  /// In en, this message translates to:
  /// **'Keep playing after the first player gets home.'**
  String get localSetupPlayOnBody;

  /// No description provided for @localSetupStart.
  ///
  /// In en, this message translates to:
  /// **'Start game'**
  String get localSetupStart;

  /// No description provided for @colorRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get colorRed;

  /// No description provided for @colorBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get colorBlue;

  /// No description provided for @colorGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get colorGreen;

  /// No description provided for @colorYellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get colorYellow;

  /// No description provided for @localNamePlayer.
  ///
  /// In en, this message translates to:
  /// **'Player {number}'**
  String localNamePlayer(int number);

  /// No description provided for @localNameAi.
  ///
  /// In en, this message translates to:
  /// **'Majlis AI'**
  String get localNameAi;

  /// No description provided for @localNameAiNumbered.
  ///
  /// In en, this message translates to:
  /// **'Majlis AI {number}'**
  String localNameAiNumbered(int number);

  /// No description provided for @localGameTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline game'**
  String get localGameTitle;

  /// No description provided for @localStatusYourRoll.
  ///
  /// In en, this message translates to:
  /// **'Your turn: roll the dice'**
  String get localStatusYourRoll;

  /// No description provided for @localStatusRoll.
  ///
  /// In en, this message translates to:
  /// **'{name}: roll the dice'**
  String localStatusRoll(String name);

  /// No description provided for @localStatusYourMove.
  ///
  /// In en, this message translates to:
  /// **'Pick a token to move'**
  String get localStatusYourMove;

  /// No description provided for @localStatusMove.
  ///
  /// In en, this message translates to:
  /// **'{name}: pick a token'**
  String localStatusMove(String name);

  /// No description provided for @localStatusAi.
  ///
  /// In en, this message translates to:
  /// **'{name} is playing…'**
  String localStatusAi(String name);

  /// No description provided for @localNoticeNoMoves.
  ///
  /// In en, this message translates to:
  /// **'{name} can\'t move'**
  String localNoticeNoMoves(String name);

  /// No description provided for @localNoticeTooManySixes.
  ///
  /// In en, this message translates to:
  /// **'{name} rolled too many sixes'**
  String localNoticeTooManySixes(String name);

  /// No description provided for @localNoticeCaptured.
  ///
  /// In en, this message translates to:
  /// **'{name} sent a token back to base!'**
  String localNoticeCaptured(String name);

  /// No description provided for @localNoticeHome.
  ///
  /// In en, this message translates to:
  /// **'{name} got every token home: place {place}!'**
  String localNoticeHome(String name, int place);

  /// No description provided for @localWinner.
  ///
  /// In en, this message translates to:
  /// **'{name} wins!'**
  String localWinner(String name);

  /// No description provided for @localResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Game over'**
  String get localResultsTitle;

  /// No description provided for @localPlaceShort.
  ///
  /// In en, this message translates to:
  /// **'#{place}'**
  String localPlaceShort(int place);

  /// No description provided for @localPlayAgain.
  ///
  /// In en, this message translates to:
  /// **'Play again'**
  String get localPlayAgain;

  /// No description provided for @localDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get localDone;

  /// No description provided for @localLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave this game?'**
  String get localLeaveTitle;

  /// No description provided for @localLeaveBody.
  ///
  /// In en, this message translates to:
  /// **'Offline games aren\'t saved, so this one will end.'**
  String get localLeaveBody;

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
