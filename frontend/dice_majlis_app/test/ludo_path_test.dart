// Checks the app's board geometry matches the server engine
// (backend/core/ludo_engine/board.py): same track, same seat offsets,
// same home column and home cell. If these drift apart, tokens are drawn
// on different squares than the server thinks they are on.

import 'dart:math';

import 'package:dice_majlis_app/game/ludo_path.dart';
import 'package:flutter_test/flutter_test.dart';

const _seats = ['red', 'blue', 'green', 'yellow'];
const _trackLength = 52;
const _seatSpacing = 13;

/// The one track square red never visits (just behind its own start).
const _squareRedSkips = Point<int>(6, 14);

Point<int> _trackSquare(int square) => square <= LudoPath.lastTrackProgress
    ? LudoPath.redPath[square]
    : _squareRedSkips;

void main() {
  test('every path runs from start (0) to home (56)', () {
    for (final color in _seats) {
      expect(
        LudoPath.getPath(color).length,
        LudoPath.homeProgress + 1,
        reason: color,
      );
    }
  });

  test('red goes straight from the last track square into its home column', () {
    final red = LudoPath.redPath;
    expect(red[50], const Point<int>(7, 14));
    expect(red.sublist(51, 56), const [
      Point<int>(7, 13),
      Point<int>(7, 12),
      Point<int>(7, 11),
      Point<int>(7, 10),
      Point<int>(7, 9),
    ]);
    expect(red[56], const Point<int>(7, 8));
    expect(red.contains(_squareRedSkips), isFalse);
  });

  test('progress maps to the same shared square as the server engine', () {
    for (var seat = 0; seat < _seats.length; seat++) {
      final path = LudoPath.getPath(_seats[seat]);
      for (
        var progress = 0;
        progress <= LudoPath.lastTrackProgress;
        progress++
      ) {
        final square = (progress + seat * _seatSpacing) % _trackLength;
        expect(
          path[progress],
          _trackSquare(square),
          reason: '${_seats[seat]} progress $progress = square $square',
        );
      }
    }
  });

  test('home columns and home cells are private to each colour', () {
    final privateCells = <Point<int>>{};
    for (final color in _seats) {
      privateCells.addAll(LudoPath.getPath(color).sublist(51));
    }
    expect(privateCells.length, 4 * 6);
    for (final color in _seats) {
      final home = LudoPath.getPath(color)[LudoPath.homeProgress];
      expect(home.x, inInclusiveRange(6, 8), reason: color);
      expect(home.y, inInclusiveRange(6, 8), reason: color);
    }
  });
}
