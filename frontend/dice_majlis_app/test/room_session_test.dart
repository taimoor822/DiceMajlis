import 'package:dice_majlis_app/core/auth/account.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the create/join room response', () {
    final session = RoomSession.fromRoomResponse({
      'room': {'id': 7, 'code': 'AB12', 'max_players': 3, 'is_started': false},
      'player': {
        'id': '7d1c2b54-0000-4000-8000-000000000001',
        'name': 'Player 1',
        'color': 'red',
        'is_host': true,
        'is_bot': false,
      },
    });

    expect(session.roomCode, 'AB12');
    expect(session.roomId, '7');
    expect(session.isStarted, isFalse);
    expect(session.playerId, '7d1c2b54-0000-4000-8000-000000000001');
    expect(session.isHost, isTrue);
    expect(session.maxPlayers, 3);
    expect(session.self?.name, 'Player 1');
    expect(session.self?.color, 'red');
  });

  test('a guest is not host; missing fields get safe defaults', () {
    final session = RoomSession.fromRoomResponse({
      'room': {'code': 'AB12'},
      'player': {'id': 42, 'name': 'Player', 'color': 'blue'},
    });

    expect(session.playerId, '42');
    expect(session.roomId, isNull);
    expect(session.isHost, isFalse);
    expect(session.maxPlayers, isNull);
    expect(session.self?.isBot, isFalse);
  });

  test('rejoining a started game says so', () {
    final session = RoomSession.fromRoomResponse({
      'room': {'code': 'AB12', 'is_started': true},
      'player': {'id': 'p1', 'name': 'P', 'color': 'red'},
    });
    expect(session.isStarted, isTrue);
  });

  test('the room the account is in, from the server (app start)', () {
    final session = RoomSession.fromActiveRoom(
      const ActiveRoom(
        code: 'AB12',
        seatId: 'seat-1',
        roomId: 'room-uuid',
        isHost: true,
        maxPlayers: 3,
        started: true,
      ),
    );
    expect(session.roomCode, 'AB12');
    expect(session.playerId, 'seat-1');
    expect(session.roomId, 'room-uuid');
    expect(session.isHost, isTrue);
    expect(session.maxPlayers, 3);
    expect(session.isStarted, isTrue);
    expect(session.self, isNull);
  });

  test('players from the lobby socket (snake_case keys)', () {
    final bot = RoomPlayer.fromJson({
      'id': 'b1',
      'name': 'Majlis AI',
      'color': 'green',
      'is_host': false,
      'is_bot': true,
    });

    expect(bot.isBot, isTrue);
    expect(bot.toJson()['is_bot'], isTrue);
    expect(
      bot,
      const RoomPlayer(
        id: 'b1',
        name: 'Majlis AI',
        color: 'green',
        isBot: true,
      ),
    );
  });
}
