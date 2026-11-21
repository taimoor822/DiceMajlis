import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/majlis_colors.dart';
import '../../../../shared/widgets/board_skin_rim.dart';
import '../../domain/ludo_path.dart';
import 'board_widget.dart';
import 'player_token.dart';

/// One token to draw on the board.
@immutable
class BoardToken {
  const BoardToken({
    required this.color,
    required this.tokenIndex,
    required this.progress,
    this.label,
    this.movable = false,
    this.dimmed = false,
    this.flashing = false,
    this.onTap,
  });

  /// Seat colour name: 'red', 'blue', 'green' or 'yellow'.
  final String color;
  final int tokenIndex;

  /// -1 base, 0..50 track, 51..55 home column, 56 home.
  final int progress;
  final String? label;

  /// Glows and can be tapped.
  final bool movable;

  /// Drawn faded (e.g. tokens that can't move this turn).
  final bool dimmed;

  /// Glows for a moment (e.g. just captured).
  final bool flashing;
  final VoidCallback? onTap;
}

/// The board with its tokens, as big as the space it gets (square). Tokens
/// on the same cell spread out; a token glides one cell per [stepDuration].
class LudoBoardView extends StatelessWidget {
  const LudoBoardView({
    super.key,
    required this.tokens,
    this.stepDuration = const Duration(milliseconds: 140),
    this.boardSkin,
  });

  final List<BoardToken> tokens;
  final Duration stepDuration;

  /// The board skin's asset key (a cosmetic); null = the plain board.
  final String? boardSkin;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final tile = side / 15;
        final tokenSize = (tile * 0.9).clamp(16.0, 48.0);
        final spread = (tile * 0.22).clamp(2.0, tokenSize * 0.25);

        // Tokens on the same square spread out around its centre.
        final bySpot = <Offset, List<BoardToken>>{};
        for (final token in tokens) {
          final spot = LudoPath.pointFor(
            token.color,
            token.progress,
            token.tokenIndex,
          );
          (bySpot[spot] ??= []).add(token);
        }

        final children = <Widget>[];
        bySpot.forEach((spot, group) {
          final center = spot * tile;
          for (var i = 0; i < group.length; i++) {
            final token = group[i];
            children.add(
              AnimatedPlayerToken(
                key: ValueKey('token-${token.color}-${token.tokenIndex}'),
                center: center + _spread(i, group.length, spread),
                size: tokenSize,
                duration: stepDuration,
                child: PlayerToken(
                  color: MajlisColors.seatColor(token.color),
                  label: token.label ?? '${token.tokenIndex + 1}',
                  enabled: !token.dimmed,
                  flashing: token.movable || token.flashing,
                  onTap: token.movable ? token.onTap : null,
                ),
              ),
            );
          }
        });

        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                BoardSkinRim(skin: boardSkin),
                const Positioned.fill(child: BoardWidget()),
                ...children,
              ],
            ),
          ),
        );
      },
    );
  }

  static Offset _spread(int index, int count, double radius) {
    if (count <= 1) return Offset.zero;
    final angle = 2 * math.pi * index / count;
    return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }
}
