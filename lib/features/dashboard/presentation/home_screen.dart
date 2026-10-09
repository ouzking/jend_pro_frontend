import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/formatting/business_time.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../auth/application/auth_session.dart';
import '../../business/application/workspace_controller.dart';
import '../application/dashboard_controller.dart';
import '../domain/dashboard_models.dart';
import 'widgets/dashboard_sections.dart';
import 'widgets/revenue_hero_card.dart';

/// Accueil — « Comment va mon commerce aujourd'hui ? »
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static String greeting(DateTime now) => now.hour < 12
      ? 'Bonjour'
      : now.hour < 18
      ? 'Bon après-midi'
      : 'Bonsoir';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final business = ref.watch(activeBusinessProvider);
    final permissions = ref.watch(permissionsProvider);
    final profile = ref.watch(userProfileProvider).value;
    final dashboard = ref.watch(dashboardProvider);
    final currency = business?.currencyCode ?? 'XOF';
    final canReport = permissions.can(Permission.reportsRead);

    Future<void> refresh() => ref.refresh(dashboardProvider.future).then<void>((_) {}, onError: (_) {});

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: JpSpacing.maxContentWidth),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.md, JpSpacing.md, 0),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          const JpLogo(size: 26),
                          const Spacer(),
                          const NotificationBell(),
                          IconButton(
                            tooltip: 'Mon compte',
                            onPressed: () => context.go(Routes.more),
                            icon: JpAvatar(name: profile?.displayName, size: JpSize.avatarSm + 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.lg, JpSpacing.gutter, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${greeting(BusinessTime.now(business?.timezone ?? 'Africa/Dakar').toLocal())}'
                            '${profile == null ? '' : ' ${profile.firstName}'}',
                            style: JpTypography.body.copyWith(color: p.textSecondary),
                          ),
                          Semantics(
                            header: true,
                            child: Text(
                              business?.businessName ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: JpTypography.headline.copyWith(color: p.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (canReport)
                    const SliverPadding(
                      padding: EdgeInsets.only(top: JpSpacing.lg),
                      sliver: SliverToBoxAdapter(child: _PeriodSelector()),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      JpSpacing.gutter,
                      JpSpacing.lg,
                      JpSpacing.gutter,
                      JpSpacing.huge,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: JpAsyncView<DashboardData>(
                        value: dashboard,
                        onRetry: () => ref.invalidate(dashboardProvider),
                        loading: const DashboardSkeleton(),
                        data: (data) => _DashboardBody(data: data, currency: currency, refreshing: dashboard.isLoading),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PeriodSelector extends ConsumerWidget {
  const _PeriodSelector();

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final timezone = ref.read(activeBusinessProvider)?.timezone ?? 'Africa/Dakar';
    final today = BusinessTime.today(timezone);
    final current = ref.read(dashboardPeriodProvider);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
      initialDateRange: current.kind == PeriodKind.custom ? DateTimeRange(start: current.from, end: current.to) : null,
      helpText: 'Choisir une période',
      saveText: 'Valider',
    );
    if (range == null || !context.mounted) return;
    if (range.duration.inDays >= DashboardPeriod.maxDays) {
      JpOverlays.toast(context, 'Période limitée à 366 jours : la fin a été ajustée.', tone: JpTone.warning);
    }
    ref.read(dashboardPeriodProvider.notifier).custom(range.start, range.end);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(dashboardPeriodProvider);
    final notifier = ref.read(dashboardPeriodProvider.notifier);
    final chips = [(PeriodKind.today, 'Aujourd’hui'), (PeriodKind.week, '7 jours'), (PeriodKind.month, '30 jours')];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter),
        children: [
          for (final (kind, label) in chips) ...[
            ChoiceChip(label: Text(label), selected: period.kind == kind, onSelected: (_) => notifier.select(kind)),
            const SizedBox(width: JpSpacing.sm),
          ],
          ChoiceChip(
            avatar: const Icon(Icons.date_range_rounded, size: 18),
            label: const Text('Période'),
            selected: period.kind == PeriodKind.custom,
            onSelected: (_) => _pickRange(context, ref),
          ),
        ],
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.data, required this.currency, required this.refreshing});

  final DashboardData data;
  final String currency;
  final bool refreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final permissions = ref.watch(permissionsProvider);
    final summary = data.summary;
    final canSell = permissions.can(Permission.salesCreate);

    final actions = [
      // Sans indicateurs, la carte « Prêt à encaisser » porte déjà l'action.
      if (canSell && summary != null)
        QuickAction(
          label: 'Encaisser',
          icon: Icons.point_of_sale_rounded,
          primary: true,
          onTap: () => context.push(Routes.sale),
        ),
      if (permissions.can(Permission.productsRead))
        QuickAction(label: 'Stock', icon: Icons.inventory_2_outlined, onTap: () => context.go(Routes.catalog)),
      if (permissions.can(Permission.customersRead))
        QuickAction(label: 'Clients', icon: Icons.people_alt_outlined, onTap: () => context.go(Routes.customers)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary != null)
          RevenueHeroCard(data: data, currency: currency, refreshing: refreshing)
        else if (canSell)
          _CashierHero(onSell: () => context.push(Routes.sale)),
        if (actions.isNotEmpty) ...[const SizedBox(height: JpSpacing.lg), QuickActionsRow(actions: actions)],
        if (summary != null) ...[
          const SizedBox(height: JpSpacing.lg),
          KpiGrid(
            children: [
              KpiTile(
                label: 'Panier moyen',
                icon: Icons.shopping_bag_outlined,
                value: JpAmount(summary.averageBasket, currency: currency, style: JpTypography.title),
                caption: summary.cancelledCount > 0
                    ? '${summary.cancelledCount} annulée${summary.cancelledCount > 1 ? 's' : ''}'
                    : '${summary.activeCustomers} client${summary.activeCustomers > 1 ? 's' : ''} identifié${summary.activeCustomers > 1 ? 's' : ''}',
              ),
              if (summary.estimatedMargin != null)
                KpiTile(
                  label: 'Bénéfice estimé',
                  icon: Icons.trending_up_rounded,
                  tone: JpTone.success,
                  value: JpAmount(
                    summary.estimatedMargin!,
                    currency: currency,
                    style: JpTypography.title,
                    color: summary.estimatedMargin! < 0 ? p.danger : null,
                  ),
                  caption: summary.revenue > 0
                      ? 'Marge ${(summary.estimatedMargin! / summary.revenue * 100).round()} % du CA'
                      : 'Selon les coûts d’achat',
                ),
              KpiTile(
                label: 'Dépenses',
                icon: Icons.receipt_long_outlined,
                tone: JpTone.accent,
                value: JpAmount(summary.expenses, currency: currency, style: JpTypography.title),
                caption: 'Trésorerie nette ${_signed(summary.netCashFlow)}',
              ),
              KpiTile(
                label: 'Créances clients',
                icon: Icons.account_balance_wallet_outlined,
                tone: summary.customersDebt > 0 ? JpTone.warning : JpTone.neutral,
                value: JpAmount(summary.customersDebt, currency: currency, style: JpTypography.title),
                caption: summary.creditGiven > 0 ? 'Crédit accordé sur la période' : 'Montant total dû',
                onTap: permissions.can(Permission.customersRead) ? () => context.go(Routes.customers) : null,
              ),
            ],
          ),
        ],
        if (data.lowStock?.isNotEmpty ?? false) ...[
          const SizedBox(height: JpSpacing.lg),
          LowStockCard(items: data.lowStock!, onTap: () => context.go(Routes.catalog)),
        ],
        if (data.topProducts.isNotEmpty) ...[
          const SizedBox(height: JpSpacing.xxl),
          JpSectionHeader(
            title: 'Meilleures ventes',
            actionLabel: 'Rapports',
            onAction: () => context.push(Routes.reports),
          ),
          const SizedBox(height: JpSpacing.sm),
          TopProductsCard(products: data.topProducts.take(5).toList(), currency: currency),
        ],
        if (permissions.canSeeSales) ...[
          const SizedBox(height: JpSpacing.xxl),
          JpSectionHeader(
            title: permissions.can(Permission.salesRead) ? 'Dernières ventes' : 'Mes dernières ventes',
            actionLabel: data.recentSales.isEmpty ? null : 'Tout voir',
            onAction: () => context.push(Routes.salesHistory),
          ),
          const SizedBox(height: JpSpacing.sm),
          if (data.recentSales.isEmpty)
            JpCard(
              child: Column(
                children: [
                  const JpIllustratedIcon(icon: Icons.receipt_long_outlined, size: 64),
                  const SizedBox(height: JpSpacing.md),
                  Text('Aucune vente pour l’instant', style: JpTypography.bodyStrong.copyWith(color: p.textPrimary)),
                  const SizedBox(height: JpSpacing.xs),
                  Text(
                    'Vos ventes apparaîtront ici en temps réel.',
                    textAlign: TextAlign.center,
                    style: JpTypography.bodySmall.copyWith(color: p.textMuted),
                  ),
                  if (canSell) ...[
                    const SizedBox(height: JpSpacing.lg),
                    JpButton(
                      label: 'Enregistrer une vente',
                      icon: Icons.add_rounded,
                      size: JpButtonSize.medium,
                      expand: false,
                      onPressed: () => context.push(Routes.sale),
                    ),
                  ],
                ],
              ),
            )
          else
            RecentSalesList(
              sales: data.recentSales,
              currency: currency,
              onTap: (sale) => context.push(Routes.saleDetail(sale.id)),
            ),
        ],
      ],
    );
  }

  String _signed(int amount) {
    final text = Formatters.money(amount.abs(), currency: currency);
    return amount < 0 ? '−$text' : text;
  }
}

/// Accueil sans `reports.read` (caissier) : l'action principale d'abord.
class _CashierHero extends StatelessWidget {
  const _CashierHero({required this.onSell});

  final VoidCallback onSell;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(JpSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: JpRadius.all(JpRadius.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.heroStart, p.heroEnd],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Prêt à encaisser ?', style: JpTypography.title.copyWith(color: Colors.white)),
          const SizedBox(height: JpSpacing.xs),
          Text(
            'Une vente se fait en quelques secondes.',
            style: JpTypography.body.copyWith(color: Colors.white.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: JpSpacing.lg),
          Material(
            color: JpColors.mint400,
            borderRadius: JpRadius.all(JpRadius.md),
            child: InkWell(
              borderRadius: JpRadius.all(JpRadius.md),
              onTap: onSell,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: JpSpacing.xl, vertical: JpSpacing.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.point_of_sale_rounded, color: JpColors.forest950),
                    const SizedBox(width: JpSpacing.sm),
                    Text('Nouvelle vente', style: JpTypography.label.copyWith(color: JpColors.forest950)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
