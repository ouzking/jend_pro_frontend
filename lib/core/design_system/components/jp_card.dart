import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../tokens/jp_metrics.dart';

/// Carte de base : surface, bordure fine, rayon généreux, ombre légère
/// optionnelle. Cliquable si [onTap] est fourni.
class JpCard extends StatelessWidget {
  const JpCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(JpSpacing.lg),
    this.elevated = false,
    this.color,
    this.borderColor,
    this.radius = JpRadius.lg,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool elevated;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final borderRadius = JpRadius.all(radius);
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = InkWell(onTap: onTap, borderRadius: borderRadius, child: content);
    }
    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: elevated ? JpShadows.md(p.shadow) : JpShadows.sm(p.shadow),
        ),
        child: Material(
          color: color ?? p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(color: borderColor ?? p.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: content,
        ),
      ),
    );
  }
}
