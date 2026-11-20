// Create / join / waiting-room flow with a fake server.

import 'package:dice_majlis_app/features/ludo/presentation/game_board_screen.dart';
import 'package:dice_majlis_app/features/multiplayer/data/room_repository.dart';
import 'package:dice_majlis_app/features/multiplayer/presentation/waiting_room_screen.dart';
import 'package:dice_majlis_app/shared/widgets/majlis_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

/// Starts the app and opens the Game Hub tab, where the room flow lives.
Future<void> openHub(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump(const Duration(seconds: 2)); // splash
  await tester.pumpAndSettle();
  await tester.tap(find.text('Game Hub'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('host creates a room, sees players, starts the game', (
    tester,
  ) async {
    final repo = FakeRoomRepository();
    final sockets = FakeSockets();
    await openHub(tester, testApp(repository: repo, sockets: sockets));

    await tester.tap(find.text('CREATE ROOM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['options', 'create:2']);
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
    await openHub(tester, testApp(repository: repo, sockets: sockets));

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

  testWidgets('a failed create says why and stays put', (tester) async {
    final repo = FakeRoomRepository();
    final sockets = FakeSockets();
    await openHub(tester, testApp(repository: repo, sockets: sockets));

    await tester.tap(find.text('CREATE ROOM'));
    await tester.pumpAndSettle();
    repo.failWith = 'network_error';
    await tester.tap(find.text('CREATE'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining("Can't reach the server"), findsOneWidget);
    expect(find.byType(WaitingRoomScreen), findsNothing);
    expect(sockets.opened, isEmpty);
  });

  testWidgets('room sizes come from the server', (tester) async {
    final repo = FakeRoomRepository(
      options: const RoomOptions(playerCounts: [2, 3], defaultPlayerCount: 3),
    );
    await openHub(tester, testApp(repository: repo, sockets: FakeSockets()));

    await tester.tap(find.text('CREATE ROOM'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, '2'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '3'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '4'), findsNothing);
    final picked = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '3'),
    );
    expect(picked.selected, isTrue); // the server's default

    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['options', 'create:3']);
  });

  testWidgets('if the room sizes fail to load, the player can retry', (
    tester,
  ) async {
    final repo = FakeRoomRepository(failWith: 'network_error');
    await openHub(tester, testApp(repository: repo, sockets: FakeSockets()));

    await tester.tap(find.text('CREATE ROOM'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load the room options."), findsOneWidget);
    final createButton = tester.widget<MajlisButton>(find.byType(MajlisButton));
    expect(createButton.onPressed, isNull);

    repo.failWith = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '4'), findsOneWidget);
  });

  testWidgets('joining a full room says so', (tester) async {
    final repo = FakeRoomRepository(failWith: 'room_full');
    await openHub(tester, testApp(repository: repo, sockets: FakeSockets()));

    await tester.tap(find.text('JOIN ROOM'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'AB12');
    await tester.tap(find.text('JOIN'));
    await tester.pump();
    await tester.pump();

    expect(find.text('That room is full.'), findsOneWidget);
    expect(find.byType(WaitingRoomScreen), findsNothing);
  });

  testWidgets('leaving the waiting room gives the seat back', (tester) async {
    final repo = FakeRoomRepository();
    final sockets = FakeSockets();
    await openHub(tester, testApp(repository: repo, sockets: sockets));

    await tester.tap(find.text('CREATE ROOM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();
    expect(find.byType(WaitingRoomScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Leave room'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'leave:AB12');
    expect(find.byType(WaitingRoomScreen), findsNothing);
    expect(find.text('Game Hub'), findsWidgets);
    expect(sockets.last.disconnected, isTrue);
  });

  testWidgets('if leaving fails, the player stays in the room', (tester) async {
    final repo = FakeRoomRepository();
    await openHub(tester, testApp(repository: repo, sockets: FakeSockets()));
    await tester.tap(find.text('CREATE ROOM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();

    repo.failWith = 'network_error';
    await tester.tap(find.byTooltip('Leave room'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining("Can't reach the server"), findsOneWidget);
    expect(find.byType(WaitingRoomScreen), findsOneWidget);
  });

  testWidgets('joining a game you are already in opens the board', (
    tester,
  ) async {
    final repo = FakeRoomRepository(joinStarted: true);
    await openHub(tester, testApp(repository: repo, sockets: FakeSockets()));

    await tester.tap(find.text('JOIN ROOM'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'AB12');
    await tester.tap(find.text('JOIN'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(GameBoardScreen), findsOneWidget);
  });
}
