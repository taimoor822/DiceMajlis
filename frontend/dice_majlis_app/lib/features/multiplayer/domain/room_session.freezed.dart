// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'room_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RoomPlayer {

 String get id; String get name; String get color; bool get isHost; bool get isBot;
/// Create a copy of RoomPlayer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoomPlayerCopyWith<RoomPlayer> get copyWith => _$RoomPlayerCopyWithImpl<RoomPlayer>(this as RoomPlayer, _$identity);

  /// Serializes this RoomPlayer to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoomPlayer&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.color, color) || other.color == color)&&(identical(other.isHost, isHost) || other.isHost == isHost)&&(identical(other.isBot, isBot) || other.isBot == isBot));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,color,isHost,isBot);

@override
String toString() {
  return 'RoomPlayer(id: $id, name: $name, color: $color, isHost: $isHost, isBot: $isBot)';
}


}

/// @nodoc
abstract mixin class $RoomPlayerCopyWith<$Res>  {
  factory $RoomPlayerCopyWith(RoomPlayer value, $Res Function(RoomPlayer) _then) = _$RoomPlayerCopyWithImpl;
@useResult
$Res call({
 String id, String name, String color, bool isHost, bool isBot
});




}
/// @nodoc
class _$RoomPlayerCopyWithImpl<$Res>
    implements $RoomPlayerCopyWith<$Res> {
  _$RoomPlayerCopyWithImpl(this._self, this._then);

  final RoomPlayer _self;
  final $Res Function(RoomPlayer) _then;

/// Create a copy of RoomPlayer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? color = null,Object? isHost = null,Object? isBot = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,color: null == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String,isHost: null == isHost ? _self.isHost : isHost // ignore: cast_nullable_to_non_nullable
as bool,isBot: null == isBot ? _self.isBot : isBot // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [RoomPlayer].
extension RoomPlayerPatterns on RoomPlayer {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoomPlayer value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoomPlayer() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoomPlayer value)  $default,){
final _that = this;
switch (_that) {
case _RoomPlayer():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoomPlayer value)?  $default,){
final _that = this;
switch (_that) {
case _RoomPlayer() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String color,  bool isHost,  bool isBot)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoomPlayer() when $default != null:
return $default(_that.id,_that.name,_that.color,_that.isHost,_that.isBot);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String color,  bool isHost,  bool isBot)  $default,) {final _that = this;
switch (_that) {
case _RoomPlayer():
return $default(_that.id,_that.name,_that.color,_that.isHost,_that.isBot);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String color,  bool isHost,  bool isBot)?  $default,) {final _that = this;
switch (_that) {
case _RoomPlayer() when $default != null:
return $default(_that.id,_that.name,_that.color,_that.isHost,_that.isBot);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoomPlayer implements RoomPlayer {
  const _RoomPlayer({required this.id, required this.name, required this.color, this.isHost = false, this.isBot = false});
  factory _RoomPlayer.fromJson(Map<String, dynamic> json) => _$RoomPlayerFromJson(json);

@override final  String id;
@override final  String name;
@override final  String color;
@override@JsonKey() final  bool isHost;
@override@JsonKey() final  bool isBot;

/// Create a copy of RoomPlayer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoomPlayerCopyWith<_RoomPlayer> get copyWith => __$RoomPlayerCopyWithImpl<_RoomPlayer>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoomPlayerToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoomPlayer&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.color, color) || other.color == color)&&(identical(other.isHost, isHost) || other.isHost == isHost)&&(identical(other.isBot, isBot) || other.isBot == isBot));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,color,isHost,isBot);

@override
String toString() {
  return 'RoomPlayer(id: $id, name: $name, color: $color, isHost: $isHost, isBot: $isBot)';
}


}

/// @nodoc
abstract mixin class _$RoomPlayerCopyWith<$Res> implements $RoomPlayerCopyWith<$Res> {
  factory _$RoomPlayerCopyWith(_RoomPlayer value, $Res Function(_RoomPlayer) _then) = __$RoomPlayerCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String color, bool isHost, bool isBot
});




}
/// @nodoc
class __$RoomPlayerCopyWithImpl<$Res>
    implements _$RoomPlayerCopyWith<$Res> {
  __$RoomPlayerCopyWithImpl(this._self, this._then);

  final _RoomPlayer _self;
  final $Res Function(_RoomPlayer) _then;

/// Create a copy of RoomPlayer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? color = null,Object? isHost = null,Object? isBot = null,}) {
  return _then(_RoomPlayer(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,color: null == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String,isHost: null == isHost ? _self.isHost : isHost // ignore: cast_nullable_to_non_nullable
as bool,isBot: null == isBot ? _self.isBot : isBot // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$RoomSession {

 String get roomCode;/// The room's server id (names its live `room/` channel). Null when the
/// server didn't send it.
 String? get roomId;/// This account's seat (player) id in the room.
 String get playerId; bool get isHost;/// True once the game has started.
 bool get isStarted;/// Seats in the room, as the server set them. Null when unknown.
 int? get maxPlayers;/// This account's own player entry, when the server sent it.
 RoomPlayer? get self;/// Which game the room plays and how (server game registry).
 String get gameType; String get variant;
/// Create a copy of RoomSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoomSessionCopyWith<RoomSession> get copyWith => _$RoomSessionCopyWithImpl<RoomSession>(this as RoomSession, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoomSession&&(identical(other.roomCode, roomCode) || other.roomCode == roomCode)&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.playerId, playerId) || other.playerId == playerId)&&(identical(other.isHost, isHost) || other.isHost == isHost)&&(identical(other.isStarted, isStarted) || other.isStarted == isStarted)&&(identical(other.maxPlayers, maxPlayers) || other.maxPlayers == maxPlayers)&&(identical(other.self, self) || other.self == self)&&(identical(other.gameType, gameType) || other.gameType == gameType)&&(identical(other.variant, variant) || other.variant == variant));
}


@override
int get hashCode => Object.hash(runtimeType,roomCode,roomId,playerId,isHost,isStarted,maxPlayers,self,gameType,variant);

@override
String toString() {
  return 'RoomSession(roomCode: $roomCode, roomId: $roomId, playerId: $playerId, isHost: $isHost, isStarted: $isStarted, maxPlayers: $maxPlayers, self: $self, gameType: $gameType, variant: $variant)';
}


}

/// @nodoc
abstract mixin class $RoomSessionCopyWith<$Res>  {
  factory $RoomSessionCopyWith(RoomSession value, $Res Function(RoomSession) _then) = _$RoomSessionCopyWithImpl;
@useResult
$Res call({
 String roomCode, String? roomId, String playerId, bool isHost, bool isStarted, int? maxPlayers, RoomPlayer? self, String gameType, String variant
});


$RoomPlayerCopyWith<$Res>? get self;

}
/// @nodoc
class _$RoomSessionCopyWithImpl<$Res>
    implements $RoomSessionCopyWith<$Res> {
  _$RoomSessionCopyWithImpl(this._self, this._then);

  final RoomSession _self;
  final $Res Function(RoomSession) _then;

/// Create a copy of RoomSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? roomCode = null,Object? roomId = freezed,Object? playerId = null,Object? isHost = null,Object? isStarted = null,Object? maxPlayers = freezed,Object? self = freezed,Object? gameType = null,Object? variant = null,}) {
  return _then(_self.copyWith(
roomCode: null == roomCode ? _self.roomCode : roomCode // ignore: cast_nullable_to_non_nullable
as String,roomId: freezed == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String?,playerId: null == playerId ? _self.playerId : playerId // ignore: cast_nullable_to_non_nullable
as String,isHost: null == isHost ? _self.isHost : isHost // ignore: cast_nullable_to_non_nullable
as bool,isStarted: null == isStarted ? _self.isStarted : isStarted // ignore: cast_nullable_to_non_nullable
as bool,maxPlayers: freezed == maxPlayers ? _self.maxPlayers : maxPlayers // ignore: cast_nullable_to_non_nullable
as int?,self: freezed == self ? _self.self : self // ignore: cast_nullable_to_non_nullable
as RoomPlayer?,gameType: null == gameType ? _self.gameType : gameType // ignore: cast_nullable_to_non_nullable
as String,variant: null == variant ? _self.variant : variant // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of RoomSession
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoomPlayerCopyWith<$Res>? get self {
    if (_self.self == null) {
    return null;
  }

  return $RoomPlayerCopyWith<$Res>(_self.self!, (value) {
    return _then(_self.copyWith(self: value));
  });
}
}


/// Adds pattern-matching-related methods to [RoomSession].
extension RoomSessionPatterns on RoomSession {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoomSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoomSession() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoomSession value)  $default,){
final _that = this;
switch (_that) {
case _RoomSession():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoomSession value)?  $default,){
final _that = this;
switch (_that) {
case _RoomSession() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String roomCode,  String? roomId,  String playerId,  bool isHost,  bool isStarted,  int? maxPlayers,  RoomPlayer? self,  String gameType,  String variant)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoomSession() when $default != null:
return $default(_that.roomCode,_that.roomId,_that.playerId,_that.isHost,_that.isStarted,_that.maxPlayers,_that.self,_that.gameType,_that.variant);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String roomCode,  String? roomId,  String playerId,  bool isHost,  bool isStarted,  int? maxPlayers,  RoomPlayer? self,  String gameType,  String variant)  $default,) {final _that = this;
switch (_that) {
case _RoomSession():
return $default(_that.roomCode,_that.roomId,_that.playerId,_that.isHost,_that.isStarted,_that.maxPlayers,_that.self,_that.gameType,_that.variant);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String roomCode,  String? roomId,  String playerId,  bool isHost,  bool isStarted,  int? maxPlayers,  RoomPlayer? self,  String gameType,  String variant)?  $default,) {final _that = this;
switch (_that) {
case _RoomSession() when $default != null:
return $default(_that.roomCode,_that.roomId,_that.playerId,_that.isHost,_that.isStarted,_that.maxPlayers,_that.self,_that.gameType,_that.variant);case _:
  return null;

}
}

}

