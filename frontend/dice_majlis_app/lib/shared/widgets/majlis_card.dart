import 'package:flutter/material.dart';

import '../../core/theme/majlis_colors.dart';

/// Glass panel with a fine gold edge, used to group content on screens.
class MajlisCard extends StatelessWidget {
  const MajlisCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final majlis = context.majlis;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: majlis.glassFill,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: majlis.glassBorder),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
