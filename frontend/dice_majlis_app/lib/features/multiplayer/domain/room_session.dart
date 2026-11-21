import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/auth/account.dart';
import '../../games/domain/game_catalog.dart';

part 'room_session.freezed.dart';
part 'room_session.g.dart';

/// A player seated in a game room, as the server describes them.
@freezed
abstract class RoomPlayer with _$RoomPlayer {
  const factory RoomPlayer({
    required String id,
    required String name,
    required String color,
    @Default(false) bool isHost,
    @Default(false) bool isBot,

    /// Before the start: ready to play (the host always is).
    @Default(false) bool isReady,

    /// After the game: asked to play again.
    @Default(false) bool wantsRematch,

    /// Left the room after the start.
    @Default(false) bool hasLeft,

    /// False while the player has no live connection (the seat is kept).
    @Default(true) bool connected,
  }) = _RoomPlayer;

  factory RoomPlayer.fromJson(Map<String, dynamic> json) =>
      _$RoomPlayerFromJson(json);
}

/// The room this account is currently in. Replaces passing untyped route
/// arguments between screens.
@freezed
abstract class RoomSession with _$RoomSession {
  const factory RoomSession({
    required String roomCode,

    /// The room's server id (names its live `room/` channel). Null when the
    /// server didn't send it.
    String? roomId,

    /// This account's seat (player) id in the room.
    required String playerId,
    @Default(false) bool isHost,

    /// True once the game has started.
    @Default(false) bool isStarted,

    /// Seats in the room, as the server set them. Null when unknown.
    int? maxPlayers,

    /// This account's own player entry, when the server sent it.
    RoomPlayer? self,

    /// Which game the room plays and how (server game registry).
    @Default(GameChoice.ludo) String gameType,
    @Default(GameChoice.classic) String variant,
  }) = _RoomSession;

  /// From the create-room / join-room API response:
  /// `{"room": {"id": ..., "code": ..., "game_type": ..., "variant": ...,
  ///   "max_players": ..., "is_started": ...}, "player": {"id": ..., "is_host": ...}}`.
  factory RoomSession.fromRoomResponse(Map<String, dynamic> response) {
    final room = Map<String, dynamic>.from(response['room'] as Map);
    final player = Map<String, dynamic>.from(response['player'] as Map);
    final self = RoomPlayer.fromJson({
      ...player,
      'id': player['id'].toString(),
    });
    final maxPlayers = room['max_players'];
    return RoomSession(
      roomCode: room['code'].toString(),
      roomId: room['id']?.toString(),
      playerId: self.id,
      isHost: self.isHost,
      isStarted: room['is_started'] == true,
      maxPlayers: maxPlayers is num ? maxPlayers.toInt() : null,
      self: self,
      gameType: room['game_type']?.toString() ?? GameChoice.ludo,
      variant: room['variant']?.toString() ?? GameChoice.classic,
    );
  }

  /// The room the server says this account is in (app start).
  factory RoomSession.fromActiveRoom(ActiveRoom room) => RoomSession(
    roomCode: room.code,
    roomId: room.roomId,
    playerId: room.seatId,
    isHost: room.isHost,
    isStarted: room.started,
    maxPlayers: room.maxPlayers,
    gameType: room.gameType,
    variant: room.variant,
  );
}
