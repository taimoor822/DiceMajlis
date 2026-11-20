import 'package:freezed_annotation/freezed_annotation.dart';

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
  }) = _RoomPlayer;

  factory RoomPlayer.fromJson(Map<String, dynamic> json) =>
      _$RoomPlayerFromJson(json);
}

/// The room this device is currently in. Replaces passing untyped route
/// arguments between screens (those were lost on a web refresh).
@freezed
abstract class RoomSession with _$RoomSession {
  const factory RoomSession({
    required String roomCode,
    required String playerId,

    /// Secret only this device holds; proves the seat is ours on start /
    /// roll / move. Never shown, never shared.
    required String playerToken,
    @Default(false) bool isHost,

    /// Seats in the room, as the server set them. Null when unknown
    /// (e.g. restored after a web refresh).
    int? maxPlayers,

    /// This device's own player entry, when the server sent it.
    RoomPlayer? self,
  }) = _RoomSession;

  /// From the create-room / join-room API response:
  /// `{"room": {"code": ..., "max_players": ...},
  ///   "player": {"id": ..., "is_host": ...}, "player_token": ...}`.
  factory RoomSession.fromRoomResponse(Map<String, dynamic> response) {
    final room = Map<String, dynamic>.from(response['room'] as Map);
    final player = Map<String, dynamic>.from(response['player'] as Map);
    final self = RoomPlayer.fromJson({
      ...player,
      'id': player['id'].toString(),
    });
    final maxPlayers = room['max_players'];
    final token = response['player_token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('Room response has no player_token');
    }
    return RoomSession(
      roomCode: room['code'].toString(),
      playerId: self.id,
      playerToken: token,
      isHost: self.isHost,
      maxPlayers: maxPlayers is num ? maxPlayers.toInt() : null,
      self: self,
    );
  }
}
