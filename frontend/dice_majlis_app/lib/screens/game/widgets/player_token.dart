import 'dart:math' as math;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final borderWidth = (side * 0.08).clamp(1.0, 2.5);
        final fontSize = (side * 0.42).clamp(10.0, 18.0);
        final glow = (side * 0.3).clamp(6.0, 14.0);

        return GestureDetector(
          onTap: enabled ? onTap : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: enabled ? 1.0 : 0.4,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.all(side * 0.05),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: flashing ? Colors.white : Colors.transparent,
                  width: borderWidth,
                ),
                boxShadow: flashing
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.7),
                          blurRadius: glow,
                          spreadRadius: 1,
                        ),
                      ]
                    : const [],
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: fontSize,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class AnimatedPlayerToken extends StatelessWidget {
  final Offset center;
  final double size;
  final Duration duration;
  final Curve curve;
  final Widget child;

  const AnimatedPlayerToken({
    super.key,
    required this.center,
    required this.size,
    required this.duration,
    this.curve = Curves.easeInOut,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: duration,
      curve: curve,
      left: center.dx - (size / 2),
      top: center.dy - (size / 2),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}
