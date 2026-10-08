import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/formatting/formatters.dart';
import '../../domain/dashboard_models.dart';

/// Raccourci de l'accueil (maquette : Encaisser, Stock, Clients…).
class QuickAction {
  const QuickAction({required this.label, required this.icon, required this.onTap, this.primary = false});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
}

class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key, required this.actions});

  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: JpSpacing.sm),
          Expanded(
            child: Semantics(
              button: true,
              label: actions[i].label,
              excludeSemantics: true,
              child: Material(
                color: actions[i].primary ? p.brand : p.surface,
                borderRadius: JpRadius.all(JpRadius.lg),
                child: InkWell(
                  borderRadius: JpRadius.all(JpRadius.lg),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    actions[i].onTap();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: JpSpacing.md),
                    decoration: BoxDecoration(
                      borderRadius: JpRadius.all(JpRadius.lg),
                      border: Border.all(color: actions[i].primary ? Colors.transparent : p.border),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          actions[i].icon,
                          size: JpSize.iconMd,
                          color: actions[i].primary ? p.textOnBrand : p.brandStrong,
                        ),
                        const SizedBox(height: JpSpacing.xs + 2),
                        Text(
                          actions[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: JpTypography.caption.copyWith(
                            color: actions[i].primary ? p.textOnBrand : p.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Tuile d'indicateur : libellé, valeur, précision.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    this.caption,
    this.tone = JpTone.brand,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Widget value;
  final String? caption;
  final JpTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final colors = p.tone(tone);
    return JpCard(
      onTap: onTap,
      padding: const EdgeInsets.all(JpSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: colors.background, borderRadius: JpRadius.all(JpRadius.sm)),
                child: Icon(icon, size: 17, color: colors.foreground),
              ),
              const SizedBox(width: JpSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JpTypography.caption.copyWith(color: p.textSecondary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: JpSpacing.md),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
          if (caption != null) ...[
            const SizedBox(height: JpSpacing.xxs),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: JpTypography.caption.copyWith(color: p.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Grille 2 colonnes (3 sur tablette) qui garde des tuiles de même hauteur.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.sizeOf(context).width >= JpBreakpoints.tablet ? 4 : 2;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final slice = children.sublist(i, (i + columns).clamp(0, children.length));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) const SizedBox(width: JpSpacing.md),
                Expanded(child: j < slice.length ? slice[j] : const SizedBox()),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: JpSpacing.md), rows[i]],
      ],
    );
  }
}

/// Alerte stock faible : visible seulement s'il y a quelque chose à faire.
class LowStockCard extends StatelessWidget {
  const LowStockCard({super.key, required this.items, this.onTap});

  final List<LowStockItem> items;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final out = items.where((i) => i.isOut).length;
    final tone = p.tone(out > 0 ? JpTone.danger : JpTone.warning);
    return JpCard(
      onTap: onTap,
      borderColor: tone.foreground.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: tone.background, borderRadius: JpRadius.all(JpRadius.sm)),
                child: Icon(Icons.inventory_outlined, color: tone.foreground, size: 20),
              ),
              const SizedBox(width: JpSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${items.length} produit${items.length > 1 ? 's' : ''} à réapprovisionner',
                      style: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
                    ),
                    Text(
                      out > 0 ? '$out en rupture' : 'Sous le seuil minimal',
                      style: JpTypography.bodySmall.copyWith(color: tone.foreground),
                    ),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, color: p.textMuted),
            ],
          ),
          const SizedBox(height: JpSpacing.md),
          for (final item in items.take(3))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: JpSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: JpTypography.bodySmall.copyWith(color: p.textSecondary),
                    ),
                  ),
                  JpBadge(
                    label: item.isOut ? 'Rupture' : 'Reste ${Formatters.quantity(item.quantity)}',
                    tone: item.isOut ? JpTone.danger : JpTone.warning,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Meilleures ventes de la période, avec barre de proportion.
class TopProductsCard extends StatelessWidget {
  const TopProductsCard({super.key, required this.products, required this.currency});

  final List<TopProduct> products;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final max = products.fold<int>(0, (m, e) => e.revenue > m ? e.revenue : m);
    return JpCard(
      child: Column(
        children: [
          for (var i = 0; i < products.length; i++) ...[
            if (i > 0) const SizedBox(height: JpSpacing.md),
            Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text('${i + 1}', style: JpTypography.label.copyWith(color: i == 0 ? p.accent : p.textMuted)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              products[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: JpTypography.bodyStrong.copyWith(color: p.textPrimary, fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: JpSpacing.sm),
                          JpAmount(products[i].revenue, currency: currency, style: JpTypography.label),
                        ],
                      ),
                      const SizedBox(height: JpSpacing.xs + 2),
                      ClipRRect(
                        borderRadius: JpRadius.all(JpRadius.pill),
                        child: LinearProgressIndicator(
                          value: max == 0 ? 0 : products[i].revenue / max,
                          minHeight: 4,
                          backgroundColor: p.surfaceMuted,
                          color: i == 0 ? p.signal : p.brand.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: JpSpacing.xxs),
                      Text(
                        '${Formatters.quantity(products[i].quantity)} vendu${products[i].quantity > 1 ? 's' : ''}',
                        style: JpTypography.caption.copyWith(color: p.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// « Dernières ventes » (maquette) : initiales, article, heure, moyen de
/// paiement, montant.
class RecentSalesList extends StatelessWidget {
  const RecentSalesList({super.key, required this.sales, required this.currency, this.onTap});

  final List<RecentSale> sales;
  final String currency;
  final ValueChanged<RecentSale>? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return JpCard(
      padding: const EdgeInsets.symmetric(vertical: JpSpacing.xs),
      child: Column(
        children: [
          for (var i = 0; i < sales.length; i++) ...[
            if (i > 0) Divider(indent: 68, color: p.border),
            InkWell(
              onTap: onTap == null ? null : () => onTap!(sales[i]),
              child: _SaleRow(sale: sales[i], currency: currency),
            ),
          ],
        ],
      ),
    );
  }
}

class _SaleRow extends StatelessWidget {
  const _SaleRow({required this.sale, required this.currency});

  final RecentSale sale;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final title = sale.firstItemName == null
        ? sale.number
        : '${sale.firstItemName} × ${Formatters.quantity(sale.firstItemQuantity ?? 1)}'
              '${sale.itemCount > 1 ? ' +${sale.itemCount - 1}' : ''}';
    final meta = [
      Formatters.relative(sale.soldAt),
      if (sale.cancelled)
        'Annulée'
      else if (sale.creditAmount > 0)
        sale.creditAmount == sale.total ? 'À crédit' : 'Crédit partiel'
      else if (sale.paymentMethod != null)
        sale.paymentMethod!.label,
      if (sale.customerName != null) sale.customerName!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.md),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.brandSoft, borderRadius: JpRadius.all(JpRadius.md)),
            child: Text(
              sale.firstItemName != null
                  ? Formatters.productMonogram(sale.firstItemName)
                  : Formatters.initials(sale.customerName ?? 'V'),
              style: JpTypography.label.copyWith(color: p.brandStrong, fontSize: 13),
            ),
          ),
          const SizedBox(width: JpSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JpTypography.bodyStrong.copyWith(
                    color: sale.cancelled ? p.textMuted : p.textPrimary,
                    fontSize: 14,
                    decoration: sale.cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JpTypography.caption.copyWith(color: sale.cancelled ? p.danger : p.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: JpSpacing.sm),
          JpAmount(
            sale.total,
            currency: currency,
            style: JpTypography.label,
            color: sale.cancelled ? p.textMuted : null,
          ),
        ],
      ),
    );
  }
}

/// Squelette de l'accueil (même silhouette que le contenu réel).
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const JpShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          JpSkeleton(height: 230, radius: JpRadius.xl),
          SizedBox(height: JpSpacing.lg),
          Row(
            children: [
              Expanded(child: JpSkeleton(height: 72, radius: JpRadius.lg)),
              SizedBox(width: JpSpacing.sm),
              Expanded(child: JpSkeleton(height: 72, radius: JpRadius.lg)),
              SizedBox(width: JpSpacing.sm),
              Expanded(child: JpSkeleton(height: 72, radius: JpRadius.lg)),
            ],
          ),
          SizedBox(height: JpSpacing.lg),
          Row(
            children: [
              Expanded(child: JpSkeleton(height: 110, radius: JpRadius.lg)),
              SizedBox(width: JpSpacing.md),
              Expanded(child: JpSkeleton(height: 110, radius: JpRadius.lg)),
            ],
          ),
          SizedBox(height: JpSpacing.xxl),
          JpSkeleton(height: 200, radius: JpRadius.lg),
        ],
      ),
    );
  }
}
