import 'package:flutter/material.dart';

import '../../core/theme/majlis_colors.dart';

enum MajlisButtonStyle { primary, secondary }

/// The main Dice Majlis button: gold gradient (primary) or outlined
/// (secondary), 56 px tall for easy tapping, with a loading state.
class MajlisButton extends StatelessWidget {
  const MajlisButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = MajlisButtonStyle.primary,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final MajlisButtonStyle style;
  final bool loading;
  final bool expand;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final majlis = context.majlis;
    final scheme = Theme.of(context).colorScheme;
    final primary = style == MajlisButtonStyle.primary;
    final foreground = primary
        ? majlis.onGold
        : (Theme.of(context).brightness == Brightness.dark
              ? majlis.goldLight
              : scheme.primary);
    final radius = BorderRadius.circular(18);

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: foreground,
            ),
          )
        else if (icon != null)
          Icon(icon, color: foreground, size: 22),
        if (loading || icon != null) const SizedBox(width: 10),
        Flexible(
          child: Text(
            label.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: foreground,
              fontSize: 16,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: onPressed == null ? 0.45 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: primary ? majlis.goldGradient : null,
            color: primary ? null : majlis.glassFill,
            border: primary
                ? null
                : Border.all(
                    color: majlis.gold.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
            boxShadow: primary && _enabled
                ? [
                    BoxShadow(
                      color: majlis.gold.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: _enabled ? onPressed : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
