// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Account _$AccountFromJson(Map<String, dynamic> json) => _Account(
  playerId: (json['player_id'] as num).toInt(),
  displayName: json['display_name'] as String,
  isGuest: json['is_guest'] as bool? ?? false,
  email: json['email'] as String?,
  avatar: json['avatar'] as String? ?? '',
  country: json['country'] as String?,
  languages:
      (json['languages'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  linked:
      (json['linked'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  level: (json['level'] as num?)?.toInt() ?? 1,
  xp: (json['xp'] as num?)?.toInt() ?? 0,
  levelXp: (json['level_xp'] as num?)?.toInt() ?? 0,
  nextLevelXp: (json['next_level_xp'] as num?)?.toInt() ?? 0,
  activeRoom: json['active_room'] == null
      ? null
      : ActiveRoom.fromJson(json['active_room'] as Map<String, dynamic>),
);

Map<String, dynamic> _$AccountToJson(_Account instance) => <String, dynamic>{
  'player_id': instance.playerId,
  'display_name': instance.displayName,
  'is_guest': instance.isGuest,
  'email': instance.email,
  'avatar': instance.avatar,
  'country': instance.country,
  'languages': instance.languages,
  'linked': instance.linked,
  'level': instance.level,
  'xp': instance.xp,
  'level_xp': instance.levelXp,
  'next_level_xp': instance.nextLevelXp,
  'active_room': instance.activeRoom?.toJson(),
};

_ActiveRoom _$ActiveRoomFromJson(Map<String, dynamic> json) => _ActiveRoom(
  code: json['code'] as String,
  seatId: json['seat_id'] as String,
  roomId: json['room_id'] as String?,
  isHost: json['is_host'] as bool? ?? false,
  maxPlayers: (json['max_players'] as num?)?.toInt(),
  started: json['started'] as bool? ?? false,
  gameType: json['game_type'] as String? ?? 'ludo',
  variant: json['variant'] as String? ?? 'classic',
);

Map<String, dynamic> _$ActiveRoomToJson(_ActiveRoom instance) =>
    <String, dynamic>{
      'code': instance.code,
      'seat_id': instance.seatId,
      'room_id': instance.roomId,
      'is_host': instance.isHost,
      'max_players': instance.maxPlayers,
      'started': instance.started,
      'game_type': instance.gameType,
      'variant': instance.variant,
    };
