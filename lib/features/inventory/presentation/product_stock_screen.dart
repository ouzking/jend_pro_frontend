import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/pagination/paged.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../../products/application/catalog_providers.dart';
import '../../products/domain/catalog_models.dart';
import '../../products/presentation/widgets/product_visuals.dart';
import '../application/inventory_providers.dart';
import '../domain/inventory_models.dart';
import 'stock_action_sheet.dart';
import 'widgets/stock_widgets.dart';

/// Stock d'un produit : quantités par emplacement, opérations, historique.
class ProductStockScreen extends ConsumerWidget {
  const ProductStockScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productDetailProvider(productId));
    final stock = ref.watch(productStockProvider(productId));
    return Scaffold(
      appBar: AppBar(title: const Text('Stock')),
      body: JpAsyncView<Product>(
        value: product,
        onRetry: () => ref.invalidate(productDetailProvider(productId)),
        data: (p) => p.trackStock
            ? JpAsyncView<List<LocationStock>>(
                value: stock,
                onRetry: () => ref.invalidate(productStockProvider(productId)),
                data: (s) => _StockBody(product: p, stock: s),
              )
            : const JpEmptyState(
                icon: Icons.design_services_outlined,
                tone: JpTone.neutral,
                title: 'Article non stocké',
                message: 'Ce produit est un service : aucune quantité n’est suivie.',
              ),
      ),
    );
  }
}

class _StockBody extends ConsumerWidget {
  const _StockBody({required this.product, required this.stock});

  final Product product;
  final List<LocationStock> stock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final permissions = ref.watch(permissionsProvider);
    final movements = ref.watch(movementsProvider(product.id));
    final canAdjust = permissions.can(Permission.inventoryAdjust);
    final canTransfer = permissions.can(Permission.inventoryTransfer) && stock.length > 1;
    final total = stock.fold<num>(0, (sum, s) => sum + (s.quantity ?? 0));
    final hasAny = stock.any((s) => s.quantity != null);
    final multi = stock.length > 1;

    final actions = [
      if (canAdjust) StockAction.add,
      if (canAdjust && hasAny) StockAction.remove,
      if (canAdjust && hasAny) StockAction.count,
      if (canTransfer && hasAny) StockAction.transfer,
    ];

    void open(StockAction action, [String? locationId]) =>
        showStockActionSheet(context, action: action, product: product, stock: stock, initialLocationId: locationId);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(productStockProvider(product.id));
        ref.invalidate(movementsProvider(product.id));
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 400) ref.read(movementsProvider(product.id).notifier).loadMore();
          return false;
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, JpSpacing.huge),
          children: [
            JpConstrained(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ProductThumb(name: product.name, imagePath: product.imagePath, size: 56),
                      const SizedBox(width: JpSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.name, style: JpTypography.titleSmall.copyWith(color: p.textPrimary)),
                            const SizedBox(height: JpSpacing.xs),
                            StockBadge(product: product),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: JpSpacing.xl),
                  JpCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          multi ? 'Stock total' : 'Stock disponible',
                          style: JpTypography.caption.copyWith(color: p.textSecondary, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: JpSpacing.xs),
                        Text(
                          hasAny ? '${Formatters.quantity(total)} ${product.unit}' : 'Pas encore saisi',
                          style: JpTypography.numeric(JpTypography.headline).copyWith(color: p.textPrimary),
                        ),
                        if (product.minStockLevel > 0)
                          Text(
                            'Seuil d’alerte : ${Formatters.quantity(product.minStockLevel)} ${product.unit}',
                            style: JpTypography.caption.copyWith(color: p.textMuted),
                          ),
                        if (multi) ...[
                          const SizedBox(height: JpSpacing.md),
                          for (final s in stock)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: JpSpacing.xs),
                              child: Row(
                                children: [
                                  Icon(
                                    s.location.isWarehouse ? Icons.warehouse_outlined : Icons.storefront_outlined,
                                    size: 18,
                                    color: p.textMuted,
                                  ),
                                  const SizedBox(width: JpSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      s.location.name,
                                      style: JpTypography.body.copyWith(color: p.textSecondary),
                                    ),
                                  ),
                                  Text(
                                    s.quantity == null ? '—' : Formatters.quantity(s.quantity!),
                                    style: JpTypography.numeric(JpTypography.bodyStrong).copyWith(color: p.textPrimary),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: JpSpacing.lg),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: JpSpacing.sm,
                      crossAxisSpacing: JpSpacing.sm,
                      childAspectRatio: 3.1,
                      children: [
                        for (final a in actions)
                          JpButton.outline(
                            label: a == StockAction.add && !hasAny ? 'Stock initial' : a.shortLabel,
                            icon: a.icon,
                            size: JpButtonSize.medium,
                            onPressed: () => open(a),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: JpSpacing.xxl),
                  const JpSectionHeader(title: 'Historique'),
                  _MovementsList(value: movements, unit: product.unit, showLocation: multi),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementsList extends ConsumerWidget {
  const _MovementsList({required this.value, required this.unit, required this.showLocation});

  final AsyncValue<Paged<StockMovement>> value;
  final String unit;
  final bool showLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final page = value.value;
    if (page == null) {
      return value.hasError
          ? JpErrorState(error: value.error!)
          : const Padding(
              padding: EdgeInsets.all(JpSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            );
    }
    if (page.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: JpSpacing.xl),
        child: Text(
          'Aucun mouvement pour l’instant. Chaque entrée, vente ou ajustement apparaîtra ici.',
          textAlign: TextAlign.center,
          style: JpTypography.bodySmall.copyWith(color: p.textMuted),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < page.items.length; i++) ...[
          if (i > 0) Divider(color: p.border),
          MovementTile(movement: page.items[i], unit: unit, showLocation: showLocation),
        ],
        if (page.loadingMore)
          const Padding(
            padding: EdgeInsets.all(JpSpacing.lg),
            child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.2)),
          ),
      ],
    );
  }
}
