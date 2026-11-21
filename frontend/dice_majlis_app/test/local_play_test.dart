// Offline games on this phone (vs AI, pass-and-play) on the Dart engine.

import 'package:dice_majlis_app/core/l10n/generated/app_localizations.dart';
import 'package:dice_majlis_app/core/network/api_exception.dart';
import 'package:dice_majlis_app/features/auth/presentation/welcome_screen.dart';
import 'package:dice_majlis_app/features/local_play/domain/local_game_controller.dart';
import 'package:dice_majlis_app/features/local_play/domain/local_game_setup.dart';
import 'package:dice_majlis_app/features/local_play/domain/local_play_providers.dart';
import 'package:dice_majlis_app/features/local_play/presentation/local_game_screen.dart';
import 'package:dice_majlis_app/features/local_play/presentation/local_names.dart';
import 'package:dice_majlis_app/features/local_play/presentation/local_setup_screen.dart';
import 'package:dice_majlis_app/features/ludo/domain/engine/ludo_engine.dart';
import 'package:dice_majlis_app/features/splash/presentation/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

LocalGameController _game(
  Map<int, LocalSeatKind> kinds, {
  DiceRoller? dice,
  bool playOn = false,
}) => LocalGameController(
  setup: LocalGameSetup(kinds: kinds, playOn: playOn),
  dice: dice ?? SecureDice(),
  timing: LocalPlayTiming.instant,
);

const _human = LocalSeatKind.human;
const _ai = LocalSeatKind.ai;

Future<void> _launch(
  WidgetTester tester, {
  DiceRoller? dice,
  FakeAuthApi? auth,
  MemoryTokenStore? tokens,
}) async {
  await tester.binding.setSurfaceSize(const Size(480, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    testApp(
      repository: FakeRoomRepository(),
      sockets: FakeSockets(),
      auth: auth,
      tokens: tokens,
      overrides: [
        localPlayTimingProvider.overrideWithValue(LocalPlayTiming.instant),
        if (dice != null) localDiceProvider.overrideWithValue(dice),
      ],
    ),
  );
  await tester.pump(const Duration(seconds: 2)); // splash
  await tester.pumpAndSettle();
}

/// Lets an offline game catch up (the board's picture keeps a spinner going
/// in tests, so no pumpAndSettle once it is on screen).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(seconds: 1));
}

String _status(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('local-status'))).data!;

