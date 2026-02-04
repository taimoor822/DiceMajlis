import 'dart:async';
import 'dart:math' as math;
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
  Timer? _rollingTimer;
  Timer? _timeoutTimer;
  int? _rollingFace;
  final math.Random _rand = math.Random();

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

    // UI-only animation; final dice value must come from backend (WS event).
    _startRollingAnimation();

    // Call backend roll
    widget.onTap?.call();
  }

  void _startRollingAnimation() {
    _rollingTimer?.cancel();
    _timeoutTimer?.cancel();

    _rollingTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!mounted) return;
      setState(() {
        _rollingFace = _rand.nextInt(6) + 1;
      });
    });

    // Safety timeout in case WS response is delayed or missing.
    _timeoutTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      _stopRolling();
    });
  }

  void _stopRolling() {
    _rollingTimer?.cancel();
    _rollingTimer = null;

    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    if (!mounted) return;
    setState(() {
      isRolling = false;
      _rollingFace = null;
    });
  }

  @override
  void didUpdateWidget(covariant DiceWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Stop local animation as soon as the server value arrives.
    if (isRolling && oldWidget.value == null && widget.value != null) {
      _stopRolling();
    }
  }

  @override
  void dispose() {
    _rollingTimer?.cancel();
    _timeoutTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = widget.value?.toString() ?? (isRolling ? (_rollingFace?.toString() ?? '🎲') : '🎲');

    return GestureDetector(
      onTap: (widget.enabled && !isRolling) ? _handleTap : null,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Opacity(
          opacity: (widget.enabled && !isRolling) ? 1 : 0.4,
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