/// @nodoc


class _RoomSession implements RoomSession {
  const _RoomSession({required this.roomCode, this.roomId, required this.playerId, this.isHost = false, this.isStarted = false, this.maxPlayers, this.self, this.gameType = GameChoice.ludo, this.variant = GameChoice.classic});
  

@override final  String roomCode;
/// The room's server id (names its live `room/` channel). Null when the
/// server didn't send it.
@override final  String? roomId;
/// This account's seat (player) id in the room.
@override final  String playerId;
@override@JsonKey() final  bool isHost;
/// True once the game has started.
@override@JsonKey() final  bool isStarted;
/// Seats in the room, as the server set them. Null when unknown.
@override final  int? maxPlayers;
/// This account's own player entry, when the server sent it.
@override final  RoomPlayer? self;
/// Which game the room plays and how (server game registry).
@override@JsonKey() final  String gameType;
@override@JsonKey() final  String variant;

/// Create a copy of RoomSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoomSessionCopyWith<_RoomSession> get copyWith => __$RoomSessionCopyWithImpl<_RoomSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoomSession&&(identical(other.roomCode, roomCode) || other.roomCode == roomCode)&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.playerId, playerId) || other.playerId == playerId)&&(identical(other.isHost, isHost) || other.isHost == isHost)&&(identical(other.isStarted, isStarted) || other.isStarted == isStarted)&&(identical(other.maxPlayers, maxPlayers) || other.maxPlayers == maxPlayers)&&(identical(other.self, self) || other.self == self)&&(identical(other.gameType, gameType) || other.gameType == gameType)&&(identical(other.variant, variant) || other.variant == variant));
}


