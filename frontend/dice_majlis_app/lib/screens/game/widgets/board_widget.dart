import 'package:flutter/material.dart';
import '../../../widgets/glow_container.dart';

class BoardWidget extends StatelessWidget {
  const BoardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return GlowContainer(
      glowColor: const Color(0xFF9D4EDD),
      padding: const EdgeInsets.all(12),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          children: [
            // GRID BACKGROUND
            Positioned.fill(
              child: CustomPaint(
                painter: _GridPainter(),
              ),
            ),

            // CENTER HOME
            Center(
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFF1B1F3B),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xFF9D4EDD),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'HOME',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),

            // LANES
            _lane(Alignment.topCenter, Colors.blue),
            _lane(Alignment.bottomCenter, Colors.red),
            _lane(Alignment.centerLeft, Colors.green),
            _lane(Alignment.centerRight, Colors.orange),
          ],
        ),
      ),
    );
  }

  Widget _lane(Alignment alignment, Color color) {
    return Align(
      alignment: alignment,
      child: Container(
        width: alignment == Alignment.topCenter || alignment == Alignment.bottomCenter ? 60 : 16,
        height: alignment == Alignment.centerLeft || alignment == Alignment.centerRight ? 60 : 16,
        decoration: BoxDecoration(
          color: color.withOpacity(0.8),
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: 10,
            ),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1;

    const divisions = 7;
    final step = size.width / divisions;

    for (int i = 1; i < divisions; i++) {
      final offset = step * i;
      canvas.drawLine(Offset(offset, 0), Offset(offset, size.height), paint);
      canvas.drawLine(Offset(0, offset), Offset(size.width, offset), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
