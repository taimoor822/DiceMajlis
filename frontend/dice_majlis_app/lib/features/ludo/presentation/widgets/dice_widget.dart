import 'package:flutter/material.dart';

import '../../../../core/theme/majlis_colors.dart';
import '../../../../shared/widgets/glow_container.dart';

class DiceWidget extends StatefulWidget {
  final int? value; // dice value from backend
  final bool enabled; // can roll or not
  final VoidCallback? onTap; // trigger API roll
  final bool rolling;

  const DiceWidget({
    super.key,
    this.value,
    this.enabled = true,
    this.onTap,
    this.rolling = false,
  });

  @override
  State<DiceWidget> createState() => _DiceWidgetState();
}

class _DiceWidgetState extends State<DiceWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

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
    if (!widget.enabled || widget.rolling) return;
    // A short bounce: grow, then settle back to the normal size.
    _controller.forward(from: 0).then((_) {
      if (mounted) _controller.reverse();
    });
    widget.onTap?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = widget.value?.toString() ?? '?';
    final isInteractive = widget.enabled && !widget.rolling;
    final majlis = context.majlis;

    return GestureDetector(
      onTap: isInteractive ? _handleTap : null,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Opacity(
          opacity: isInteractive ? 1 : 0.4,
          child: GlowContainer(
            glowColor: majlis.accent,
            color: majlis.diceFace,
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 70,
              height: 70,
              child: Center(
                child: widget.rolling && widget.value == null
                    ? SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: majlis.diceInk,
                        ),
                      )
                    : Text(
                        displayValue,
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: majlis.diceInk,
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
