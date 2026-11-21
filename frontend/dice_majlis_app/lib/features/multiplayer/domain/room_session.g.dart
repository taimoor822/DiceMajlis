// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RoomPlayer _$RoomPlayerFromJson(Map<String, dynamic> json) => _RoomPlayer(
  id: json['id'] as String,
  name: json['name'] as String,
  color: json['color'] as String,
  isHost: json['is_host'] as bool? ?? false,
  isBot: json['is_bot'] as bool? ?? false,
  isReady: json['is_ready'] as bool? ?? false,
  wantsRematch: json['wants_rematch'] as bool? ?? false,
  hasLeft: json['has_left'] as bool? ?? false,
);

Map<String, dynamic> _$RoomPlayerToJson(_RoomPlayer instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'color': instance.color,
      'is_host': instance.isHost,
      'is_bot': instance.isBot,
      'is_ready': instance.isReady,
      'wants_rematch': instance.wantsRematch,
      'has_left': instance.hasLeft,
    };
