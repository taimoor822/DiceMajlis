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
    expect(session.isHost, isFalse);
    expect(session.maxPlayers, isNull);
    expect(session.self?.isBot, isFalse);
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
