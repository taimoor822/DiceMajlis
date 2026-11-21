// The board never guesses the rules: only tokens the server lists can move.

import 'package:dice_majlis_app/app.dart';
import 'package:dice_majlis_app/core/auth/auth_controller.dart';
import 'package:dice_majlis_app/core/realtime/realtime_providers.dart';
import 'package:dice_majlis_app/core/routing/app_router.dart';
import 'package:dice_majlis_app/core/routing/app_routes.dart';
import 'package:dice_majlis_app/features/home/presentation/home_screen.dart';
import 'package:dice_majlis_app/features/ludo/presentation/game_board_screen.dart';
import 'package:dice_majlis_app/features/ludo/presentation/widgets/dice_widget.dart';
import 'package:dice_majlis_app/features/ludo/presentation/widgets/player_token.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_session.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_session_controller.dart';
import 'package:dice_majlis_app/features/multiplayer/presentation/waiting_room_screen.dart';
import 'package:dice_majlis_app/features/profile/domain/xp_gain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

const me = 'p-host';
const bot = 'p-bot';
const myTokens = ['t1', 't2', 't3', 't4'];

Map<String, dynamic> snapshot({
  int? lastDice,
  List<String> movable = const [],
  String? winner,
}) => {
  'type': 'game_started',
  'room_code': 'AB12',
  'players': [
    {'id': me, 'name': 'Player 1', 'color': 'red', 'is_host': true},
    {'id': bot, 'name': 'Majlis AI', 'color': 'green', 'is_bot': true},
  ],
  'tokens': [
    for (final id in myTokens)
      {'id': id, 'player_id': me, 'position': -1, 'is_finished': false},
    for (final id in ['b1', 'b2', 'b3', 'b4'])
      {'id': id, 'player_id': bot, 'position': -1, 'is_finished': false},
  ],
  'current_turn_player_id': me,
  'last_dice': lastDice,
  'movable_token_ids': movable,
  'seconds_left': 30,
  'warning_seconds': 10,
  'winner_id': winner,
};

/// Opens /game/AB12, signed in, with a host session already in place.
Future<FakeSockets> openBoard(
  WidgetTester tester, {
  FakeRoomRepository? repository,
}) async {
  final sockets = FakeSockets();
  final container = ProviderContainer(
    overrides: [
      ...fakeNetwork(
        repository: repository ?? FakeRoomRepository(),
        sockets: sockets,
      ),
      // No /ws/v1/ connection here: this container outlives the widget tree,
      // so the connection's ping timer would still be running when the test
      // ends. The board still uses the lobby socket until 1.12.
      realtimeClientProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  await container.read(authControllerProvider.notifier).restore();
  container
      .read(roomSessionProvider.notifier)
      .start(
        const RoomSession(
          roomCode: 'AB12',
          playerId: me,
          isHost: true,
          isStarted: true,
        ),
      );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const DiceMajlisApp(),
    ),
  );
  container.read(appRouterProvider).go(AppRoutes.game('AB12'));
  // Not pumpAndSettle: the board image's loading spinner never settles in tests.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  expect(find.byType(GameBoardScreen), findsOneWidget);
  return sockets;
}

List<bool> myTokenStates(WidgetTester tester) => tester
    .widgetList<PlayerToken>(find.byType(PlayerToken))
    .where((t) => t.label.isNotEmpty)
    .map((t) => t.onTap != null)
    .toList();

