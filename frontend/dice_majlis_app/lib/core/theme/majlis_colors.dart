import 'package:flutter/material.dart';

import 'majlis_palette.dart';

/// Dice Majlis colours that Material's ColorScheme has no slot for
/// (gold gradient, background gradient, geometric pattern, seats, rarity).
///
/// Read it with `context.majlis`.
@immutable
class MajlisColors extends ThemeExtension<MajlisColors> {
  const MajlisColors({
    required this.gold,
    required this.goldLight,
    required this.goldDeep,
    required this.accent,
    required this.success,
    required this.danger,
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.pattern,
    required this.glassFill,
    required this.glassBorder,
    required this.textMuted,
    required this.warning,
    required this.onGold,
    required this.onSeat,
    required this.scrim,
    required this.diceFace,
    required this.diceInk,
  });

  final Color gold;
  final Color goldLight;
  final Color goldDeep;
  final Color accent;
  final Color success;
  final Color danger;
  final Color backgroundTop;
  final Color backgroundBottom;
  final Color pattern;
  final Color glassFill;
  final Color glassBorder;
  final Color textMuted;

  /// "Hurry up" state, e.g. the last seconds of a turn.
  final Color warning;

  /// Text and icons on gold surfaces (primary buttons).
  final Color onGold;

  /// Text, icons and highlights on seat-coloured surfaces (tokens, avatars).
  final Color onSeat;

  /// Base for dimming overlays and shadows; apply the alpha where it is used.
  final Color scrim;

  /// The dice: its face and the number on it.
  final Color diceFace;
  final Color diceInk;

  static const dark = MajlisColors(
    gold: MajlisPalette.gold,
    goldLight: MajlisPalette.goldLight,
    goldDeep: MajlisPalette.goldDeep,
    accent: MajlisPalette.turquoise,
    success: MajlisPalette.emerald,
    danger: MajlisPalette.danger,
    backgroundTop: MajlisPalette.navy,
    backgroundBottom: MajlisPalette.navyDeep,
    pattern: Color(0x14D4A84B), // gold at ~8%
    glassFill: Color(0xCC112B3B),
    glassBorder: Color(0x33D4A84B),
    textMuted: Color(0xFFB4C3C7),
    warning: MajlisPalette.warning,
    onGold: MajlisPalette.onGold,
    onSeat: MajlisPalette.onSeat,
    scrim: MajlisPalette.shade,
    diceFace: MajlisPalette.ivory,
    diceInk: MajlisPalette.ink,
  );

  static const light = MajlisColors(
    gold: MajlisPalette.goldDeep,
    goldLight: MajlisPalette.gold,
    goldDeep: Color(0xFF7E5B1C),
    accent: MajlisPalette.teal,
    success: MajlisPalette.emerald,
    danger: MajlisPalette.danger,
    backgroundTop: MajlisPalette.ivory,
    backgroundBottom: MajlisPalette.sand,
    pattern: Color(0x1A0E4D57), // teal at ~10%
    glassFill: Color(0xE6FFFBF4),
    glassBorder: Color(0x400E4D57),
    textMuted: MajlisPalette.inkMuted,
    warning: Color(0xFFC77A12),
    onGold: MajlisPalette.onGold,
    onSeat: MajlisPalette.onSeat,
    scrim: MajlisPalette.shade,
    diceFace: MajlisPalette.ivory,
    diceInk: MajlisPalette.ink,
  );

  /// Gold gradient for primary buttons, titles and highlights.
  LinearGradient get goldGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [goldLight, gold, goldDeep],
  );

  LinearGradient get backgroundGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundTop, backgroundBottom],
  );

  /// Board colour for a server seat colour name ('red', 'blue', ...).
  static Color seatColor(String? name) {
    switch ((name ?? '').toLowerCase()) {
      case 'red':
        return MajlisPalette.seatRed;
      case 'blue':
        return MajlisPalette.seatBlue;
      case 'green':
        return MajlisPalette.seatGreen;
      case 'yellow':
      case 'orange':
      case 'amber':
        return MajlisPalette.seatYellow;
      default:
        return MajlisPalette.rarityCommon;
    }
  }

  @override
  MajlisColors copyWith({
    Color? gold,
    Color? goldLight,
    Color? goldDeep,
    Color? accent,
    Color? success,
    Color? danger,
    Color? backgroundTop,
    Color? backgroundBottom,
    Color? pattern,
    Color? glassFill,
    Color? glassBorder,
    Color? textMuted,
    Color? warning,
    Color? onGold,
    Color? onSeat,
    Color? scrim,
    Color? diceFace,
    Color? diceInk,
  }) {
    return MajlisColors(
      gold: gold ?? this.gold,
      goldLight: goldLight ?? this.goldLight,
      goldDeep: goldDeep ?? this.goldDeep,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      backgroundTop: backgroundTop ?? this.backgroundTop,
      backgroundBottom: backgroundBottom ?? this.backgroundBottom,
      pattern: pattern ?? this.pattern,
      glassFill: glassFill ?? this.glassFill,
      glassBorder: glassBorder ?? this.glassBorder,
      textMuted: textMuted ?? this.textMuted,
      warning: warning ?? this.warning,
      onGold: onGold ?? this.onGold,
      onSeat: onSeat ?? this.onSeat,
      scrim: scrim ?? this.scrim,
      diceFace: diceFace ?? this.diceFace,
      diceInk: diceInk ?? this.diceInk,
    );
  }

  @override
  MajlisColors lerp(ThemeExtension<MajlisColors>? other, double t) {
    if (other is! MajlisColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return MajlisColors(
      gold: mix(gold, other.gold),
      goldLight: mix(goldLight, other.goldLight),
      goldDeep: mix(goldDeep, other.goldDeep),
      accent: mix(accent, other.accent),
      success: mix(success, other.success),
      danger: mix(danger, other.danger),
      backgroundTop: mix(backgroundTop, other.backgroundTop),
      backgroundBottom: mix(backgroundBottom, other.backgroundBottom),
      pattern: mix(pattern, other.pattern),
      glassFill: mix(glassFill, other.glassFill),
      glassBorder: mix(glassBorder, other.glassBorder),
      textMuted: mix(textMuted, other.textMuted),
      warning: mix(warning, other.warning),
      onGold: mix(onGold, other.onGold),
      onSeat: mix(onSeat, other.onSeat),
      scrim: mix(scrim, other.scrim),
      diceFace: mix(diceFace, other.diceFace),
      diceInk: mix(diceInk, other.diceInk),
    );
  }
}

extension MajlisThemeContext on BuildContext {
  /// Dice Majlis extra colours for the current theme.
  MajlisColors get majlis =>
      Theme.of(this).extension<MajlisColors>() ?? MajlisColors.dark;
}
