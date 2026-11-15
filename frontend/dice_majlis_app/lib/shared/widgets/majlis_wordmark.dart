import 'package:flutter/material.dart';

import '../../core/theme/majlis_colors.dart';

/// "Dice Majlis" title in the gold gradient, with an optional tagline.
class MajlisWordmark extends StatelessWidget {
  const MajlisWordmark({
    super.key,
    required this.title,
    this.tagline,
    this.size = 40,
  });

  final String title;
  final String? tagline;
  final double size;

  @override
  Widget build(BuildContext context) {
    final majlis = context.majlis;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DieEmblem(size: size * 1.6),
        SizedBox(height: size * 0.35),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => majlis.goldGradient.createShader(bounds),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineLarge?.copyWith(
              fontSize: size,
              height: 1.1,
              letterSpacing: 1,
            ),
          ),
        ),
        if (tagline != null) ...[
          const SizedBox(height: 10),
          Text(
            tagline!,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              color: majlis.textMuted,
              letterSpacing: 2,
            ),
          ),
        ],
      ],
    );
  }
}

/// A die face set inside an eight-pointed star — drawn in code, original.
class _DieEmblem extends StatelessWidget {
  const _DieEmblem({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final majlis = context.majlis;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final angle in [0.0, 0.785398])
            Transform.rotate(
              angle: angle,
              child: Container(
                width: size * 0.72,
                height: size * 0.72,
                decoration: BoxDecoration(
                  gradient: majlis.goldGradient,
                  borderRadius: BorderRadius.circular(size * 0.12),
                  boxShadow: [
                    BoxShadow(
                      color: majlis.gold.withValues(alpha: 0.3),
                      blurRadius: size * 0.25,
                    ),
                  ],
                ),
              ),
            ),
          Container(
            width: size * 0.5,
            height: size * 0.5,
            decoration: BoxDecoration(
              color: majlis.backgroundTop,
              borderRadius: BorderRadius.circular(size * 0.1),
            ),
            child: CustomPaint(painter: _PipsPainter(color: majlis.goldLight)),
          ),
        ],
      ),
    );
  }
}

class _PipsPainter extends CustomPainter {
  _PipsPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final r = size.width * 0.085;
    const spots = [
      Offset(0.27, 0.27),
      Offset(0.73, 0.27),
      Offset(0.5, 0.5),
      Offset(0.27, 0.73),
      Offset(0.73, 0.73),
    ];
    for (final s in spots) {
      canvas.drawCircle(
        Offset(s.dx * size.width, s.dy * size.height),
        r,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PipsPainter old) => old.color != color;
}
