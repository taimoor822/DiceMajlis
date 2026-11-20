import '../network/api_exception.dart';
import 'generated/app_localizations.dart';

extension ApiErrorText on AppLocalizations {
  /// A translated, player-friendly message for a failed server call.
  String apiErrorText(Object error) {
    if (error is! ApiException) return errorGeneric;
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
      'not_authenticated' ||
      'session_revoked' ||
      'token_expired' ||
      'invalid_token' ||
      'invalid_refresh' ||
      'refresh_expired' => errorSignedOut,
      'rate_limited' => errorRateLimited,
      'not_your_turn' => errorNotYourTurn,
      'wrong_phase' => errorWrongPhase,
      'illegal_move' => errorIllegalMove,
      'game_not_active' => errorGameFinished,
      'stale_version' => errorTryAgain,
      'legacy_game' => errorLegacyGame,
      'invalid_input' => errorInvalidInput,
      _ => errorGeneric,
    };
  }
}
