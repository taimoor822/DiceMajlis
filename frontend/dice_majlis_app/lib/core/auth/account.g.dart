// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Account _$AccountFromJson(Map<String, dynamic> json) => _Account(
  playerId: (json['player_id'] as num).toInt(),
  displayName: json['display_name'] as String,
  isGuest: json['is_guest'] as bool? ?? false,
  activeRoom: json['active_room'] == null
      ? null
      : ActiveRoom.fromJson(json['active_room'] as Map<String, dynamic>),
);

Map<String, dynamic> _$AccountToJson(_Account instance) => <String, dynamic>{
  'player_id': instance.playerId,
  'display_name': instance.displayName,
  'is_guest': instance.isGuest,
  'active_room': instance.activeRoom?.toJson(),
};

_ActiveRoom _$ActiveRoomFromJson(Map<String, dynamic> json) => _ActiveRoom(
  code: json['code'] as String,
  seatId: json['seat_id'] as String,
  isHost: json['is_host'] as bool? ?? false,
  maxPlayers: (json['max_players'] as num?)?.toInt(),
  started: json['started'] as bool? ?? false,
);

Map<String, dynamic> _$ActiveRoomToJson(_ActiveRoom instance) =>
    <String, dynamic>{
      'code': instance.code,
      'seat_id': instance.seatId,
      'is_host': instance.isHost,
      'max_players': instance.maxPlayers,
      'started': instance.started,
    };
