/// Where a private room stands (server: `game/rooms.py`, `room_updated`).
enum RoomStatus {
  /// Someone isn't ready yet.
  waiting,

  /// Everyone is ready: the host may start.
  ready,

  /// The start countdown runs.
  starting,
  playing,

  /// Game over: players may ask for a rematch.
  finished,
  closed,

  /// A status this version of the app doesn't know.
  unknown;

  static RoomStatus parse(Object? value) => RoomStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => RoomStatus.unknown,
  );
}

/// A rule the host may change, with the values the server offers.
class RoomOptionChoice {
  const RoomOptionChoice({
    required this.key,
    required this.defaultValue,
    required this.choices,
  });

  factory RoomOptionChoice.fromJson(Map<String, dynamic> json) =>
      RoomOptionChoice(
        key: json['key'].toString(),
        defaultValue: json['default'],
        choices: List<Object?>.from(json['choices'] as List? ?? const []),
      );

  /// The server's rule name, e.g. `turn_timeout_seconds`.
  final String key;
  final Object? defaultValue;
  final List<Object?> choices;
}

/// The `room_updated` message: everything about the room except who sits in it.
class RoomInfo {
  const RoomInfo({
    required this.status,
    this.isLocked = false,
    this.variant,
    this.maxPlayers,
    this.options = const {},
    this.optionChoices = const [],
    this.hostId,
    this.startsIn,
    this.nextRoomCode,
    this.nextRoomId,
  });

  factory RoomInfo.fromJson(Map<String, dynamic> json) {
    final next = json['next_room'];
    final options = json['options'];
    return RoomInfo(
      status: RoomStatus.parse(json['status']),
      isLocked: json['is_locked'] == true,
      variant: json['variant']?.toString(),
      maxPlayers: (json['max_players'] as num?)?.toInt(),
      options: options is Map ? Map<String, Object?>.from(options) : const {},
      optionChoices: [
        for (final o in json['option_choices'] as List? ?? const [])
          if (o is Map) RoomOptionChoice.fromJson(Map<String, dynamic>.from(o)),
      ],
      hostId: json['host_id']?.toString(),
      startsIn: (json['starts_in'] as num?)?.toInt(),
      nextRoomCode: next is Map ? next['code']?.toString() : null,
      nextRoomId: next is Map ? next['room_id']?.toString() : null,
    );
  }

  final RoomStatus status;
  final bool isLocked;
  final String? variant;
  final int? maxPlayers;

  /// The rules chosen (every option, defaults included).
  final Map<String, Object?> options;
  final List<RoomOptionChoice> optionChoices;
  final String? hostId;

  /// Seconds left in the start countdown (status [RoomStatus.starting]).
  final int? startsIn;

  /// Where the rematch is played, once there is one.
  final String? nextRoomCode;
  final String? nextRoomId;
}

/// An invite to a room, by Player ID (`room_invite` on `user/<id>`).
class RoomInvite {
  const RoomInvite({
    required this.roomCode,
    required this.fromName,
    this.roomId,
    this.gameType = 'ludo',
    this.variant = 'classic',
    this.fromPlayerId,
  });

  factory RoomInvite.fromJson(Map<String, dynamic> json) {
    final from = json['from'];
    return RoomInvite(
      roomCode: json['room_code'].toString(),
      roomId: json['room_id']?.toString(),
      gameType: json['game_type']?.toString() ?? 'ludo',
      variant: json['variant']?.toString() ?? 'classic',
      fromName: from is Map ? from['name']?.toString() ?? '' : '',
      fromPlayerId: from is Map ? (from['player_id'] as num?)?.toInt() : null,
    );
  }

  final String roomCode;
  final String? roomId;
  final String gameType;
  final String variant;
  final String fromName;
  final int? fromPlayerId;
}

/// The answer to a rematch vote: the new room and your seat there, once
/// everyone agreed.
class RematchAnswer {
  const RematchAnswer({this.roomCode, this.roomId, this.seatId});

  factory RematchAnswer.fromJson(Map<String, dynamic> json) {
    final next = json['next_room'];
    return RematchAnswer(
      roomCode: next is Map ? next['code']?.toString() : null,
      roomId: next is Map ? next['room_id']?.toString() : null,
      seatId: json['seat_id']?.toString(),
    );
  }

  final String? roomCode;
  final String? roomId;
  final String? seatId;

  bool get started => roomCode != null && seatId != null;
}
