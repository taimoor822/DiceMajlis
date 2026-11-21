// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Account {

/// Permanent public 9-digit Player ID. Never changes.
 int get playerId; String get displayName;/// True until the player saves the account with email + password.
 bool get isGuest; String? get email;/// Key of a built-in avatar picture (see `PlayerAvatar`).
 String get avatar;/// ISO country code, or null when the player doesn't show one.
 String? get country;/// Spoken-language codes the player shows (`en`, `ar`, ...).
 List<String> get languages; int get level; int get xp;/// XP where this level starts and where the next one starts.
 int get levelXp; int get nextLevelXp;/// The room this account is in right now (to go straight back to it).
 ActiveRoom? get activeRoom;
/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountCopyWith<Account> get copyWith => _$AccountCopyWithImpl<Account>(this as Account, _$identity);

  /// Serializes this Account to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Account&&(identical(other.playerId, playerId) || other.playerId == playerId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.isGuest, isGuest) || other.isGuest == isGuest)&&(identical(other.email, email) || other.email == email)&&(identical(other.avatar, avatar) || other.avatar == avatar)&&(identical(other.country, country) || other.country == country)&&const DeepCollectionEquality().equals(other.languages, languages)&&(identical(other.level, level) || other.level == level)&&(identical(other.xp, xp) || other.xp == xp)&&(identical(other.levelXp, levelXp) || other.levelXp == levelXp)&&(identical(other.nextLevelXp, nextLevelXp) || other.nextLevelXp == nextLevelXp)&&(identical(other.activeRoom, activeRoom) || other.activeRoom == activeRoom));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,playerId,displayName,isGuest,email,avatar,country,const DeepCollectionEquality().hash(languages),level,xp,levelXp,nextLevelXp,activeRoom);

@override
String toString() {
  return 'Account(playerId: $playerId, displayName: $displayName, isGuest: $isGuest, email: $email, avatar: $avatar, country: $country, languages: $languages, level: $level, xp: $xp, levelXp: $levelXp, nextLevelXp: $nextLevelXp, activeRoom: $activeRoom)';
}


}

/// @nodoc
abstract mixin class $AccountCopyWith<$Res>  {
  factory $AccountCopyWith(Account value, $Res Function(Account) _then) = _$AccountCopyWithImpl;
@useResult
$Res call({
 int playerId, String displayName, bool isGuest, String? email, String avatar, String? country, List<String> languages, int level, int xp, int levelXp, int nextLevelXp, ActiveRoom? activeRoom
});


$ActiveRoomCopyWith<$Res>? get activeRoom;

}
/// @nodoc
class _$AccountCopyWithImpl<$Res>
    implements $AccountCopyWith<$Res> {
  _$AccountCopyWithImpl(this._self, this._then);

  final Account _self;
  final $Res Function(Account) _then;

/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? playerId = null,Object? displayName = null,Object? isGuest = null,Object? email = freezed,Object? avatar = null,Object? country = freezed,Object? languages = null,Object? level = null,Object? xp = null,Object? levelXp = null,Object? nextLevelXp = null,Object? activeRoom = freezed,}) {
  return _then(_self.copyWith(
playerId: null == playerId ? _self.playerId : playerId // ignore: cast_nullable_to_non_nullable
as int,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,isGuest: null == isGuest ? _self.isGuest : isGuest // ignore: cast_nullable_to_non_nullable
as bool,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,avatar: null == avatar ? _self.avatar : avatar // ignore: cast_nullable_to_non_nullable
as String,country: freezed == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String?,languages: null == languages ? _self.languages : languages // ignore: cast_nullable_to_non_nullable
as List<String>,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as int,xp: null == xp ? _self.xp : xp // ignore: cast_nullable_to_non_nullable
as int,levelXp: null == levelXp ? _self.levelXp : levelXp // ignore: cast_nullable_to_non_nullable
as int,nextLevelXp: null == nextLevelXp ? _self.nextLevelXp : nextLevelXp // ignore: cast_nullable_to_non_nullable
as int,activeRoom: freezed == activeRoom ? _self.activeRoom : activeRoom // ignore: cast_nullable_to_non_nullable
as ActiveRoom?,
  ));
}
/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActiveRoomCopyWith<$Res>? get activeRoom {
    if (_self.activeRoom == null) {
    return null;
  }

  return $ActiveRoomCopyWith<$Res>(_self.activeRoom!, (value) {
    return _then(_self.copyWith(activeRoom: value));
  });
}
}


