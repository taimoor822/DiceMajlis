import 'package:flutter/material.dart';

import '../../core/theme/cosmetic_looks.dart';
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

/// A player's avatar: a built-in picture on its own colour, inside the profile
/// frame they wear (if any).
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.avatar,
    this.radius = 24,
    this.selected = false,
    this.frame,
  });

  final String? avatar;
  final double radius;

  /// The frame's asset key (a cosmetic), or null for none.
  final String? frame;

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
    final look = CosmeticLooks.frame(frame);
    if (look != null) {
      return DecoratedBox(
        key: const Key('avatar-frame'),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(colors: look.ring),
          boxShadow: [
            BoxShadow(
              color: look.ring[look.ring.length ~/ 2].withValues(alpha: 0.45),
              blurRadius: look.width * 2,
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(look.width),
          // A thin dark gap keeps the ring apart from any avatar colour.
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: majlis.backgroundBottom, width: 2),
            ),
            child: Padding(padding: const EdgeInsets.all(2), child: circle),
          ),
        ),
      );
    }
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
