import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/majlis_colors.dart';

/// Full-screen Majlis backdrop: a soft gradient with a faint lattice of
/// eight-pointed stars (an original geometric pattern drawn in code).
class MajlisBackground extends StatelessWidget {
  const MajlisBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.majlis;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: colors.backgroundGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: StarLatticePainter(color: colors.pattern),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Eight-pointed stars on a square grid, joined by thin diagonals.
class StarLatticePainter extends CustomPainter {
  StarLatticePainter({required this.color, this.cell = 64});

  final Color color;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final radius = cell * 0.28;
    for (double y = 0; y <= size.height + cell; y += cell) {
      for (double x = 0; x <= size.width + cell; x += cell) {
        final center = Offset(x, y);
        canvas.drawPath(_star(center, radius), stroke);
        // Diagonal links to the neighbouring stars make the lattice.
        canvas.drawLine(
          center + Offset(radius * 0.7, radius * 0.7),
          center + Offset(cell - radius * 0.7, cell - radius * 0.7),
          stroke,
        );
        canvas.drawLine(
          center + Offset(-radius * 0.7, radius * 0.7),
          center + Offset(-cell + radius * 0.7, cell - radius * 0.7),
          stroke,
        );
      }
    }
  }

  /// Two overlapping squares, one turned 45°.
  Path _star(Offset c, double r) {
    final path = Path();
    for (final turn in [0.0, math.pi / 4]) {
      for (var i = 0; i < 4; i++) {
        final a = turn + i * math.pi / 2 + math.pi / 4;
        final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
    }
    return path;
  }

  @override
  bool shouldRepaint(StarLatticePainter old) =>
      old.color != color || old.cell != cell;
}