/// Adds pattern-matching-related methods to [Account].
extension AccountPatterns on Account {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Account value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Account() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Account value)  $default,){
final _that = this;
switch (_that) {
case _Account():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Account value)?  $default,){
final _that = this;
switch (_that) {
case _Account() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int playerId,  String displayName,  bool isGuest,  String? email,  String avatar,  String? country,  List<String> languages,  int level,  int xp,  int levelXp,  int nextLevelXp,  ActiveRoom? activeRoom)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Account() when $default != null:
return $default(_that.playerId,_that.displayName,_that.isGuest,_that.email,_that.avatar,_that.country,_that.languages,_that.level,_that.xp,_that.levelXp,_that.nextLevelXp,_that.activeRoom);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int playerId,  String displayName,  bool isGuest,  String? email,  String avatar,  String? country,  List<String> languages,  int level,  int xp,  int levelXp,  int nextLevelXp,  ActiveRoom? activeRoom)  $default,) {final _that = this;
switch (_that) {
case _Account():
return $default(_that.playerId,_that.displayName,_that.isGuest,_that.email,_that.avatar,_that.country,_that.languages,_that.level,_that.xp,_that.levelXp,_that.nextLevelXp,_that.activeRoom);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int playerId,  String displayName,  bool isGuest,  String? email,  String avatar,  String? country,  List<String> languages,  int level,  int xp,  int levelXp,  int nextLevelXp,  ActiveRoom? activeRoom)?  $default,) {final _that = this;
switch (_that) {
case _Account() when $default != null:
return $default(_that.playerId,_that.displayName,_that.isGuest,_that.email,_that.avatar,_that.country,_that.languages,_that.level,_that.xp,_that.levelXp,_that.nextLevelXp,_that.activeRoom);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Account extends Account {
  const _Account({required this.playerId, required this.displayName, this.isGuest = false, this.email, this.avatar = '', this.country, final  List<String> languages = const <String>[], this.level = 1, this.xp = 0, this.levelXp = 0, this.nextLevelXp = 0, this.activeRoom}): _languages = languages,super._();
  factory _Account.fromJson(Map<String, dynamic> json) => _$AccountFromJson(json);

/// Permanent public 9-digit Player ID. Never changes.
@override final  int playerId;
@override final  String displayName;
/// True until the player saves the account with email + password.
@override@JsonKey() final  bool isGuest;
@override final  String? email;
/// Key of a built-in avatar picture (see `PlayerAvatar`).
@override@JsonKey() final  String avatar;
/// ISO country code, or null when the player doesn't show one.
@override final  String? country;
/// Spoken-language codes the player shows (`en`, `ar`, ...).
 final  List<String> _languages;
/// Spoken-language codes the player shows (`en`, `ar`, ...).
@override@JsonKey() List<String> get languages {
  if (_languages is EqualUnmodifiableListView) return _languages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_languages);
}

@override@JsonKey() final  int level;
@override@JsonKey() final  int xp;
/// XP where this level starts and where the next one starts.
@override@JsonKey() final  int levelXp;
@override@JsonKey() final  int nextLevelXp;
/// The room this account is in right now (to go straight back to it).
@override final  ActiveRoom? activeRoom;

/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountCopyWith<_Account> get copyWith => __$AccountCopyWithImpl<_Account>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AccountToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Account&&(identical(other.playerId, playerId) || other.playerId == playerId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.isGuest, isGuest) || other.isGuest == isGuest)&&(identical(other.email, email) || other.email == email)&&(identical(other.avatar, avatar) || other.avatar == avatar)&&(identical(other.country, country) || other.country == country)&&const DeepCollectionEquality().equals(other._languages, _languages)&&(identical(other.level, level) || other.level == level)&&(identical(other.xp, xp) || other.xp == xp)&&(identical(other.levelXp, levelXp) || other.levelXp == levelXp)&&(identical(other.nextLevelXp, nextLevelXp) || other.nextLevelXp == nextLevelXp)&&(identical(other.activeRoom, activeRoom) || other.activeRoom == activeRoom));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,playerId,displayName,isGuest,email,avatar,country,const DeepCollectionEquality().hash(_languages),level,xp,levelXp,nextLevelXp,activeRoom);

@override
String toString() {
  return 'Account(playerId: $playerId, displayName: $displayName, isGuest: $isGuest, email: $email, avatar: $avatar, country: $country, languages: $languages, level: $level, xp: $xp, levelXp: $levelXp, nextLevelXp: $nextLevelXp, activeRoom: $activeRoom)';
}


}

