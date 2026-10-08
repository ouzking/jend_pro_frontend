import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/scanner/barcode_scanner_screen.dart';
import '../../business/application/workspace_controller.dart';
import '../../inventory/application/inventory_providers.dart';
import '../../inventory/presentation/stock_tab.dart';
import '../application/catalog_providers.dart';
import '../domain/catalog_models.dart';
import 'widgets/categories_sheet.dart';
import 'widgets/product_visuals.dart';

/// Catalogue : recherche instantanée, scan, catégories, liste paginée.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _search = TextEditingController();
  bool _stockTab = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(productFilterProvider).query;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {}); // bouton « effacer »
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => ref.read(productFilterProvider.notifier).search(value));
  }

  void _clearQuery() {
    _search.clear();
    _debounce?.cancel();
    ref.read(productFilterProvider.notifier).search('');
    setState(() {});
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context, title: 'Rechercher par code-barres');
    if (code == null || !mounted) return;
    try {
      final product = await ref.read(productActionsProvider).findByBarcode(code);
      if (!mounted) return;
      if (product != null) {
        context.push(Routes.productDetail(product.id));
        return;
      }
      final canCreate = ref.read(permissionsProvider).can(Permission.productsCreate);
      if (!canCreate) {
        JpOverlays.toast(context, 'Aucun produit avec le code $code.', tone: JpTone.warning);
        return;
      }
      final create = await JpOverlays.confirm(
        context,
        title: 'Produit introuvable',
        message: 'Aucun produit n’a le code-barres $code. Voulez-vous le créer ?',
        confirmLabel: 'Créer le produit',
        icon: Icons.qr_code_scanner_rounded,
      );
      if (create && mounted) context.push(Routes.productNew(barcode: code));
    } on AppFailure catch (f) {
      if (mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final permissions = ref.watch(permissionsProvider);
    final filter = ref.watch(productFilterProvider);
    final list = ref.watch(productListProvider);
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final canCreate = permissions.can(Permission.productsCreate);
    final canManageCategories = permissions.can(Permission.categoriesManage);
    final canSeeStock = permissions.can(Permission.inventoryRead);
    final stockTab = _stockTab && canSeeStock;

    return Scaffold(
      floatingActionButton: canCreate && !stockTab
          ? FloatingActionButton.extended(
              heroTag: 'new-product',
              onPressed: () => context.push(Routes.productNew()),
              backgroundColor: p.brand,
              foregroundColor: p.textOnBrand,
              elevation: 2,
              highlightElevation: 4,
              icon: const Icon(Icons.add_rounded),
              label: Text('Produit', style: JpTypography.label.copyWith(color: p.textOnBrand)),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: JpConstrained(
          child: RefreshIndicator(
            onRefresh: () =>
                (stockTab ? ref.refresh(stockListProvider.future) : ref.refresh(productListProvider.future)).then<void>(
                  (_) {},
                  onError: (_) {},
                ),
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 600) {
                  stockTab
                      ? ref.read(stockListProvider.notifier).loadMore()
                      : ref.read(productListProvider.notifier).loadMore();
                }
                return false;
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.lg, JpSpacing.sm, JpSpacing.md),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text('Catalogue', style: JpTypography.headline.copyWith(color: p.textPrimary)),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Scanner un code-barres',
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            onPressed: _scan,
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Plus d’options',
                            icon: const Icon(Icons.more_vert_rounded),
                            onSelected: (v) {
                              switch (v) {
                                case 'categories':
                                  showCategoriesSheet(context);
                                case 'archived':
                                  ref
                                      .read(productFilterProvider.notifier)
                                      .status(
                                        filter.status == ProductStatusFilter.active
                                            ? ProductStatusFilter.archived
                                            : ProductStatusFilter.active,
                                      );
                              }
                            },
                            itemBuilder: (_) => [
                              if (canManageCategories)
                                const PopupMenuItem(value: 'categories', child: Text('Gérer les catégories')),
                              PopupMenuItem(
                                value: 'archived',
                                child: Text(
                                  filter.status == ProductStatusFilter.active
                                      ? 'Voir les produits archivés'
                                      : 'Voir les produits actifs',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (canSeeStock)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, 0, JpSpacing.gutter, JpSpacing.md),
                      sliver: SliverToBoxAdapter(
                        child: SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Produits'),
                              icon: Icon(Icons.inventory_2_outlined),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('Stock'),
                              icon: Icon(Icons.stacked_bar_chart_rounded),
                            ),
                          ],
                          selected: {stockTab},
                          onSelectionChanged: (v) => setState(() => _stockTab = v.first),
                        ),
                      ),
                    ),
                  if (stockTab)
                    const StockTab()
                  else ...[
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter),
                      sliver: SliverToBoxAdapter(
                        child: JpTextField(
                          controller: _search,
                          hint: 'Rechercher un produit, un SKU, un code…',
                          prefixIcon: Icons.search_rounded,
                          textInputAction: TextInputAction.search,
                          onChanged: _onQueryChanged,
                          suffix: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Effacer',
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: _clearQuery,
                                ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: _CategoryChips()),
                    if (filter.status == ProductStatusFilter.archived)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, 0, JpSpacing.gutter, JpSpacing.sm),
                        sliver: SliverToBoxAdapter(
                          child: JpBanner(
                            tone: JpTone.neutral,
                            icon: Icons.inventory_outlined,
                            message: 'Produits archivés : ils n’apparaissent plus à la vente.',
                            actionLabel: 'Actifs',
                            onAction: () => ref.read(productFilterProvider.notifier).status(ProductStatusFilter.active),
                          ),
                        ),
                      ),
                    ..._listSlivers(list, filter, currency, canCreate),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _listSlivers(AsyncValue<ProductPage> list, ProductFilter filter, String currency, bool canCreate) {
    final page = list.value;
    if (page == null) {
      if (list.hasError) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: JpErrorState(error: list.error!, onRetry: () => ref.invalidate(productListProvider)),
          ),
        ];
      }
      return [SliverList.builder(itemCount: 8, itemBuilder: (_, _) => const JpShimmer(child: ProductTileSkeleton()))];
    }

    if (page.items.isEmpty) {
      final searching = !filter.isDefault;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: searching
              ? JpEmptyState(
                  icon: Icons.search_off_rounded,
                  tone: JpTone.neutral,
                  title: filter.query.isEmpty ? 'Aucun produit ici' : 'Aucun résultat',
                  message: filter.query.isEmpty
                      ? 'Aucun produit ne correspond à ce filtre.'
                      : 'Aucun produit ne correspond à « ${filter.query} ».',
                )
              : JpEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Votre catalogue est vide',
                  message: 'Ajoutez vos produits avec leur prix : vous pourrez ensuite vendre en quelques secondes.',
                  actionLabel: canCreate ? 'Ajouter un produit' : null,
                  onAction: canCreate ? () => context.push(Routes.productNew()) : null,
                ),
        ),
      ];
    }

    return [
      if (list.isLoading) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
      SliverList.separated(
        itemCount: page.items.length,
        separatorBuilder: (_, _) => Divider(indent: JpSpacing.gutter + 64, color: context.palette.border),
        itemBuilder: (context, i) {
          final product = page.items[i];
          return ProductTile(
            product: product,
            currency: currency,
            onTap: () => context.push(Routes.productDetail(product.id)),
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
                    onPressed: () => ref.read(productListProvider.notifier).loadMore(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Réessayer'),
                  )
                : !page.hasMore
                ? Text(
                    '${page.items.length} produit${page.items.length > 1 ? 's' : ''}',
                    style: JpTypography.caption.copyWith(color: context.palette.textMuted),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    ];
  }
}

class _CategoryChips extends ConsumerWidget {
  const _CategoryChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final selected = ref.watch(productFilterProvider.select((f) => f.categoryId));
    if (categories.isEmpty) return const SizedBox(height: JpSpacing.md);
    final notifier = ref.read(productFilterProvider.notifier);
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.md),
        children: [
          ChoiceChip(label: const Text('Tout'), selected: selected == null, onSelected: (_) => notifier.category(null)),
          for (final c in categories) ...[
            const SizedBox(width: JpSpacing.sm),
            ChoiceChip(
              label: Text(c.name),
              selected: selected == c.id,
              onSelected: (v) => notifier.category(v ? c.id : null),
            ),
          ],
        ],
      ),
    );
  }
}