@override
int get hashCode => Object.hash(runtimeType,roomCode,roomId,playerId,isHost,isStarted,maxPlayers,self,gameType,variant);

@override
String toString() {
  return 'RoomSession(roomCode: $roomCode, roomId: $roomId, playerId: $playerId, isHost: $isHost, isStarted: $isStarted, maxPlayers: $maxPlayers, self: $self, gameType: $gameType, variant: $variant)';
}


}

/// @nodoc
abstract mixin class _$RoomSessionCopyWith<$Res> implements $RoomSessionCopyWith<$Res> {
  factory _$RoomSessionCopyWith(_RoomSession value, $Res Function(_RoomSession) _then) = __$RoomSessionCopyWithImpl;
@override @useResult
$Res call({
 String roomCode, String? roomId, String playerId, bool isHost, bool isStarted, int? maxPlayers, RoomPlayer? self, String gameType, String variant
});


@override $RoomPlayerCopyWith<$Res>? get self;

}
/// @nodoc
class __$RoomSessionCopyWithImpl<$Res>
    implements _$RoomSessionCopyWith<$Res> {
  __$RoomSessionCopyWithImpl(this._self, this._then);

  final _RoomSession _self;
  final $Res Function(_RoomSession) _then;

/// Create a copy of RoomSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roomCode = null,Object? roomId = freezed,Object? playerId = null,Object? isHost = null,Object? isStarted = null,Object? maxPlayers = freezed,Object? self = freezed,Object? gameType = null,Object? variant = null,}) {
  return _then(_RoomSession(
roomCode: null == roomCode ? _self.roomCode : roomCode // ignore: cast_nullable_to_non_nullable
as String,roomId: freezed == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String?,playerId: null == playerId ? _self.playerId : playerId // ignore: cast_nullable_to_non_nullable
as String,isHost: null == isHost ? _self.isHost : isHost // ignore: cast_nullable_to_non_nullable
as bool,isStarted: null == isStarted ? _self.isStarted : isStarted // ignore: cast_nullable_to_non_nullable
as bool,maxPlayers: freezed == maxPlayers ? _self.maxPlayers : maxPlayers // ignore: cast_nullable_to_non_nullable
as int?,self: freezed == self ? _self.self : self // ignore: cast_nullable_to_non_nullable
as RoomPlayer?,gameType: null == gameType ? _self.gameType : gameType // ignore: cast_nullable_to_non_nullable
as String,variant: null == variant ? _self.variant : variant // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of RoomSession
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoomPlayerCopyWith<$Res>? get self {
    if (_self.self == null) {
    return null;
  }

  return $RoomPlayerCopyWith<$Res>(_self.self!, (value) {
    return _then(_self.copyWith(self: value));
  });
}
}

// dart format on
