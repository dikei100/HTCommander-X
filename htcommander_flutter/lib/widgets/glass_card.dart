import 'dart:ui';

import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0x991E243E), // rgba(30,36,62,0.6) per Stitch
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colors.outlineVariant.withAlpha(38), // 15% ghost border
                width: 0.5,
              ),
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}
