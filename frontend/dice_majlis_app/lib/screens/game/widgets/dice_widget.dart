import 'package:flutter/material.dart';
import '../../../widgets/glow_container.dart';

class DiceWidget extends StatefulWidget {
  final int? value; // dice value from backend
  final bool enabled; // can roll or not
  final VoidCallback? onTap; // trigger API roll

  const DiceWidget({super.key, this.value, this.enabled = true, this.onTap});

  @override
  State<DiceWidget> createState() => _DiceWidgetState();
}

class _DiceWidgetState extends State<DiceWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  bool isRolling = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scaleAnim = Tween<double>(
      begin: 1,
      end: 1.25,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  }

  void _handleTap() async {
    if (!widget.enabled || isRolling) return;

    setState(() => isRolling = true);

    _controller.forward(from: 0);

    // Call backend roll
    widget.onTap?.call();

    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      setState(() => isRolling = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = widget.value?.toString() ?? '🎲';

    return GestureDetector(
      onTap: _handleTap,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.4,
          child: GlowContainer(
            glowColor: const Color(0xFF00FF9C),
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 70,
              height: 70,
              child: Center(
                child: Text(
                  displayValue,
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF12172A),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