/// @nodoc
abstract mixin class _$AccountCopyWith<$Res> implements $AccountCopyWith<$Res> {
  factory _$AccountCopyWith(_Account value, $Res Function(_Account) _then) = __$AccountCopyWithImpl;
@override @useResult
$Res call({
 int playerId, String displayName, bool isGuest, String? email, String avatar, String? country, List<String> languages, int level, int xp, int levelXp, int nextLevelXp, ActiveRoom? activeRoom
});


@override $ActiveRoomCopyWith<$Res>? get activeRoom;

}
/// @nodoc
class __$AccountCopyWithImpl<$Res>
    implements _$AccountCopyWith<$Res> {
  __$AccountCopyWithImpl(this._self, this._then);

  final _Account _self;
  final $Res Function(_Account) _then;

/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? playerId = null,Object? displayName = null,Object? isGuest = null,Object? email = freezed,Object? avatar = null,Object? country = freezed,Object? languages = null,Object? level = null,Object? xp = null,Object? levelXp = null,Object? nextLevelXp = null,Object? activeRoom = freezed,}) {
  return _then(_Account(
playerId: null == playerId ? _self.playerId : playerId // ignore: cast_nullable_to_non_nullable
as int,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,isGuest: null == isGuest ? _self.isGuest : isGuest // ignore: cast_nullable_to_non_nullable
as bool,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,avatar: null == avatar ? _self.avatar : avatar // ignore: cast_nullable_to_non_nullable
as String,country: freezed == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String?,languages: null == languages ? _self._languages : languages // ignore: cast_nullable_to_non_nullable
as List<String>,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as int,xp: null == xp ? _self.xp : xp // ignore: cast_nullable_to_non_nullable
as int,levelXp: null == levelXp ? _self.levelXp : levelXp // ignore: cast_nullable_to_non_nullable
as int,nextLevelXp: null == nextLevelXp ? _self.nextLevelXp : nextLevelXp // ignore: cast_nullable_to_non_nullable
as int,activeRoom: freezed == activeRoom ? _self.activeRoom : activeRoom // ignore: cast_nullable_to_non_nullable
as ActiveRoom?,
  ));
}

/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActiveRoomCopyWith<$Res>? get activeRoom {
    if (_self.activeRoom == null) {
    return null;
  }

  return $ActiveRoomCopyWith<$Res>(_self.activeRoom!, (value) {
    return _then(_self.copyWith(activeRoom: value));
  });
}
}


/// @nodoc
mixin _$ActiveRoom {

 String get code; String get seatId; bool get isHost; int? get maxPlayers;/// True once the game has started (go to the board, not the waiting room).
 bool get started;/// Which game the room plays (server game registry); older servers send
/// nothing, and every room was Classic Ludo then.
 String get gameType; String get variant;
/// Create a copy of ActiveRoom
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActiveRoomCopyWith<ActiveRoom> get copyWith => _$ActiveRoomCopyWithImpl<ActiveRoom>(this as ActiveRoom, _$identity);

  /// Serializes this ActiveRoom to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActiveRoom&&(identical(other.code, code) || other.code == code)&&(identical(other.seatId, seatId) || other.seatId == seatId)&&(identical(other.isHost, isHost) || other.isHost == isHost)&&(identical(other.maxPlayers, maxPlayers) || other.maxPlayers == maxPlayers)&&(identical(other.started, started) || other.started == started)&&(identical(other.gameType, gameType) || other.gameType == gameType)&&(identical(other.variant, variant) || other.variant == variant));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,code,seatId,isHost,maxPlayers,started,gameType,variant);

@override
String toString() {
  return 'ActiveRoom(code: $code, seatId: $seatId, isHost: $isHost, maxPlayers: $maxPlayers, started: $started, gameType: $gameType, variant: $variant)';
}


}