void main() {
  testWidgets('a roll alone enables nothing; the server list decides', (
    tester,
  ) async {
    final sockets = await openBoard(tester);

    // A six is showing, but the server has not listed any movable token.
    sockets.last.emit(snapshot(lastDice: 6));
    await tester.pump();
    expect(myTokenStates(tester).where((tappable) => tappable), isEmpty);

    // The server says exactly one token may move.
    sockets.last.emit({
      'type': 'dice_rolled',
      'player_id': me,
      'dice': 6,
      'movable_token_ids': ['t3'],
    });
    await tester.pump();
    expect(myTokenStates(tester).where((tappable) => tappable), hasLength(1));
    expect(find.text('6'), findsOneWidget); // the dice shows the roll
  });

  testWidgets('reconnecting mid-turn restores the movable tokens', (
    tester,
  ) async {
    final sockets = await openBoard(tester);
    sockets.last.emit(snapshot(lastDice: 6, movable: ['t1', 't2']));
    await tester.pump();
    expect(myTokenStates(tester).where((tappable) => tappable), hasLength(2));
  });

  testWidgets('reconnecting after the end shows the result, once', (
    tester,
  ) async {
    final sockets = await openBoard(tester);
    sockets.last.emit(snapshot(winner: me));
    await tester.pump();
    sockets.last.emit({'type': 'game_finished', 'winner_id': me});
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('You win!'), findsOneWidget);
    await tester.tap(find.text('Back to home'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('the result shows the XP the server gave, and level ups', (
    tester,
  ) async {
    final sockets = await openBoard(tester);
    final players = [
      {'id': me, 'name': 'Player 1', 'color': 'red', 'is_host': true},
      {'id': 'p-sara', 'name': 'Sara', 'color': 'green'},
    ];
    sockets.last.emit({...snapshot(), 'players': players});
    await tester.pump();
    // The XP arrives just before the end of the game.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GameBoardScreen)),
    );
    container
        .read(xpGainsProvider.notifier)
        .add(
          'AB12',
          XpGain.fromJson({
            'amount': 50,
            'reason': 'game',
            'room_code': 'AB12',
            'level_up': true,
            'level': 2,
            'xp': 120,
            'level_xp': 100,
            'next_level_xp': 300,
          })!,
        );
    sockets.last.emit({'type': 'game_finished', 'winner_id': me});
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('+50 XP'), findsOneWidget);
    expect(find.text("Level up! You're now level 2"), findsOneWidget);
    expect(find.text("Games with the AI don't give XP."), findsNothing);
  });

  testWidgets('a game with the AI says it gives no XP', (tester) async {
    final sockets = await openBoard(tester);
    sockets.last.emit(snapshot());
    await tester.pump();
    sockets.last.emit({'type': 'game_finished', 'winner_id': me});
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('You win!'), findsOneWidget);
    expect(find.text("Games with the AI don't give XP."), findsOneWidget);
    expect(find.byKey(const Key('game-over-xp')), findsNothing);
  });

  testWidgets('a player drops: the seat stays, shown as away until back', (
    tester,
  ) async {
    final sockets = await openBoard(tester);
    final players = [
      {'id': me, 'name': 'Player 1', 'color': 'red', 'is_host': true},
      {'id': 'p-sara', 'name': 'Sara', 'color': 'green'},
    ];
    sockets.last.emit({...snapshot(), 'players': players});
    await tester.pump();
    expect(find.textContaining('Away'), findsNothing);

    sockets.last.emit({'type': 'player_disconnected', 'player_id': 'p-sara'});
    await tester.pump();
    expect(find.text('Sara • Away'), findsOneWidget);
    expect(
      find.text('Sara lost connection. Their seat is kept.'),
      findsOneWidget,
    );

    sockets.last.emit({'type': 'player_reconnected', 'player_id': 'p-sara'});
    await tester.pump();
    expect(find.text('Sara'), findsOneWidget);
    expect(find.text('Sara is back.'), findsOneWidget);
  });

  testWidgets('after the game: play again, then the rematch room opens', (
    tester,
  ) async {
    final repo = FakeRoomRepository();
    final sockets = await openBoard(tester, repository: repo);
    sockets.last.emit(snapshot());
    await tester.pump();
    sockets.last.emit({'type': 'game_finished', 'winner_id': bot});
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('You lost'), findsOneWidget);
    await tester.tap(find.text('Play again'));
    await tester.pump();
    expect(repo.calls.last, 'rematch:AB12:true');
    expect(find.text('Waiting for the others to say yes…'), findsOneWidget);
    expect(find.text('Play again'), findsNothing);

    sockets.last.emit({
      'type': 'rematch_started',
      'room_code': 'CD34',
      'room_id': 'room-2',
      'seats': {me: 'new-seat', bot: 'new-bot'},
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(WaitingRoomScreen), findsOneWidget);
    expect(find.text('CD34'), findsOneWidget);
    expect(sockets.last.connectedRoom, 'CD34');
    expect(sockets.last.connectedRoomId, 'room-2');
  });

  testWidgets('leaving asks first, then forfeits on the server', (
    tester,
  ) async {
    final repo = FakeRoomRepository();
    final sockets = await openBoard(tester, repository: repo);
    sockets.last.emit(snapshot());
    await tester.pump();

    await tester.tap(find.byTooltip('Leave game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Leave this game?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.calls, isEmpty);
    expect(find.byType(GameBoardScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Leave game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Leave'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(repo.calls, ['leave:AB12']);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('rolling asks the server; the app never sends who it is', (
    tester,
  ) async {
    final repo = FakeRoomRepository();
    final sockets = await openBoard(tester, repository: repo);
    sockets.last.emit(snapshot());
    await tester.pump();

    await tester.tap(find.byType(DiceWidget));
    await tester.pump();
    expect(repo.calls, ['roll:AB12']);
  });
}
