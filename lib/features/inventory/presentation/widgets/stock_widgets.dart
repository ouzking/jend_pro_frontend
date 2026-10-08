import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/formatting/formatters.dart';
import '../../../products/presentation/widgets/product_visuals.dart';
import '../../domain/inventory_models.dart';

/// Ligne de l'onglet Stock : quantité en grand + jauge par rapport au seuil.
class StockRowTile extends StatelessWidget {
  const StockRowTile({super.key, required this.row, this.showLocation = false, this.onTap});

  final StockRow row;
  final bool showLocation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (tone, label) = row.isOut
        ? (JpTone.danger, 'Rupture')
        : row.isLow
        ? (JpTone.warning, 'Stock faible')
        : (JpTone.success, 'OK');
    final colors = p.tone(tone);
    // Jauge : plein à 2 × le seuil (ou plein si aucun seuil n'est défini).
    final ratio = row.isOut
        ? 0.0
        : row.minLevel <= 0
        ? 1.0
        : (row.quantity / (row.minLevel * 2)).clamp(0.04, 1.0).toDouble();

    return Semantics(
      button: onTap != null,
      label: '${row.productName}, ${Formatters.quantity(row.quantity)} ${row.unit}, $label',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.md),
          child: Row(
            children: [
              ProductThumb(name: row.productName, imagePath: row.imagePath, size: 44),
              const SizedBox(width: JpSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: JpTypography.bodyStrong.copyWith(color: p.textPrimary, fontSize: 15),
                    ),
                    const SizedBox(height: JpSpacing.xs + 2),
                    ClipRRect(
                      borderRadius: JpRadius.all(JpRadius.pill),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 5,
                        backgroundColor: p.surfaceMuted,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(height: JpSpacing.xs),
                    Text(
                      [
                        if (showLocation && row.locationName != null) row.locationName!,
                        if (row.minLevel > 0) 'Seuil ${Formatters.quantity(row.minLevel)}',
                        if (row.minLevel <= 0) 'Aucun seuil',
                      ].join(' · '),
                      style: JpTypography.caption.copyWith(color: p.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: JpSpacing.lg),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.quantity(row.quantity),
                    style: JpTypography.numeric(JpTypography.title).copyWith(color: colors.foreground),
                  ),
                  Text(row.unit, style: JpTypography.caption.copyWith(color: p.textMuted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ligne d'historique : type, motif, emplacement, variation et solde.
class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.movement, required this.unit, this.showLocation = false});

  final StockMovement movement;
  final String unit;
  final bool showLocation;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final incoming = movement.quantity > 0;
    final tone = p.tone(incoming ? JpTone.success : JpTone.danger);
    final signed = '${incoming ? '+' : '−'}${Formatters.quantity(movement.quantity.abs())}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: JpSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: tone.background, borderRadius: JpRadius.all(JpRadius.sm)),
            child: Icon(movement.type.icon, size: 18, color: tone.foreground),
          ),
          const SizedBox(width: JpSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(movement.type.label, style: JpTypography.bodyStrong.copyWith(color: p.textPrimary, fontSize: 14)),
                if (movement.reason?.isNotEmpty ?? false)
                  Text(
                    movement.reason!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: JpTypography.bodySmall.copyWith(color: p.textSecondary),
                  ),
                Text(
                  [
                    Formatters.dateTime(movement.createdAt),
                    if (showLocation && movement.locationName != null) movement.locationName!,
                  ].join(' · '),
                  style: JpTypography.caption.copyWith(color: p.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: JpSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(signed, style: JpTypography.numeric(JpTypography.bodyStrong).copyWith(color: tone.foreground)),
              Text(
                'Solde ${Formatters.quantity(movement.quantityAfter)} $unit',
                style: JpTypography.numeric(JpTypography.caption).copyWith(color: p.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
