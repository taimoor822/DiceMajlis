// The Dart engine must give exactly the answers the server's Python engine
// gave for every shared test vector (shared/ludo/engine_vectors.json, written
// by backend/core/ludo_engine/vectors.py). Same vectors = same rules.
import 'dart:convert';
import 'dart:io';

import 'package:dice_majlis_app/features/ludo/domain/engine/ludo_engine.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Json = Map<String, Object?>;

/// Tests run from the app folder; the vectors live at the repo root.
final File _vectorsFile = File('../../shared/ludo/engine_vectors.json');

/// JSON with sorted keys, so two values compare (and print) the same way.
String canon(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) k: _sorted(value[k])};
  }
  if (value is Iterable) return [for (final v in value) _sorted(v)];
  return value;
}

GameState _start(Json game) {
  final setup = game['setup'] as Json?;
  if (setup == null) return GameState.fromJson(game['initial']! as Json);
  return LudoEngine.newGame(
    setup['game_id']! as String,
    List<String>.from(setup['player_ids']! as List),
    seats: setup['seats'] == null
        ? null
        : List<int>.from(setup['seats']! as List),
    rules: Rules.fromJson(setup['rules']! as Json),
    firstPlayerId: setup['first_player_id'] as String?,
  );
}

Matcher _engineError(String code) =>
    throwsA(isA<EngineError>().having((e) => e.code, 'code', code));

void main() {
  final vectors = jsonDecode(_vectorsFile.readAsStringSync()) as Json;

  test('vectors use the format this test reads', () {
    expect(vectors['format'], 1);
  });

  group('board', () {
    final board = vectors['board']! as Json;

    test('numbers match the server', () {
      expect(LudoBoard.trackLength, board['track_length']);
      expect(LudoBoard.seatCount, board['seat_count']);
      expect(LudoBoard.seatSpacing, board['seat_spacing']);
      expect(LudoBoard.baseProgress, board['base_progress']);
      expect(LudoBoard.startProgress, board['start_progress']);
      expect(LudoBoard.lastTrackProgress, board['last_track_progress']);
      expect(
        LudoBoard.firstHomeColumnProgress,
        board['first_home_column_progress'],
      );
      expect(LudoBoard.homeProgress, board['home_progress']);
      expect(LudoBoard.seatColors, board['seat_colors']);
      expect(
        LudoBoard.defaultSafeSquares().toList()..sort(),
        board['default_safe_squares'],
      );
      final seats = board['default_seats']! as Json;
      for (final count in [2, 3, 4]) {
        expect(LudoBoard.defaultSeatsFor(count), seats['$count']);
      }
    });

    test('every seat and progress lands on the same square', () {
      final table = board['absolute_square']! as List;
      for (var seat = 0; seat < LudoBoard.seatCount; seat++) {
        final row = table[seat] as List;
        for (var p = LudoBoard.baseProgress; p <= LudoBoard.homeProgress; p++) {
          expect(
            LudoBoard.absoluteSquare(seat, p),
            row[p + 1],
            reason: 'seat $seat progress $p',
          );
        }
      }
    });
  });

  test('default rules match the server', () {
    expect(canon(Rules.standard.toJson()), canon(vectors['default_rules']));
  });

  group('new game', () {
    for (final raw in vectors['setups']! as List) {
      final c = raw as Json;
      test(c['name']! as String, () {
        GameState create() => LudoEngine.newGame(
          c['game_id']! as String,
          List<String>.from(c['player_ids']! as List),
          seats: c['seats'] == null
              ? null
              : List<int>.from(c['seats']! as List),
          rules: c['rules'] == null
              ? null
              : Rules.fromJson(c['rules']! as Json),
          firstPlayerId: c['first_player_id'] as String?,
        );
        if (c.containsKey('error')) {
          expect(create, _engineError(c['error']! as String));
        } else {
          expect(canon(create().toJson()), canon(c['state']));
        }
      });
    }
  });

  group('stored states', () {
    for (final raw in vectors['snapshots']! as List) {
      final c = raw as Json;
      test(c['name']! as String, () {
        GameState load() => GameState.fromJson(c['json']! as Json);
        if (c.containsKey('error')) {
          expect(load, _engineError(c['error']! as String));
        } else {
          expect(canon(load().toJson()), canon(c['state']));
        }
      });
    }
  });

  group('games', () {
    for (final raw in vectors['games']! as List) {
      final game = raw as Json;
      test(game['name']! as String, () {
        var state = _start(game);
        expect(canon(state.toJson()), canon(game['initial']));

        final steps = game['steps']! as List;
        for (var i = 0; i < steps.length; i++) {
          final step = steps[i] as Json;
          final where = '${game['name']} step $i: ${canon(step['action'])}';
          final action = step['action']! as Json;

          if (step.containsKey('error')) {
            expect(
              () => LudoEngine.applyAction(state, action),
              _engineError(step['error']! as String),
              reason: where,
            );
            continue;
          }
          if (step.containsKey('bot')) {
            expect(
              LudoBot.chooseMove(state).tokenIndex,
              step['bot'],
              reason: '$where (bot choice)',
            );
          }

          final transition = LudoEngine.applyAction(state, action);
          expect(
            canon([
              for (final e in transition.events) [e.type.wire, e.data],
            ]),
            canon(step['events']),
            reason: where,
          );
          expect(
            transition.events.every((e) => e.version == state.version + 1),
            isTrue,
            reason: '$where (event versions)',
          );
          state = transition.state;

          if (step.containsKey('state')) {
            expect(canon(state.toJson()), canon(step['state']), reason: where);
            expect(GameState.fromJson(state.toJson()), state, reason: where);
          }
        }

        expect(canon(state.toJson()), canon(game['final']));
        expect(state.isFinished, isTrue);
      });
    }
  });

  group('dice', () {
    test('secure dice only roll 1 to 6', () {
      final dice = SecureDice();
      final seen = {for (var i = 0; i < 600; i++) dice.roll()};
      expect(seen.difference({1, 2, 3, 4, 5, 6}), isEmpty);
    });

    test('scripted dice play back their values, then stop', () {
      final dice = ScriptedDice([6, 1]);
      expect([dice.roll(), dice.roll()], [6, 1]);
      expect(dice.remaining, 0);
      expect(dice.roll, throwsStateError);
      expect(() => ScriptedDice([7]), throwsArgumentError);
    });
  });
}
