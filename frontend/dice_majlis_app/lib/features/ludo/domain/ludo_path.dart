import 'dart:math';
import 'dart:ui';

import 'engine/board.dart';

/// Board geometry. Must match the server engine (backend/core/ludo_engine/board.py).
///
/// A token's position is its *progress* from its own start square:
///   -1        in base
///   0..50     shared track (index into [getPath])
///   51..55    own home column
///   56        home ([homeProgress]) — drawn on the colour's centre cell
/// Seat order around the track is red, blue, green, yellow (13 squares apart).
class LudoPath {
  static const int _gridSize = 15;
  static const int _maxIndex = _gridSize - 1;

  static const int lastTrackProgress = LudoBoard.lastTrackProgress;
  static const int homeProgress = LudoBoard.homeProgress;

  static const List<Point<int>> redPath = <Point<int>>[
    Point<int>(6, 13),
    Point<int>(6, 12),
    Point<int>(6, 11),
    Point<int>(6, 10),
    Point<int>(6, 9),
    Point<int>(5, 8),
    Point<int>(4, 8),
    Point<int>(3, 8),
    Point<int>(2, 8),
    Point<int>(1, 8),
    Point<int>(0, 8),
    Point<int>(0, 7),
    Point<int>(0, 6),
    Point<int>(1, 6),
    Point<int>(2, 6),
    Point<int>(3, 6),
    Point<int>(4, 6),
    Point<int>(5, 6),
    Point<int>(6, 5),
    Point<int>(6, 4),
    Point<int>(6, 3),
    Point<int>(6, 2),
    Point<int>(6, 1),
    Point<int>(6, 0),
    Point<int>(7, 0),
    Point<int>(8, 0),
    Point<int>(8, 1),
    Point<int>(8, 2),
    Point<int>(8, 3),
    Point<int>(8, 4),
    Point<int>(8, 5),
    Point<int>(9, 6),
    Point<int>(10, 6),
    Point<int>(11, 6),
    Point<int>(12, 6),
    Point<int>(13, 6),
    Point<int>(14, 6),
    Point<int>(14, 7),
    Point<int>(14, 8),
    Point<int>(13, 8),
    Point<int>(12, 8),
    Point<int>(11, 8),
    Point<int>(10, 8),
    Point<int>(9, 8),
    Point<int>(8, 9),
    Point<int>(8, 10),
    Point<int>(8, 11),
    Point<int>(8, 12),
    Point<int>(8, 13),
    Point<int>(8, 14),
    Point<int>(7, 14), // 50: last track square, entrance to the home column
    Point<int>(7, 13), // 51..55: home column
    Point<int>(7, 12),
    Point<int>(7, 11),
    Point<int>(7, 10),
    Point<int>(7, 9),
    Point<int>(7, 8), // 56: home
  ];

  static final List<Point<int>> bluePath = _rotatePath(1);

  static final List<Point<int>> yellowPath = _rotatePath(3);

  static final List<Point<int>> greenPath = _rotatePath(2);

  static List<Point<int>> getPath(String color) {
    switch (color.trim().toLowerCase()) {
      case 'red':
        return redPath;
      case 'blue':
        return bluePath;
      case 'green':
        return greenPath;
      case 'yellow':
        return yellowPath;
      default:
        throw ArgumentError.value(color, 'color', 'Unsupported color');
    }
  }

  static List<Point<int>> _rotatePath(int quarterTurns) {
    return List<Point<int>>.unmodifiable(
      redPath.map((p) => _rotate(p, quarterTurns)),
    );
  }

  static Point<int> _rotate(Point<int> p, int quarterTurns) {
    final t = quarterTurns % 4;
    final turns = t < 0 ? t + 4 : t;
    switch (turns) {
      case 0:
        return p;
      case 1:
        return Point<int>(_maxIndex - p.y, p.x);
      case 2:
        return Point<int>(_maxIndex - p.x, _maxIndex - p.y);
      case 3:
        return Point<int>(p.y, _maxIndex - p.x);
      default:
        throw StateError('Invalid rotation');
    }
  }

  // Base circles in the board picture, in cells from its top-left corner
  // (measured from assets/board/majlis_board.svg): each base sits in a 6x6
  // corner with circles 1.94 and 4.11 cells in from the outer edges.
  static const double _baseNear = 1.94;
  static const double _baseFar = 4.11;

  /// Corner of each colour's base: (left?, top?).
  static const Map<String, (bool, bool)> _baseCorner = {
    'red': (true, false),
    'blue': (true, true),
    'green': (false, true),
    'yellow': (false, false),
  };

  /// Where token [tokenIndex] of [color] waits in its base, in cells from the
  /// board's top-left corner. Tokens 0–3 take the lower-left, lower-right,
  /// upper-left and upper-right circles.
  static Offset basePoint(String color, int tokenIndex) {
    final corner = _baseCorner[color.trim().toLowerCase()];
    if (corner == null) {
      throw ArgumentError.value(color, 'color', 'Unsupported color');
    }
    final (left, top) = corner;
    final xs = left
        ? const [_baseNear, _baseFar]
        : const [_gridSize - _baseFar, _gridSize - _baseNear];
    final ys = top
        ? const [_baseNear, _baseFar]
        : const [_gridSize - _baseFar, _gridSize - _baseNear];
    final i = tokenIndex % 4;
    return Offset(xs[i % 2], ys[i < 2 ? 1 : 0]);
  }

  /// Centre of a token of [color] at [progress] (-1 base .. 56 home), in
  /// cells from the board's top-left corner.
  static Offset pointFor(String color, int progress, int tokenIndex) {
    if (progress < 0) return basePoint(color, tokenIndex);
    final path = getPath(color);
    final cell = path[progress.clamp(0, path.length - 1)];
    return Offset(cell.x + 0.5, cell.y + 0.5);
  }

  static Offset gridToPixel({
    required int x,
    required int y,
    required double boardSize,
  }) {
    final tileSize = boardSize / _gridSize;
    return Offset((x + 0.5) * tileSize, (y + 0.5) * tileSize);
  }
}
