import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../../dashboard/domain/dashboard_models.dart';
import '../../dashboard/presentation/widgets/dashboard_sections.dart';
import '../../documents/application/document_providers.dart';
import '../../documents/data/document_builder.dart';
import '../../documents/presentation/document_preview_screen.dart';
import '../application/report_providers.dart';
import '../domain/report_models.dart';

/// Rapports d'activité : tout est agrégé par le serveur (`reports.read`).
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final today = reportToday(ref.read(activeBusinessProvider)?.timezone);
    final current = ref.read(reportSelectionProvider).period;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
      initialDateRange: DateTimeRange(start: current.from, end: current.to),
      helpText: 'Période du rapport (366 jours max.)',
      saveText: 'Valider',
    );
    if (picked == null) return;
    ref.read(reportSelectionProvider.notifier).custom(picked.start, picked.end);
    if (picked.end.difference(picked.start).inDays >= DashboardPeriod.maxDays && context.mounted) {
      JpOverlays.toast(context, 'Période limitée à 366 jours.', tone: JpTone.warning);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final selection = ref.watch(reportSelectionProvider);
    final data = ref.watch(reportDataProvider);
    final value = data.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapports'),
        actions: [
          if (value != null)
            IconButton(
              tooltip: 'Exporter en PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => DocumentPreviewScreen.open(
                context,
                title: 'Rapport d’activité',
                filename: documentFilename(
                  'Rapport',
                  '${Formatters.isoDay(value.period.from)}-${Formatters.isoDay(value.period.to)}',
                ),
                build: () async =>
                    DocumentBuilder.report(value, await ref.read(documentIssuerProvider.future), selection.label),
              ),
            ),
        ],
      ),
      body: JpConstrained(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(reportDataProvider.future).then<void>((_) {}, onError: (_) {}),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.only(bottom: JpSpacing.huge),
            children: [
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.sm),
                  children: [
                    for (final r in ReportRange.values) ...[
                      ChoiceChip(
                        avatar: r == ReportRange.custom ? const Icon(Icons.date_range_rounded, size: 16) : null,
                        label: Text(r.label),
                        selected: selection.range == r,
                        onSelected: (_) => r == ReportRange.custom
                            ? _pickRange(context, ref)
                            : ref.read(reportSelectionProvider.notifier).select(r),
                      ),
                      const SizedBox(width: JpSpacing.sm),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter),
                child: Text(
                  ReportSelection.periodLabel(selection.period),
                  style: JpTypography.caption.copyWith(color: p.textMuted),
                ),
              ),
              const SizedBox(height: JpSpacing.md),
              switch (data) {
                AsyncValue(:final value?) => _ReportBody(data: value, refreshing: data.isLoading),
                AsyncError(:final error) => Padding(
                  padding: const EdgeInsets.only(top: JpSpacing.huge),
                  child: JpErrorState(error: error, onRetry: () => ref.invalidate(reportDataProvider)),
                ),
                _ => const JpSkeletonList(itemCount: 6),
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportBody extends ConsumerWidget {
  const _ReportBody({required this.data, required this.refreshing});

  final ReportData data;
  final bool refreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final s = data.summary;
    final prev = data.previous;
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final permissions = ref.watch(permissionsProvider);
    String money(int v) => Formatters.money(v, currency: currency);

    return AnimatedOpacity(
      opacity: refreshing ? 0.6 : 1,
      duration: JpMotion.fast,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ChartCard(data: data, currency: currency),
            const SizedBox(height: JpSpacing.lg),
            KpiGrid(
              children: [
                KpiTile(
                  label: 'Ventes',
                  icon: Icons.receipt_long_outlined,
                  value: _ValueWithDelta(
                    text: '${s.salesCount}',
                    delta: ReportData.delta(s.salesCount, prev.salesCount),
                  ),
                  caption: s.cancelledCount > 0 ? '${s.cancelledCount} annulée(s)' : 'Aucune annulation',
                ),
                KpiTile(
                  label: 'Panier moyen',
                  icon: Icons.shopping_basket_outlined,
                  value: _ValueWithDelta(
                    text: money(s.averageBasket),
                    delta: ReportData.delta(s.averageBasket, prev.averageBasket),
                  ),
                ),
                if (s.estimatedMargin != null)
                  KpiTile(
                    label: 'Marge estimée',
                    icon: Icons.trending_up_rounded,
                    tone: s.estimatedMargin! >= 0 ? JpTone.success : JpTone.danger,
                    value: _ValueWithDelta(
                      text: money(s.estimatedMargin!),
                      delta: prev.estimatedMargin == null
                          ? null
                          : ReportData.delta(s.estimatedMargin!, prev.estimatedMargin!),
                    ),
                    caption: data.marginRate == null
                        ? null
                        : '${(data.marginRate! * 100).toStringAsFixed(1).replaceAll('.', ',')} % du CA',
                  ),
                KpiTile(
                  label: 'Clients actifs',
                  icon: Icons.people_alt_outlined,
                  value: Text('${s.activeCustomers}', style: _kpiStyle(p)),
                ),
                KpiTile(
                  label: 'Remises accordées',
                  icon: Icons.local_offer_outlined,
                  tone: JpTone.warning,
                  value: Text(money(s.discounts), style: _kpiStyle(p)),
                ),
                KpiTile(
                  label: 'Vendu à crédit',
                  icon: Icons.handshake_outlined,
                  tone: JpTone.warning,
                  value: Text(money(s.creditGiven), style: _kpiStyle(p)),
                  caption: 'Créances totales : ${money(s.customersDebt)}',
                  onTap: permissions.can(Permission.customersRead) ? () => context.go(Routes.customers) : null,
                ),
              ],
            ),
            const SizedBox(height: JpSpacing.xl),
            const JpSectionHeader(title: 'Trésorerie'),
            const SizedBox(height: JpSpacing.sm),
            JpCard(
              child: Column(
                children: [
                  _MoneyRow('Encaissements', s.cashIn, currency, icon: Icons.south_west_rounded, tone: JpTone.success),
                  _MoneyRow(
                    'Décaissements (fournisseurs, remboursements)',
                    -s.cashOut,
                    currency,
                    icon: Icons.north_east_rounded,
                    tone: JpTone.danger,
                  ),
                  _MoneyRow('Dépenses', -s.expenses, currency, icon: Icons.receipt_outlined, tone: JpTone.warning),
                  Divider(height: JpSpacing.xl, color: p.border),
                  _MoneyRow(
                    'Flux net',
                    s.netCashFlow,
                    currency,
                    strong: true,
                    tone: s.netCashFlow >= 0 ? JpTone.success : JpTone.danger,
                  ),
                ],
              ),
            ),
            const SizedBox(height: JpSpacing.xl),
            const JpSectionHeader(title: 'Meilleures ventes'),
            const SizedBox(height: JpSpacing.sm),
            if (data.topProducts.isEmpty)
              JpCard(
                child: Text('Aucune vente sur la période.', style: JpTypography.body.copyWith(color: p.textMuted)),
              )
            else
              _TopProducts(products: data.topProducts, currency: currency, totalRevenue: s.revenue),
            if (permissions.can(Permission.auditRead)) ...[
              const SizedBox(height: JpSpacing.xl),
              JpButton.ghost(
                label: 'Journal d’audit',
                icon: Icons.history_rounded,
                onPressed: () => context.push(Routes.audit),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static TextStyle _kpiStyle(JpPalette p) => JpTypography.numeric(JpTypography.title).copyWith(color: p.textPrimary);
}

class _ChartCard extends ConsumerWidget {
  const _ChartCard({required this.data, required this.currency});

  final ReportData data;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final metric = ref.watch(reportMetricProvider);
    final effective = metric == ReportMetric.margin && !data.hasMargin ? ReportMetric.revenue : metric;
    final s = data.summary;
    final (headline, delta) = switch (effective) {
      ReportMetric.revenue => (
        Formatters.money(s.revenue, currency: currency),
        ReportData.delta(s.revenue, data.previous.revenue),
      ),
      ReportMetric.margin => (
        Formatters.money(s.estimatedMargin ?? 0, currency: currency),
        data.previous.estimatedMargin == null
            ? null
            : ReportData.delta(s.estimatedMargin ?? 0, data.previous.estimatedMargin!),
      ),
      ReportMetric.count => ('${s.salesCount} ventes', ReportData.delta(s.salesCount, data.previous.salesCount)),
    };
    final granularity = data.period.granularity;
    final short = switch (granularity) {
      'day' when data.period.days <= 7 => DateFormat('E', 'fr'),
      'day' => DateFormat('d', 'fr'),
      'week' => DateFormat('d/M', 'fr'),
      _ => DateFormat('MMM', 'fr'),
    };
    final long = switch (granularity) {
      'day' => DateFormat('EEE d MMM', 'fr'),
      'week' => DateFormat("'Sem. du' d MMM", 'fr'),
      _ => DateFormat('MMMM y', 'fr'),
    };
    final bars = [
      for (final point in data.series)
        () {
          final v = switch (effective) {
            ReportMetric.revenue => point.revenue,
            ReportMetric.margin => point.estimatedMargin ?? 0,
            ReportMetric.count => point.salesCount,
          };
          return JpBarDatum(
            value: v < 0 ? 0 : v,
            label: short.format(point.period).replaceAll('.', ''),
            detail:
                '${long.format(point.period)} · ${effective == ReportMetric.count ? '$v vente(s)' : Formatters.money(v, currency: currency)}',
          );
        }(),
    ];
    return JpCard(
      padding: const EdgeInsets.all(JpSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<ReportMetric>(
            segments: [
              for (final m in ReportMetric.values)
                if (m != ReportMetric.margin || data.hasMargin) ButtonSegment(value: m, label: Text(m.label)),
            ],
            selected: {effective},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (v) => ref.read(reportMetricProvider.notifier).set(v.single),
          ),
          const SizedBox(height: JpSpacing.lg),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(headline, style: JpTypography.numeric(JpTypography.display).copyWith(color: p.textPrimary)),
          ),
          const SizedBox(height: JpSpacing.xs),
          Row(
            children: [
              DeltaBadge(delta: delta),
              const SizedBox(width: JpSpacing.sm),
              Flexible(
                child: Text(
                  'vs période précédente',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JpTypography.caption.copyWith(color: p.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: JpSpacing.xl),
          if (bars.isEmpty)
            SizedBox(
              height: 80,
              child: Center(
                child: Text('Pas de données', style: JpTypography.caption.copyWith(color: p.textMuted)),
              ),
            )
          else
            JpBarChart(
              data: bars,
              height: 150,
              barColor: p.brandSoft,
              highlightColor: p.accent,
              labelColor: p.textMuted,
              showLabels: bars.length <= 16,
              semanticsLabel: '${effective.label} par période',
            ),
        ],
      ),
    );
  }
}

/// Variation « +12,3 % » colorée (ou « — » si non comparable).
class DeltaBadge extends StatelessWidget {
  const DeltaBadge({super.key, required this.delta});

  final double? delta;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    if (d == null) return const JpBadge(label: '—');
    final up = d >= 0;
    return JpBadge(
      label: Formatters.percentDelta(d),
      icon: up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
      tone: d == 0 ? JpTone.neutral : (up ? JpTone.success : JpTone.danger),
    );
  }
}

class _ValueWithDelta extends StatelessWidget {
  const _ValueWithDelta({required this.text, required this.delta});

  final String text;
  final double? delta;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text, style: _ReportBody._kpiStyle(context.palette)),
      if (delta != null) ...[const SizedBox(width: JpSpacing.sm), DeltaBadge(delta: delta)],
    ],
  );
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow(this.label, this.amount, this.currency, {this.icon, this.tone = JpTone.neutral, this.strong = false});

  final String label;
  final int amount;
  final String currency;
  final IconData? icon;
  final JpTone tone;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final colors = p.tone(tone);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: JpSpacing.xs),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: colors.foreground), const SizedBox(width: JpSpacing.sm)],
          Expanded(
            child: Text(
              label,
              style: (strong ? JpTypography.bodyStrong : JpTypography.body).copyWith(color: p.textPrimary),
            ),
          ),
          JpAmount(
            amount,
            currency: currency,
            style: strong ? JpTypography.title : JpTypography.bodyStrong,
            color: strong ? colors.foreground : null,
          ),
        ],
      ),
    );
  }
}

