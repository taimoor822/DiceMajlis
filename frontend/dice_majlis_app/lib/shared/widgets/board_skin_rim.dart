import 'package:flutter/material.dart';

import '../../core/theme/cosmetic_looks.dart';

/// The board skin: a rim drawn just outside the board, behind it. Put it first
/// in the board's `Stack` (with `clipBehavior: Clip.none`); the board and its
/// tokens keep their exact size and places. Draws nothing for the plain board.
class BoardSkinRim extends StatelessWidget {
  const BoardSkinRim({super.key, required this.skin, this.width = 7});

  /// The board skin's asset key (a cosmetic).
  final String? skin;
  final double width;

  @override
  Widget build(BuildContext context) {
    final look = CosmeticLooks.board(skin);
    if (look == null) return const SizedBox.shrink();
    return Positioned(
      key: const Key('board-skin-rim'),
      left: -width,
      top: -width,
      right: -width,
      bottom: -width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 1.6),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: look.rim,
          ),
          border: Border.all(color: look.trim, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: look.rim[look.rim.length ~/ 2].withValues(alpha: 0.5),
              blurRadius: width * 2,
            ),
          ],
        ),
      ),
    );
  }
}
