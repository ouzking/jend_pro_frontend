import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../tokens/jp_metrics.dart';
import '../tokens/jp_palette.dart';
import '../tokens/jp_typography.dart';

/// Pastille de statut : « Stock faible », « Payé », « À crédit »…
class JpBadge extends StatelessWidget {
  const JpBadge({super.key, required this.label, this.tone = JpTone.neutral, this.icon, this.dot = false});

  final String label;
  final JpTone tone;
  final IconData? icon;

  /// Affiche un point coloré avant le libellé (statuts « vivants »).
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette.tone(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: JpSpacing.sm, vertical: JpSpacing.xs),
      decoration: BoxDecoration(color: colors.background, borderRadius: JpRadius.all(JpRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: colors.foreground, shape: BoxShape.circle),
            ),
            const SizedBox(width: JpSpacing.xs + 2),
          ] else if (icon != null) ...[
            Icon(icon, size: 14, color: colors.foreground),
            const SizedBox(width: JpSpacing.xs),
          ],
          Text(
            label,
            style: JpTypography.caption.copyWith(color: colors.foreground, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
