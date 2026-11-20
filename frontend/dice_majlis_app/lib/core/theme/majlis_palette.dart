import 'package:flutter/material.dart';

/// The raw Dice Majlis colours.
///
/// Widgets should not use these directly: read them through the theme
/// (`Theme.of(context).colorScheme` or `context.majlis`) so dark and light
/// modes stay consistent.
abstract final class MajlisPalette {
  // Deep night-majlis tones.
  static const navyDeep = Color(0xFF07151F);
  static const navy = Color(0xFF0B1F2E);
  static const navySurface = Color(0xFF112B3B);
  static const navyRaised = Color(0xFF173848);
  static const teal = Color(0xFF0E4D57);
  static const tealLight = Color(0xFF1B6670);

  // Accents.
  static const turquoise = Color(0xFF2EC4B6);
  static const emerald = Color(0xFF1F8A64);
  static const gold = Color(0xFFD4A84B);
  static const goldLight = Color(0xFFF0CF7E);
  static const goldDeep = Color(0xFFA67C2E);

  // Light, bright majlis tones.
  static const sand = Color(0xFFF4EBDD);
  static const sandDeep = Color(0xFFE8D9C1);
  static const ivory = Color(0xFFFFFBF4);
  static const ink = Color(0xFF1B2A33);
  static const inkMuted = Color(0xFF51626B);

  // Status.
  static const danger = Color(0xFFE0475F);
  static const warning = Color(0xFFF2A541);

  // Text and icons on top of strong colours.
  static const onGold = Color(0xFF1E1606);
  static const onSeat = Color(0xFFFFFFFF);
  static const shade = Color(0xFF000000);

  // Seat colours on the Ludo board (same in both themes).
  static const seatRed = Color(0xFFD9443B);
  static const seatBlue = Color(0xFF2F7FD1);
  static const seatGreen = Color(0xFF2E9E5B);
  static const seatYellow = Color(0xFFE6B422);

  // Item rarity (used by gifts, cosmetics, collections later).
  static const rarityCommon = Color(0xFF9AA5B1);
  static const rarityRare = Color(0xFF3BA7E0);
  static const rarityEpic = Color(0xFF9B5DE5);
  static const rarityLegendary = Color(0xFFE8B33C);
  static const rarityMythic = Color(0xFFE0475F);
}
