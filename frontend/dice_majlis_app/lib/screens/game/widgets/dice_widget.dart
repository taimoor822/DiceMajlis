import 'dart:math';
import 'package:flutter/material.dart';
import '../../../widgets/glow_container.dart';

class DiceWidget extends StatefulWidget {
  const DiceWidget({super.key});

  @override
  State<DiceWidget> createState() => _DiceWidgetState();
}

class _DiceWidgetState extends State<DiceWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  int diceValue = 1;
  bool isRolling = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scaleAnim = Tween<double>(begin: 1, end: 1.25).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
  }

  void rollDice() async {
    if (isRolling) return;

    setState(() => isRolling = true);

    _controller.forward(from: 0);

    await Future.delayed(const Duration(milliseconds: 400));

    setState(() {
      diceValue = Random().nextInt(6) + 1;
    });

    await Future.delayed(const Duration(milliseconds: 300));

    setState(() => isRolling = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: rollDice,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: GlowContainer(
          glowColor: const Color(0xFF00FF9C),
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 70,
            height: 70,
            child: Center(
              child: Text(
                diceValue.toString(),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF12172A),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
