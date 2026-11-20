import 'package:flutter/material.dart';

import '../../core/theme/majlis_colors.dart';

/// The built-in avatar pictures, by the key the server stores. The server
/// decides which keys exist (`GET /api/profile/options/`); a key this app
/// doesn't know yet shows a plain person.
const avatarIcons = <String, IconData>{
  'dice': Icons.casino,
  'trophy': Icons.emoji_events,
  'star': Icons.star_rounded,
  'moon': Icons.nightlight_round,
  'sun': Icons.wb_sunny,
  'coffee': Icons.coffee,
  'dhow': Icons.sailing,
  'tree': Icons.park,
  'diamond': Icons.diamond,
  'rocket': Icons.rocket_launch,
  'music': Icons.music_note,
  'football': Icons.sports_soccer,
  'paw': Icons.pets,
  'flower': Icons.local_florist,
  'bolt': Icons.bolt,
  'gamepad': Icons.sports_esports,
};

/// A player's avatar: a built-in picture on its own colour.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.avatar,
    this.radius = 24,
    this.selected = false,
  });

  final String? avatar;
  final double radius;

  /// Draws a gold ring (avatar pickers).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final majlis = context.majlis;
    final keys = avatarIcons.keys.toList();
    final index = keys.indexOf(avatar ?? '');
    final circle = CircleAvatar(
      radius: radius,
      backgroundColor: index < 0
          ? majlis.glassBorder
          : MajlisColors.avatarBackground(index),
      child: Icon(
        avatarIcons[avatar] ?? Icons.person,
        size: radius,
        color: index < 0 ? majlis.gold : majlis.onSeat,
      ),
    );
    if (!selected) return circle;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: majlis.gold, width: 3),
      ),
      child: Padding(padding: const EdgeInsets.all(2), child: circle),
    );
  }
}
