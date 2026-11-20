import '../network/api_exception.dart';
import 'generated/app_localizations.dart';

extension ApiErrorText on AppLocalizations {
  /// A translated, player-friendly message for a failed server call.
  String apiErrorText(Object error) {
    if (error is! ApiException) return errorGeneric;
    if (error.code == 'invalid_input') {
      for (final codes in error.fieldErrors.values) {
        for (final code in codes) {
          final text = fieldErrorText(code);
          if (text != null) return text;
        }
      }
    }
    return switch (error.code) {
      ApiException.networkError => errorNetwork,
      'room_not_found' => errorRoomNotFound,
      'room_full' => errorRoomFull,
      'game_already_started' => errorGameAlreadyStarted,
      'game_not_started' => errorGameNotStarted,
      'not_host' => errorNotHost,
      'not_in_room' => errorNotInRoom,
      'already_in_game' => errorAlreadyInGame,
      'not_your_seat' ||
      'unknown_player' ||
      'not_your_token' => errorNotYourSeat,
      'not_your_turn' => errorNotYourTurn,
      'wrong_phase' => errorWrongPhase,
      'illegal_move' => errorIllegalMove,
      'game_not_active' => errorGameFinished,
      'stale_version' => errorTryAgain,
      'legacy_game' => errorLegacyGame,
      'not_authenticated' ||
      'session_revoked' ||
      'token_expired' ||
      'invalid_token' ||
      'invalid_refresh' ||
      'refresh_expired' => errorSignedOut,
      'rate_limited' => errorRateLimited,
      'invalid_credentials' => errorInvalidCredentials,
      'email_taken' => errorEmailTaken,
      'already_saved' => errorAlreadySaved,
      'invalid_code' => errorInvalidCode,
      'code_expired' => errorCodeExpired,
      'too_many_attempts' => errorTooManyCodeTries,
      'already_claimed' => errorAlreadyClaimed,
      'insufficient_funds' => errorInsufficientFunds,
      'invalid_input' => errorInvalidInput,
      _ => errorGeneric,
    };
  }

  /// Text for one field problem the server reported (`fields` of an
  /// `invalid_input` error), or null when there's nothing specific to say.
  String? fieldErrorText(String code) => switch (code) {
    'password_too_short' => errorPasswordTooShort,
    'password_too_common' => errorPasswordTooCommon,
    'password_entirely_numeric' => errorPasswordNumeric,
    'password_too_similar' => errorPasswordSimilar,
    'name_characters' => nameCharacters,
    'name_not_allowed' => nameNotAllowed,
    _ => null,
  };

  /// Display name of a spoken-language code the server lists.
  String spokenLanguageName(String code) => switch (code) {
    'en' => languageEn,
    'ar' => languageAr,
    'ur' => languageUr,
    'pa' => languagePa,
    _ => code.toUpperCase(),
  };
}
