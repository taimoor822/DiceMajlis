// Create / join / waiting-room flow with a fake server.

import 'package:dice_majlis_app/features/ludo/presentation/game_board_screen.dart';
import 'package:dice_majlis_app/features/multiplayer/presentation/waiting_room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

Future<void> openHome(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump(const Duration(seconds: 2)); // splash
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('host creates a room, sees players, starts the game', (
    tester,
  ) async {
    final repo = FakeRoomRepository();
    final sockets = FakeSockets();
    await openHome(tester, testApp(repository: repo, sockets: sockets));

    await tester.tap(find.text('CREATE ROOM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['create:2']);
    expect(find.byType(WaitingRoomScreen), findsOneWidget);
    expect(find.text('AB12'), findsOneWidget);
    expect(sockets.last.connectedRoom, 'AB12');
    // Two seats: me, plus one empty seat.
    expect(find.text('Waiting for a player…'), findsOneWidget);

    sockets.last.emit({
      'type': 'players_updated',
      'players': [
        {'id': 'p-host', 'name': 'Player 1', 'color': 'red', 'is_host': true},
        {'id': 'p2', 'name': 'Sara', 'color': 'blue', 'is_host': false},
      ],
    });
    await tester.pump();
    expect(find.text('Sara'), findsOneWidget);
    expect(find.text('Waiting for a player…'), findsNothing);

    await tester.tap(find.text('START GAME'));
    await tester.pump();
    expect(repo.calls.last, 'start:AB12');

    final lobby = sockets.last;
    lobby.emit({'type': 'game_started'});
    await tester.pumpAndSettle();
    expect(find.byType(GameBoardScreen), findsOneWidget);
    expect(lobby.disconnected, isTrue); // lobby socket closed
    expect(sockets.last.connectedRoom, 'AB12'); // board opened its own
  });

  testWidgets('a guest joins and waits for the host', (tester) async {
    final repo = FakeRoomRepository();
    final sockets = FakeSockets();
    await openHome(tester, testApp(repository: repo, sockets: sockets));

    await tester.tap(find.text('JOIN ROOM'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('JOIN'));
    await tester.pump();
    expect(find.text('Enter the room code you were given.'), findsOneWidget);
    expect(repo.calls, isEmpty);

    await tester.enterText(find.byType(TextFormField), ' zx9q ');
    await tester.tap(find.text('JOIN'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['join:ZX9Q']);
    expect(find.text('ZX9Q'), findsOneWidget);
    expect(find.text('START GAME'), findsNothing);
    expect(
      find.text('Waiting for the host to start the game…'),
      findsOneWidget,
    );
  });

  testWidgets('a failed create shows a message and stays put', (tester) async {
    final repo = FakeRoomRepository(fail: true);
    final sockets = FakeSockets();
    await openHome(tester, testApp(repository: repo, sockets: sockets));

    await tester.tap(find.text('CREATE ROOM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CREATE'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining("Couldn't create the room"), findsOneWidget);
    expect(find.byType(WaitingRoomScreen), findsNothing);
    expect(sockets.opened, isEmpty);
  });
}
