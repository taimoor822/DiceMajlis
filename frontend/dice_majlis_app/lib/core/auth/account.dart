import 'package:freezed_annotation/freezed_annotation.dart';

part 'account.freezed.dart';
part 'account.g.dart';

/// The signed-in player, as `GET /api/me/` describes them: account, profile
/// and level progress. Everything here comes from the server.
@freezed
abstract class Account with _$Account {
  const Account._();

  const factory Account({
    /// Permanent public 9-digit Player ID. Never changes.
    required int playerId,
    required String displayName,

    /// True until the player saves the account with email + password.
    @Default(false) bool isGuest,
    String? email,

    /// Key of a built-in avatar picture (see `PlayerAvatar`).
    @Default('') String avatar,

    /// ISO country code, or null when the player doesn't show one.
    String? country,

    /// Spoken-language codes the player shows (`en`, `ar`, ...).
    @Default(<String>[]) List<String> languages,

    /// Google / Apple sign-ins attached to this account (`google`, `apple`).
    @Default(<String>[]) List<String> linked,
    @Default(1) int level,
    @Default(0) int xp,

    /// XP where this level starts and where the next one starts.
    @Default(0) int levelXp,
    @Default(0) int nextLevelXp,

    /// The room this account is in right now (to go straight back to it).
    ActiveRoom? activeRoom,

    /// What this account wears, by slot (`dice`, `board`, `frame`): the
    /// asset key the app draws, or null for an empty slot.
    @Default(<String, String?>{}) Map<String, String?> cosmetics,
  }) = _Account;

  factory Account.fromJson(Map<String, dynamic> json) =>
      _$AccountFromJson(json);

  String? get diceSkin => cosmetics['dice'];
  String? get boardSkin => cosmetics['board'];
  String? get frame => cosmetics['frame'];

  /// How far into the current level, 0 to 1 (for a progress bar).
  double get levelProgress {
    final span = nextLevelXp - levelXp;
    if (span <= 0) return 0;
    return ((xp - levelXp) / span).clamp(0.0, 1.0);
  }
}

/// A room the account holds a seat in and can go back to.
@freezed
abstract class ActiveRoom with _$ActiveRoom {
  const factory ActiveRoom({
    required String code,
    required String seatId,

    /// The room's server id (names its live `room/` channel).
    String? roomId,
    @Default(false) bool isHost,
    int? maxPlayers,

    /// True once the game has started (go to the board, not the waiting room).
    @Default(false) bool started,

    /// Which game the room plays (server game registry); older servers send
    /// nothing, and every room was Classic Ludo then.
    @Default('ludo') String gameType,
    @Default('classic') String variant,
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
