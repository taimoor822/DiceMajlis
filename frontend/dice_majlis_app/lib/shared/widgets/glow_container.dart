import 'package:flutter/material.dart';

import '../../core/theme/majlis_colors.dart';

/// A rounded box with a soft coloured glow. Colours default to the theme.
class GlowContainer extends StatelessWidget {
  final Widget child;
  final Color? glowColor;
  final Color? color;
  final double borderRadius;
  final EdgeInsets padding;

  const GlowContainer({
    super.key,
    required this.child,
    this.glowColor,
    this.color,
    this.borderRadius = 16,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final majlis = context.majlis;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? majlis.glassFill,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: (glowColor ?? majlis.accent).withValues(alpha: 0.4),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }
}
