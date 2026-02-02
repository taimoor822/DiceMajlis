import 'package:flutter/material.dart';


class PlayerToken extends StatelessWidget {
  final Color color;
  final String label;

  const PlayerToken({
    super.key,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.8),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10, 
            color: Colors.white.withOpacity(0.7),
            ),
        ),
      ],
    );
  }
}
