import 'package:flutter/material.dart';

class PlayerToken extends StatelessWidget {
  final Color color;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  const PlayerToken({
    super.key,
    required this.color,
    required this.label,
    this.enabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: CircleAvatar(
          radius: 20,
          backgroundColor: color,
          child: Text(label, style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}
