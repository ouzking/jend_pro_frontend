import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/pagination/paged.dart';
import '../application/inventory_providers.dart';
import '../domain/inventory_models.dart';
import 'widgets/stock_widgets.dart';

/// Onglet « Stock » du catalogue (slivers, intégré au défilement commun).
class StockTab extends ConsumerWidget {
  const StockTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final view = ref.watch(stockViewProvider);
    final notifier = ref.read(stockViewProvider.notifier);
    final locations = ref.watch(locationsProvider).value ?? const [];
    final list = ref.watch(stockListProvider);
    final multi = locations.length > 1;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.xs, JpSpacing.gutter, JpSpacing.sm),
              children: [
                for (final (f, label, icon) in [
                  (StockFilter.all, 'Tout', null),
                  (StockFilter.low, 'Stock faible', Icons.trending_down_rounded),
                  (StockFilter.out, 'Rupture', Icons.block_rounded),
                ]) ...[
                  ChoiceChip(
                    avatar: icon == null ? null : Icon(icon, size: 16),
                    label: Text(label),
                    selected: view.filter == f,
                    onSelected: (_) => notifier.filter(f),
                  ),
                  const SizedBox(width: JpSpacing.sm),
                ],
              ],
            ),
          ),
        ),
        if (multi)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, 0, JpSpacing.gutter, JpSpacing.sm),
                children: [
                  FilterChip(
                    label: const Text('Tous les emplacements'),
                    selected: view.locationId == null,
                    onSelected: (_) => notifier.location(null),
                  ),
                  for (final l in locations) ...[
                    const SizedBox(width: JpSpacing.sm),
                    FilterChip(
                      avatar: Icon(l.isWarehouse ? Icons.warehouse_outlined : Icons.storefront_outlined, size: 16),
                      label: Text(l.name),
                      selected: view.locationId == l.id,
                      onSelected: (_) => notifier.location(l.id),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ..._body(context, ref, list, view, multi && view.locationId == null, p),
      ],
    );
  }

  List<Widget> _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Paged<StockRow>> list,
    StockView view,
    bool showLocation,
    JpPalette p,
  ) {
    final page = list.value;
    if (page == null) {
      if (list.hasError) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: JpErrorState(error: list.error!, onRetry: () => ref.invalidate(stockListProvider)),
          ),
        ];
      }
      return [
        SliverList.builder(
          itemCount: 8,
          itemBuilder: (_, _) => const JpShimmer(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.md),
              child: Row(
                children: [
                  JpSkeleton(width: 44, height: 44, radius: JpRadius.md),
                  SizedBox(width: JpSpacing.md),
                  Expanded(child: JpSkeleton()),
                  SizedBox(width: JpSpacing.xl),
                  JpSkeleton(width: 40, height: 24),
                ],
              ),
            ),
          ),
        ),
      ];
    }
    if (page.items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: switch (view.filter) {
            StockFilter.all => const JpEmptyState(
              icon: Icons.inventory_outlined,
              title: 'Aucun stock enregistré',
              message: 'Saisissez le stock d’un produit depuis sa fiche, ou réceptionnez un achat.',
            ),
            StockFilter.low => const JpEmptyState(
              icon: Icons.verified_outlined,
              tone: JpTone.success,
              title: 'Rien sous le seuil',
              message: 'Aucun produit n’est passé sous son seuil d’alerte.',
            ),
            StockFilter.out => const JpEmptyState(
              icon: Icons.verified_outlined,
              tone: JpTone.success,
              title: 'Aucune rupture',
              message: 'Tous vos produits suivis sont disponibles.',
            ),
          },
        ),
      ];
    }
    return [
      if (list.isLoading) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
      SliverList.separated(
        itemCount: page.items.length,
        separatorBuilder: (_, _) => Divider(indent: JpSpacing.gutter + 56, color: p.border),
        itemBuilder: (context, i) {
          final row = page.items[i];
          return StockRowTile(
            row: row,
            showLocation: showLocation,
            onTap: () => context.push(Routes.productStock(row.productId)),
          );
        },
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(JpSpacing.lg),
          child: Center(
            child: page.loadingMore
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.2))
                : page.loadMoreError != null
                ? TextButton.icon(
                    onPressed: () => ref.read(stockListProvider.notifier).loadMore(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Réessayer'),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    ];
  }
}