class _TopProducts extends StatelessWidget {
  const _TopProducts({required this.products, required this.currency, required this.totalRevenue});

  final List<TopProduct> products;
  final String currency;
  final int totalRevenue;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final best = products.first.revenue == 0 ? 1 : products.first.revenue;
    return JpCard(
      child: Column(
        children: [
          for (final (i, t) in products.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: JpSpacing.sm),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text('${i + 1}', style: JpTypography.label.copyWith(color: i < 3 ? p.accent : p.textMuted)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: JpTypography.bodyStrong),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: JpRadius.all(JpRadius.xs),
                          child: LinearProgressIndicator(
                            value: (t.revenue / best).clamp(0, 1).toDouble(),
                            minHeight: 5,
                            backgroundColor: p.surfaceMuted,
                            color: i == 0 ? p.accent : p.brand,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            'Qté ${Formatters.quantity(t.quantity)}',
                            if (totalRevenue > 0) '${(t.revenue * 100 / totalRevenue).toStringAsFixed(0)} % du CA',
                            if (t.estimatedMargin != null)
                              'marge ${Formatters.money(t.estimatedMargin!, currency: currency)}',
                          ].join(' · '),
                          style: JpTypography.caption.copyWith(color: p.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: JpSpacing.md),
                  JpAmount(t.revenue, currency: currency, style: JpTypography.label),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