/// @nodoc
abstract mixin class $ActiveRoomCopyWith<$Res>  {
  factory $ActiveRoomCopyWith(ActiveRoom value, $Res Function(ActiveRoom) _then) = _$ActiveRoomCopyWithImpl;
@useResult
$Res call({
 String code, String seatId, bool isHost, int? maxPlayers, bool started, String gameType, String variant
});




}
/// @nodoc
class _$ActiveRoomCopyWithImpl<$Res>
    implements $ActiveRoomCopyWith<$Res> {
  _$ActiveRoomCopyWithImpl(this._self, this._then);

  final ActiveRoom _self;
  final $Res Function(ActiveRoom) _then;

/// Create a copy of ActiveRoom
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? seatId = null,Object? isHost = null,Object? maxPlayers = freezed,Object? started = null,Object? gameType = null,Object? variant = null,}) {
  return _then(_self.copyWith(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,seatId: null == seatId ? _self.seatId : seatId // ignore: cast_nullable_to_non_nullable
as String,isHost: null == isHost ? _self.isHost : isHost // ignore: cast_nullable_to_non_nullable
as bool,maxPlayers: freezed == maxPlayers ? _self.maxPlayers : maxPlayers // ignore: cast_nullable_to_non_nullable
as int?,started: null == started ? _self.started : started // ignore: cast_nullable_to_non_nullable
as bool,gameType: null == gameType ? _self.gameType : gameType // ignore: cast_nullable_to_non_nullable
as String,variant: null == variant ? _self.variant : variant // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ActiveRoom].
extension ActiveRoomPatterns on ActiveRoom {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActiveRoom value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActiveRoom() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActiveRoom value)  $default,){
final _that = this;
switch (_that) {
case _ActiveRoom():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActiveRoom value)?  $default,){
final _that = this;
switch (_that) {
case _ActiveRoom() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String code,  String seatId,  bool isHost,  int? maxPlayers,  bool started,  String gameType,  String variant)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActiveRoom() when $default != null:
return $default(_that.code,_that.seatId,_that.isHost,_that.maxPlayers,_that.started,_that.gameType,_that.variant);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String code,  String seatId,  bool isHost,  int? maxPlayers,  bool started,  String gameType,  String variant)  $default,) {final _that = this;
switch (_that) {
case _ActiveRoom():
return $default(_that.code,_that.seatId,_that.isHost,_that.maxPlayers,_that.started,_that.gameType,_that.variant);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String code,  String seatId,  bool isHost,  int? maxPlayers,  bool started,  String gameType,  String variant)?  $default,) {final _that = this;
switch (_that) {
case _ActiveRoom() when $default != null:
return $default(_that.code,_that.seatId,_that.isHost,_that.maxPlayers,_that.started,_that.gameType,_that.variant);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ActiveRoom implements ActiveRoom {
  const _ActiveRoom({required this.code, required this.seatId, this.isHost = false, this.maxPlayers, this.started = false, this.gameType = 'ludo', this.variant = 'classic'});
  factory _ActiveRoom.fromJson(Map<String, dynamic> json) => _$ActiveRoomFromJson(json);

@override final  String code;
@override final  String seatId;
@override@JsonKey() final  bool isHost;
@override final  int? maxPlayers;
/// True once the game has started (go to the board, not the waiting room).
@override@JsonKey() final  bool started;
/// Which game the room plays (server game registry); older servers send
/// nothing, and every room was Classic Ludo then.
@override@JsonKey() final  String gameType;
@override@JsonKey() final  String variant;

/// Create a copy of ActiveRoom
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActiveRoomCopyWith<_ActiveRoom> get copyWith => __$ActiveRoomCopyWithImpl<_ActiveRoom>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ActiveRoomToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActiveRoom&&(identical(other.code, code) || other.code == code)&&(identical(other.seatId, seatId) || other.seatId == seatId)&&(identical(other.isHost, isHost) || other.isHost == isHost)&&(identical(other.maxPlayers, maxPlayers) || other.maxPlayers == maxPlayers)&&(identical(other.started, started) || other.started == started)&&(identical(other.gameType, gameType) || other.gameType == gameType)&&(identical(other.variant, variant) || other.variant == variant));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,code,seatId,isHost,maxPlayers,started,gameType,variant);

@override
String toString() {
  return 'ActiveRoom(code: $code, seatId: $seatId, isHost: $isHost, maxPlayers: $maxPlayers, started: $started, gameType: $gameType, variant: $variant)';
}


}

/// @nodoc
abstract mixin class _$ActiveRoomCopyWith<$Res> implements $ActiveRoomCopyWith<$Res> {
  factory _$ActiveRoomCopyWith(_ActiveRoom value, $Res Function(_ActiveRoom) _then) = __$ActiveRoomCopyWithImpl;
@override @useResult
$Res call({
 String code, String seatId, bool isHost, int? maxPlayers, bool started, String gameType, String variant
});




}
/// @nodoc
class __$ActiveRoomCopyWithImpl<$Res>
    implements _$ActiveRoomCopyWith<$Res> {
  __$ActiveRoomCopyWithImpl(this._self, this._then);

  final _ActiveRoom _self;
  final $Res Function(_ActiveRoom) _then;

/// Create a copy of ActiveRoom
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? seatId = null,Object? isHost = null,Object? maxPlayers = freezed,Object? started = null,Object? gameType = null,Object? variant = null,}) {
  return _then(_ActiveRoom(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,seatId: null == seatId ? _self.seatId : seatId // ignore: cast_nullable_to_non_nullable
as String,isHost: null == isHost ? _self.isHost : isHost // ignore: cast_nullable_to_non_nullable
as bool,maxPlayers: freezed == maxPlayers ? _self.maxPlayers : maxPlayers // ignore: cast_nullable_to_non_nullable
as int?,started: null == started ? _self.started : started // ignore: cast_nullable_to_non_nullable
as bool,gameType: null == gameType ? _self.gameType : gameType // ignore: cast_nullable_to_non_nullable
as String,variant: null == variant ? _self.variant : variant // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
