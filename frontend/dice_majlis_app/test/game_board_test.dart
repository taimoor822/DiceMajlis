// The board never guesses the rules: only tokens the server lists can move.

import 'package:dice_majlis_app/app.dart';
import 'package:dice_majlis_app/core/routing/app_router.dart';
import 'package:dice_majlis_app/core/routing/app_routes.dart';
import 'package:dice_majlis_app/core/storage/session_storage.dart';
import 'package:dice_majlis_app/features/home/presentation/home_screen.dart';
import 'package:dice_majlis_app/features/ludo/presentation/game_board_screen.dart';
import 'package:dice_majlis_app/features/ludo/presentation/widgets/player_token.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_session.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_session_controller.dart';
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

/// Opens /game/AB12 with a host session already in place.
Future<FakeSockets> openBoard(WidgetTester tester) async {
  SessionStorage.clear();
  final sockets = FakeSockets();
  final container = ProviderContainer(
    overrides: fakeNetwork(repository: FakeRoomRepository(), sockets: sockets),
  );
  addTearDown(container.dispose);
  container
      .read(roomSessionProvider.notifier)
      .start(
        const RoomSession(
          roomCode: 'AB12',
          playerId: me,
          playerToken: 'secret-host',
          isHost: true,
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
}