void main() {
  group('setup', () {
    test('two players sit opposite: you against the AI', () {
      final setup = LocalGameSetup.standard();
      expect(setup.seats, [0, 2]);
      expect(setup.kinds, {0: _human, 2: _ai});
      expect(setup.rules.endWhenFirstPlayerFinishes, isTrue);
      expect(setup.rules.tokensPerPlayer, Rules.standard.tokensPerPlayer);
    });

    test('changing the player count keeps the people already chosen', () {
      final setup = LocalGameSetup.standard().withKind(2, _human);
      final four = setup.withPlayerCount(4);
      expect(four.kinds, {0: _human, 1: _ai, 2: _human, 3: _ai});
      expect(four.withPlayerCount(2).kinds, {0: _human, 2: _human});
      expect(four.withPlayOn(true).rules.endWhenFirstPlayerFinishes, isFalse);
    });

    test('names: "You" alone, else numbered; the AI likewise', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final solo = LocalGameSetup.forPlayers(3);
      expect(localPlayerName(l10n, solo, 0), 'You');
      expect(localPlayerName(l10n, solo, 1), 'Majlis AI 1');
      expect(localPlayerName(l10n, solo, 2), 'Majlis AI 2');
      final table = LocalGameSetup(kinds: {0: _human, 1: _human, 2: _ai});
      expect(localPlayerName(l10n, table, 0), 'Player 1');
      expect(localPlayerName(l10n, table, 1), 'Player 2');
      expect(localPlayerName(l10n, table, 2), 'Majlis AI');
    });
  });

  group('controller', () {
    test('you roll and move; the AI plays its turn by itself', () async {
      // You: 6 (enter), 3 (walk). AI: 2 (nothing can leave base).
      final game = _game({0: _human, 2: _ai}, dice: ScriptedDice([6, 3, 2]));
      await game.start();
      expect(game.canRoll, isTrue);

      await game.roll();
      expect(game.diceValue, 6);
      expect(game.movableTokens, {0, 1, 2, 3});
      expect(game.canRoll, isFalse);

      await game.moveToken(0);
      expect(game.shownProgress(0, 0), 0);
      expect(game.canRoll, isTrue, reason: 'a six gives another turn');
      expect(game.diceValue, isNull);

      await game.roll();
      expect(game.movableTokens, {0});
      await game.moveToken(0);
      expect(game.shownProgress(0, 0), 3);

      // The AI rolled 2, couldn't move, and it's your turn again.
      expect(game.state.currentPlayer.seat, 0);
      expect(game.notice?.kind, LocalNoticeKind.noMoves);
      expect(game.notice?.playerIndex, 1);
      expect(game.state.version, 5);
      expect(game.canRoll, isTrue);
    });

    test('pass-and-play: the next person takes the phone', () async {
      final game = _game({0: _human, 2: _human}, dice: ScriptedDice([4]));
      await game.start();
      await game.roll(); // a 4 can't leave base
      expect(game.state.currentPlayer.seat, 2);
      expect(game.isHumanTurn, isTrue);
      expect(game.canRoll, isTrue);
    });

    test('actions out of turn are ignored', () async {
      final game = _game({0: _human, 2: _ai}, dice: ScriptedDice([6]));
      await game.start();
      await game.moveToken(0); // not rolled yet
      expect(game.state.version, 0);
      await game.roll();
      await game.roll(); // a move is due
      await game.moveToken(5); // no such token
      expect(game.state.version, 1);
    });

    test('AI-only games always finish with a full ranking', () async {
      for (final playOn in [false, true]) {
        for (final count in [2, 3, 4]) {
          final setup = LocalGameSetup.forPlayers(count, playOn: playOn);
          final game = LocalGameController(
            setup: LocalGameSetup(
              kinds: {for (final s in setup.seats) s: _ai},
              playOn: playOn,
            ),
            dice: SecureDice(),
            timing: LocalPlayTiming.instant,
          );
          await game.start();
          expect(game.state.isFinished, isTrue);
          expect(game.busy, isFalse);
          final places = [for (final row in game.standings) row['place']];
          expect(places, List.generate(count, (i) => i + 1));
          // What is drawn is where the engine says the tokens are.
          for (var p = 0; p < count; p++) {
            for (var t = 0; t < 4; t++) {
              expect(game.shownProgress(p, t), game.state.players[p].tokens[t]);
            }
          }
          game.dispose();
        }
      }
    });

    test('closing the game stops the AI', () async {
      final game = LocalGameController(
        setup: LocalGameSetup(kinds: {0: _ai, 2: _ai}),
        dice: SecureDice(),
        timing: const LocalPlayTiming(
          aiThink: Duration(milliseconds: 5),
          showDice: Duration(milliseconds: 5),
          step: Duration(milliseconds: 1),
          capture: Duration(milliseconds: 1),
        ),
      );
      final running = game.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final version = game.state.version;
      game.dispose();
      await running;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(game.state.version, lessThanOrEqualTo(version + 1));
    });
  });

  group('screens', () {
    testWidgets('Game Hub → pick players → pass-and-play with the AI', (
      tester,
    ) async {
      // Player 1: 6 then 5; Player 2: 3 (stuck); Majlis AI: 1 (stuck).
      await _launch(tester, dice: ScriptedDice([6, 5, 3, 1]));
      await tester.tap(find.text('Game Hub'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PLAY OFFLINE'));
      await tester.pumpAndSettle();
      expect(find.byType(LocalSetupScreen), findsOneWidget);
      expect(find.textContaining("don't earn Gold"), findsOneWidget);

      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('local-seat-1')),
          matching: find.text('Player'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Player 2'), findsOneWidget);

      await tester.tap(find.text('START GAME'));
      await _settle(tester);
      expect(find.byType(LocalGameScreen), findsOneWidget);
      expect(_status(tester), 'Player 1: roll the dice');

      await tester.tap(find.byKey(const ValueKey('local-dice')));
      await _settle(tester);
      expect(_status(tester), 'Player 1: pick a token');

      await tester.tap(find.byKey(const ValueKey('token-red-0')));
      await _settle(tester);
      expect(_status(tester), 'Player 1: roll the dice'); // six: again

      await tester.tap(find.byKey(const ValueKey('local-dice')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('token-red-0')));
      await _settle(tester);
      expect(_status(tester), 'Player 2: roll the dice');

      await tester.tap(find.byKey(const ValueKey('local-dice')));
      await _settle(tester);
      // Player 2 and the AI can't leave base; back to Player 1.
      expect(_status(tester), 'Player 1: roll the dice');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('local-notice'))).data,
        "Majlis AI can't move",
      );

      await tester.tap(find.byTooltip('Leave game'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Leave this game?'), findsOneWidget);
      await tester.tap(find.text('Leave'));
      await _settle(tester);
      expect(find.byType(LocalGameScreen), findsNothing);
      expect(find.byType(LocalSetupScreen), findsOneWidget);
    });

    testWidgets('a finished game shows the places; play again or done', (
      tester,
    ) async {
      await _launch(tester);
      await tester.tap(find.text('Game Hub'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PLAY OFFLINE'));
      await tester.pumpAndSettle();
      // AI against AI: the game plays itself to the end.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('local-seat-0')),
          matching: find.text('AI'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('START GAME'));
      await _settle(tester);
      expect(find.text('Game over'), findsOneWidget);
      expect(find.textContaining('wins!'), findsWidgets);

      await tester.tap(find.text('Play again'));
      await _settle(tester);
      expect(find.text('Game over'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await _settle(tester);
      expect(find.byType(LocalGameScreen), findsNothing);
      expect(find.byType(LocalSetupScreen), findsOneWidget);
    });

    testWidgets('no server: play offline from the splash screen', (
      tester,
    ) async {
      await _launch(
        tester,
        auth: FakeAuthApi(failWith: ApiException.networkError),
      );
      expect(find.byType(SplashScreen), findsOneWidget);
      await tester.tap(find.text('PLAY OFFLINE'));
      await tester.pumpAndSettle();
      expect(find.byType(LocalSetupScreen), findsOneWidget);
    });

    testWidgets('signed out: play offline from Welcome', (tester) async {
      await _launch(tester, tokens: MemoryTokenStore());
      expect(find.byType(WelcomeScreen), findsOneWidget);
      await tester.tap(find.text('Play offline on this phone'));
      await tester.pumpAndSettle();
      expect(find.byType(LocalSetupScreen), findsOneWidget);
    });
  });
}
