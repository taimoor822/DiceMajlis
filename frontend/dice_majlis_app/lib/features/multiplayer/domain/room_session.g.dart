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
);

Map<String, dynamic> _$RoomPlayerToJson(_RoomPlayer instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'color': instance.color,
      'is_host': instance.isHost,
      'is_bot': instance.isBot,
    };
