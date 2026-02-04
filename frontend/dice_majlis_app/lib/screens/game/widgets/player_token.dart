import 'package:flutter/material.dart';

class PlayerToken extends StatelessWidget {
  final Color color;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;
  final bool flashing;

  const PlayerToken({
    super.key,
    required this.color,
    required this.label,
    this.enabled = false,
    this.onTap,
    this.flashing = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1.0 : 0.4,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: flashing ? Colors.white : Colors.transparent,
              width: 2,
            ),
            boxShadow: flashing
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.7),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          child: CircleAvatar(
            radius: 20,
            backgroundColor: color,
            child: Text(label, style: const TextStyle(color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
