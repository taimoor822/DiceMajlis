// The game platform in the app: Game Hub from the server's catalog, rooms that
// know their game, and the board picked by game type.

import 'package:dice_majlis_app/core/auth/account.dart';
import 'package:dice_majlis_app/features/games/domain/game_catalog.dart';
import 'package:dice_majlis_app/features/games/presentation/game_route_screen.dart';
import 'package:dice_majlis_app/features/home/presentation/home_screen.dart';
import 'package:dice_majlis_app/features/ludo/presentation/game_board_screen.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_session.dart';
import 'package:dice_majlis_app/features/multiplayer/presentation/create_room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

Future<void> _openHub(
  WidgetTester tester, {
  FakeRoomRepository? repository,
  FakeGameCatalogRepository? catalog,
}) async {
  await tester.binding.setSurfaceSize(const Size(480, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    testApp(
      repository: repository ?? FakeRoomRepository(),
      sockets: FakeSockets(),
      catalog: catalog,
    ),
  );
  await tester.pump(const Duration(seconds: 2)); // splash
  await tester.pumpAndSettle();
  await tester.tap(find.text('Game Hub'));
  await tester.pumpAndSettle();
}

Future<void> _launchInRoom(WidgetTester tester, ActiveRoom room) async {
  await tester.pumpWidget(
    testApp(
      repository: FakeRoomRepository(),
      sockets: FakeSockets(),
      auth: FakeAuthApi(
        account: Account(
          playerId: 123456789,
          displayName: 'Guest 6789',
          activeRoom: room,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2)); // splash
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('rooms know their game', () {
    test('from the create/join answer, else Classic Ludo', () {
      final session = RoomSession.fromRoomResponse({
        'room': {
          'code': 'AB12',
          'game_type': 'ludo',
          'variant': 'classic',
          'max_players': 4,
        },
        'player': {'id': 'p1', 'name': 'A', 'color': 'red'},
      });
      expect((session.gameType, session.variant), ('ludo', 'classic'));
      final old = RoomSession.fromRoomResponse({
        'room': {'code': 'AB12'},
        'player': {'id': 'p1', 'name': 'A', 'color': 'red'},
      });
      expect((old.gameType, old.variant), ('ludo', 'classic'));
    });

    test('from the active room the server remembers', () {
      final room = ActiveRoom.fromJson({
        'code': 'AB12',
        'seat_id': 'p1',
        'game_type': 'domino',
        'variant': 'draw',
      });
      final session = RoomSession.fromActiveRoom(room);
      expect((session.gameType, session.variant), ('domino', 'draw'));
    });

    test('the catalog is read from the server JSON', () {
      final games = parseCatalog({
        'games': [
          {
            'game_type': 'ludo',
            'default_variant': 'classic',
            'variants': [
              {
                'code': 'classic',
                'min_players': 2,
                'max_players': 4,
                'default_players': 4,
                'ranked': true,
                'rules': {'tokens_per_player': 4},
              },
            ],
          },
        ],
      });
      final classic = games.single.variants.single;
      expect(games.single.gameType, 'ludo');
      expect(
        (classic.code, classic.minPlayers, classic.maxPlayers, classic.ranked),
        ('classic', 2, 4, true),
      );
    });
  });

  group('Game Hub', () {
    testWidgets('shows each online game the app can draw', (tester) async {
      await _openHub(tester);
      expect(find.text('Classic Ludo'), findsOneWidget);
      expect(find.text('CREATE ROOM'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing); // one variant: no picker
      expect(find.text('PLAY OFFLINE'), findsOneWidget);
      expect(find.textContaining('Update the app'), findsNothing);
    });

    testWidgets('picks a variant, and the room is created for it', (
      tester,
    ) async {
      final repo = FakeRoomRepository();
      const quick = CatalogVariant(
        code: 'quick',
        minPlayers: 2,
        maxPlayers: 4,
        defaultPlayers: 2,
      );
      await _openHub(
        tester,
        repository: repo,
        catalog: FakeGameCatalogRepository(
          games: [
            CatalogGame(
              gameType: 'ludo',
              defaultVariant: 'classic',
              variants: [
                FakeGameCatalogRepository.ludoClassic.variants.single,
                quick,
              ],
            ),
          ],
        ),
      );
      expect(find.widgetWithText(ChoiceChip, 'Classic'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'quick'));
      await tester.pumpAndSettle();
      expect(
        find.text('quick Ludo'),
        findsOneWidget,
      ); // a variant the app can't name yet

      await tester.tap(find.text('CREATE ROOM'));
      await tester.pumpAndSettle();
      expect(find.byType(CreateRoomScreen), findsOneWidget);
      expect(find.text('quick Ludo'), findsOneWidget);
      await tester.tap(find.text('CREATE'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['options:ludo/quick', 'create:4']);
      expect(repo.createdGame, const GameChoice(variant: 'quick'));
    });

    testWidgets('games the app is too old for ask for an update', (
      tester,
    ) async {
      await _openHub(
        tester,
        catalog: FakeGameCatalogRepository(
          games: [
            FakeGameCatalogRepository.ludoClassic,
            const CatalogGame(
              gameType: 'domino',
              defaultVariant: 'draw',
              variants: [
                CatalogVariant(
                  code: 'draw',
                  minPlayers: 2,
                  maxPlayers: 4,
                  defaultPlayers: 4,
                ),
              ],
            ),
          ],
        ),
      );
      expect(find.text('Classic Ludo'), findsOneWidget);
      expect(find.textContaining('Update the app'), findsOneWidget);
    });

    testWidgets('if the games fail to load, try again', (tester) async {
      final catalog = FakeGameCatalogRepository(failWith: 'network_error');
      await _openHub(tester, catalog: catalog);
      expect(find.text("Couldn't load the games"), findsOneWidget);
      expect(find.text('PLAY OFFLINE'), findsOneWidget); // offline still works

      catalog.failWith = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Classic Ludo'), findsOneWidget);
      expect(catalog.loads, 2);
    });
  });

  group('the board follows the game type', () {
    testWidgets('a Ludo room opens the Ludo board', (tester) async {
      await _launchInRoom(
        tester,
        const ActiveRoom(code: 'AB12', seatId: 'p-host', started: true),
      );
      expect(find.byType(GameBoardScreen), findsOneWidget);
    });

    testWidgets('a game this app can\'t draw says so and lets you leave', (
      tester,
    ) async {
      await _launchInRoom(
        tester,
        const ActiveRoom(
          code: 'DM01',
          seatId: 'p-host',
          started: true,
          gameType: 'domino',
          variant: 'draw',
        ),
      );
      expect(find.byType(UnsupportedGameScreen), findsOneWidget);
      expect(find.byType(GameBoardScreen), findsNothing);
      await tester.tap(find.text('LEAVE GAME'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });
}
