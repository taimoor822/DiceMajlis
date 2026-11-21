import 'package:flutter/material.dart';

import 'majlis_colors.dart';

/// How a die looks.
class DiceLook {
  const DiceLook({required this.face, required this.ink, required this.glow});

  final Color face;
  final Color ink;
  final Color glow;
}

/// The rim drawn around the board.
class BoardLook {
  const BoardLook({required this.rim, required this.trim});

  final List<Color> rim;
  final Color trim;
}

/// The ring drawn around an avatar.
class FrameLook {
  const FrameLook({required this.ring, required this.width});

  final List<Color> ring;
  final double width;
}

/// The look of each cosmetic, by the asset key the server sends (the server
/// decides which items exist and who owns them; the app only draws them). A key
/// this app doesn't know yet gets the plain look.
abstract final class CosmeticLooks {
  static DiceLook dice(String? asset, MajlisColors majlis) => switch (asset) {
    'dice_desert_gold' => const DiceLook(
      face: Color(0xFFE2B04A),
      ink: Color(0xFF1B2440),
      glow: Color(0xFFF3D58A),
    ),
    'dice_night_sky' => const DiceLook(
      face: Color(0xFF16204A),
      ink: Color(0xFFF2D27A),
      glow: Color(0xFF4F6BD8),
    ),
    'dice_pearl' => const DiceLook(
      face: Color(0xFFF4F1EA),
      ink: Color(0xFF137C7A),
      glow: Color(0xFF9FE3DA),
    ),
    'dice_ruby' => const DiceLook(
      face: Color(0xFFB3123A),
      ink: Color(0xFFFFF4F4),
      glow: Color(0xFFFF6F8E),
    ),
    // dice_ivory, and keys this app doesn't know: the theme's own die.
    _ => DiceLook(
      face: majlis.diceFace,
      ink: majlis.diceInk,
      glow: majlis.accent,
    ),
  };

  /// Null: the board as it is (board_majlis).
  static BoardLook? board(String? asset) => switch (asset) {
    'board_oasis' => const BoardLook(
      rim: [Color(0xFF0F5A4A), Color(0xFF1F8A6E), Color(0xFF0F5A4A)],
      trim: Color(0xFFE2C46A),
    ),
    'board_sandstone' => const BoardLook(
      rim: [Color(0xFF9A6A44), Color(0xFFE0B585), Color(0xFF9A6A44)],
      trim: Color(0xFF6B3F22),
    ),
    'board_midnight' => const BoardLook(
      rim: [Color(0xFF0B1230), Color(0xFF26346E), Color(0xFF0B1230)],
      trim: Color(0xFFD9B25A),
    ),
    _ => null,
  };

  /// Null: no frame.
  static FrameLook? frame(String? asset) => switch (asset) {
    'frame_brass' => const FrameLook(
      ring: [Color(0xFF7A5A2E), Color(0xFFF0D9A8), Color(0xFF7A5A2E)],
      width: 4,
    ),
    'frame_lantern' => const FrameLook(
      ring: [Color(0xFFFF8C1A), Color(0xFFFFE29A), Color(0xFFFFB347)],
      width: 4.5,
    ),
    'frame_palm' => const FrameLook(
      ring: [Color(0xFF1F8A4C), Color(0xFFD9B25A), Color(0xFF1F8A4C)],
      width: 5,
    ),
    'frame_falcon' => const FrameLook(
      ring: [
        Color(0xFF6B4A2B),
        Color(0xFFF2D27A),
        Color(0xFFFFFFFF),
        Color(0xFFF2D27A),
        Color(0xFF6B4A2B),
      ],
      width: 5.5,
    ),
    _ => null,
  };

  /// The colour that marks an item's rarity.
  static Color rarity(String rarity, MajlisColors majlis) => switch (rarity) {
    'rare' => const Color(0xFF4F9BD8),
    'epic' => const Color(0xFFA066E0),
    'legendary' => majlis.gold,
    _ => majlis.textMuted,
  };
}
