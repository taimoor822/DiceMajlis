import 'package:freezed_annotation/freezed_annotation.dart';

part 'account.freezed.dart';
part 'account.g.dart';

/// The signed-in player, as `GET /api/me/` describes them.
@freezed
abstract class Account with _$Account {
  const factory Account({
    /// Permanent public 9-digit Player ID. Never changes.
    required int playerId,
    required String displayName,
    @Default(false) bool isGuest,

    /// The room this account is in right now (to go straight back to it).
    ActiveRoom? activeRoom,
  }) = _Account;

  factory Account.fromJson(Map<String, dynamic> json) =>
      _$AccountFromJson(json);
}

/// A room the account holds a seat in and can go back to.
@freezed
abstract class ActiveRoom with _$ActiveRoom {
  const factory ActiveRoom({
    required String code,
    required String seatId,
    @Default(false) bool isHost,
    int? maxPlayers,

    /// True once the game has started (go to the board, not the waiting room).
    @Default(false) bool started,
  }) = _ActiveRoom;

  factory ActiveRoom.fromJson(Map<String, dynamic> json) =>
      _$ActiveRoomFromJson(json);
}

/// Shows a Player ID the way people read it out: `123 456 789`.
String formatPlayerId(int playerId) {
  final digits = playerId.toString();
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    groups.insert(0, digits.substring(end - 3 < 0 ? 0 : end - 3, end));
  }
  return groups.join(' ');
}
