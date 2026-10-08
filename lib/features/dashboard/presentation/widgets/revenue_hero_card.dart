import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/formatting/formatters.dart';
import '../../domain/dashboard_models.dart';

/// Carte héros (maquette « Ventes du jour ») : CA de la période, variation
/// vs la période précédente, histogramme.
class RevenueHeroCard extends StatelessWidget {
  const RevenueHeroCard({super.key, required this.data, required this.currency, this.refreshing = false});

  final DashboardData data;
  final String currency;
  final bool refreshing;

  String get _title => switch (data.period.kind) {
    PeriodKind.today => 'Ventes du jour',
    PeriodKind.week => 'Ventes · 7 jours',
    PeriodKind.month => 'Ventes · 30 jours',
    PeriodKind.custom => 'Ventes · ${Formatters.date(data.period.from)} – ${Formatters.date(data.period.to)}',
  };

  List<JpBarDatum> _bars() {
    final granularity = data.period.granularity;
    final short = switch (granularity) {
      'day' when data.period.chartWindow.days <= 7 => DateFormat('E', 'fr'),
      'day' => DateFormat('d', 'fr'),
      'week' => DateFormat('d/M', 'fr'),
      _ => DateFormat('MMM', 'fr'),
    };
    final long = switch (granularity) {
      'day' => DateFormat('EEE d MMM', 'fr'),
      'week' => DateFormat("'Sem. du' d MMM", 'fr'),
      _ => DateFormat('MMMM y', 'fr'),
    };
    return [
      for (final point in data.series)
        JpBarDatum(
          value: point.revenue,
          label: short.format(point.period).replaceAll('.', ''),
          detail: '${long.format(point.period)} · ${Formatters.money(point.revenue, currency: currency)}',
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final summary = data.summary!;
    final delta = data.revenueDelta;
    final bars = _bars();
    const onHero = Colors.white;

    return Container(
      padding: const EdgeInsets.fromLTRB(JpSpacing.xl, JpSpacing.xl, JpSpacing.xl, JpSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: JpRadius.all(JpRadius.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.heroStart, p.heroEnd],
        ),
        border: Border.all(color: JpColors.mint400.withValues(alpha: 0.12)),
        boxShadow: JpShadows.md(p.shadow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JpTypography.label.copyWith(color: onHero.withValues(alpha: 0.78)),
                ),
              ),
              // Construit uniquement pendant un rafraîchissement : un
              // indicateur masqué continuerait d'animer (batterie).
              if (refreshing)
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.8, color: JpColors.mint300),
                ),
            ],
          ),
          const SizedBox(height: JpSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: JpAmount(summary.revenue, currency: currency, style: JpTypography.display, color: onHero),
          ),
          const SizedBox(height: JpSpacing.sm),
          Wrap(
            spacing: JpSpacing.sm,
            runSpacing: JpSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (delta != null) _DeltaPill(delta: delta, label: data.period.comparisonLabel),
              Text(
                '${summary.salesCount} vente${summary.salesCount > 1 ? 's' : ''}',
                style: JpTypography.caption.copyWith(color: onHero.withValues(alpha: 0.7)),
              ),
            ],
          ),
          if (bars.isNotEmpty) ...[
            const SizedBox(height: JpSpacing.lg),
            JpBarChart(
              data: bars,
              height: 72,
              barColor: onHero.withValues(alpha: 0.14),
              highlightColor: JpColors.mint400,
              labelColor: onHero.withValues(alpha: 0.62),
              semanticsLabel: 'Évolution du chiffre d’affaires sur ${bars.length} périodes.',
            ),
          ],
        ],
      ),
    );
  }
}

class _DeltaPill extends StatelessWidget {
  const _DeltaPill({required this.delta, required this.label});

  final double delta;
  final String label;

  @override
  Widget build(BuildContext context) {
    final up = delta >= 0;
    final color = up ? JpColors.mint300 : JpColors.red400;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: JpSpacing.sm, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: JpRadius.all(JpRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.north_east_rounded : Icons.south_east_rounded, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            '${Formatters.percentDelta(delta)} $label',
            style: JpTypography.numeric(JpTypography.caption).copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
