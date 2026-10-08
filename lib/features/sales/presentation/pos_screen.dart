import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/scanner/barcode_scanner_screen.dart';
import '../../business/application/workspace_controller.dart';
import '../../inventory/application/inventory_providers.dart';
import '../../products/application/catalog_providers.dart';
import '../application/pos_providers.dart';
import '../data/sales_repository.dart';
import '../domain/cart.dart';
import '../domain/sale_models.dart';
import 'checkout_panel.dart';
import 'widgets/pos_widgets.dart';

/// Caisse : trouver un article et l'ajouter en un geste.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Ouverture de la caisse : tentative d'envoi des ventes en attente.
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(pendingSalesProvider.notifier).sync());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => ref.read(posQueryProvider.notifier).text(value));
  }

  void _add(SellableProduct product) {
    if (product.allowsFractional) {
      // Vente au poids : la quantité est demandée.
      askQuantity(context, product).then((q) {
        if (q != null) ref.read(cartProvider.notifier).add(product, quantity: q);
      });
      return;
    }
    ref.read(cartProvider.notifier).add(product);
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context, title: 'Scanner un article');
    if (code == null || !mounted) return;
    try {
      final businessId = ref.read(activeBusinessProvider)!.businessId;
      final product = await ref.read(salesRepositoryProvider).findByBarcode(businessId, code);
      if (!mounted) return;
      if (product == null) {
        JpOverlays.toast(context, 'Aucun article avec le code $code.', tone: JpTone.warning);
        return;
      }
      HapticFeedback.mediumImpact();
      _add(product);
      JpOverlays.toast(context, '« ${product.name} » ajouté.', tone: JpTone.success);
    } on AppFailure catch (f) {
      if (mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    }
  }

  Future<void> _close() async {
    if (ref.read(cartProvider).isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    final clear = await JpOverlays.confirm(
      context,
      title: 'Quitter la caisse ?',
      message: 'Le panier est conservé : vous le retrouverez en revenant.',
      confirmLabel: 'Quitter',
      cancelLabel: 'Rester',
      icon: Icons.shopping_basket_outlined,
    );
    if (clear && mounted) Navigator.of(context).maybePop();
  }

  Future<void> _openCheckout() =>
      Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const CheckoutScreen()));

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).width >= 840;
    final grid = _ProductGrid(onAdd: _add);
    final cart = ref.watch(cartProvider);
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';

    final searchBar = Padding(
      padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.xs, JpSpacing.gutter, 0),
      child: JpTextField(
        controller: _search,
        hint: 'Rechercher un article…',
        prefixIcon: Icons.search_rounded,
        textInputAction: TextInputAction.search,
        onChanged: _onSearch,
        suffix: IconButton(
          tooltip: _search.text.isEmpty ? 'Scanner' : 'Effacer',
          icon: Icon(_search.text.isEmpty ? Icons.qr_code_scanner_rounded : Icons.close_rounded),
          onPressed: _search.text.isEmpty
              ? _scan
              : () {
                  _search.clear();
                  _onSearch('');
                },
        ),
      ),
    );

    final products = Column(
      children: [
        searchBar,
        const _Filters(),
        const PendingSalesBanner(),
        Expanded(child: grid),
      ],
    );

    return PopScope(
      canPop: cart.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(tooltip: 'Fermer la caisse', icon: const Icon(Icons.close_rounded), onPressed: _close),
          title: const Text('Nouvelle vente'),
          actions: [
            const _LocationButton(),
            IconButton(
              tooltip: 'Historique des ventes',
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: () => context.push(Routes.salesHistory),
            ),
          ],
        ),
        body: isTablet
            ? Row(
                children: [
                  Expanded(flex: 3, child: products),
                  VerticalDivider(width: 1, color: context.palette.border),
                  const SizedBox(width: 420, child: CheckoutPanel(embedded: true)),
                ],
              )
            : products,
        bottomNavigationBar: isTablet ? null : _CartBar(cart: cart, currency: currency, onCheckout: _openCheckout),
      ),
    );
  }
}

class _LocationButton extends ConsumerWidget {
  const _LocationButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(locationsProvider).value ?? const [];
    if (locations.length < 2) return const SizedBox.shrink();
    final current = ref.watch(posLocationProvider);
    return PopupMenuButton<String>(
      tooltip: 'Emplacement de vente',
      icon: const Icon(Icons.storefront_outlined),
      initialValue: current,
      onSelected: (id) => ref.read(posLocationProvider.notifier).select(id),
      itemBuilder: (_) => [
        for (final l in locations) CheckedPopupMenuItem(value: l.id, checked: l.id == current, child: Text(l.name)),
      ],
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(posQueryProvider);
    final notifier = ref.read(posQueryProvider.notifier);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final hasFavorites = ref.watch(favoritesProvider).isNotEmpty;
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.md),
        children: [
          ChoiceChip(
            label: const Text('Tout'),
            selected: !query.favoritesOnly && query.categoryId == null,
            onSelected: (_) => notifier.category(null),
          ),
          if (hasFavorites) ...[
            const SizedBox(width: JpSpacing.sm),
            ChoiceChip(
              avatar: const Icon(Icons.star_rounded, size: 16),
              label: const Text('Favoris'),
              selected: query.favoritesOnly,
              onSelected: (_) => notifier.favorites(),
            ),
          ],
          for (final c in categories) ...[
            const SizedBox(width: JpSpacing.sm),
            ChoiceChip(
              label: Text(c.name),
              selected: query.categoryId == c.id,
              onSelected: (v) => notifier.category(v ? c.id : null),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductGrid extends ConsumerWidget {
  const _ProductGrid({required this.onAdd});

  final ValueChanged<SellableProduct> onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final catalog = ref.watch(posCatalogProvider);
    final cart = ref.watch(cartProvider);
    final favorites = ref.watch(favoritesProvider);
    final query = ref.watch(posQueryProvider);
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1100 ? 5 : (width >= 840 ? 3 : (width >= 600 ? 4 : 2));

    return JpAsyncView<PosCatalog>(
      value: catalog,
      onRetry: () => ref.invalidate(posCatalogProvider),
      loading: JpShimmer(
        child: GridView.count(
          crossAxisCount: columns,
          padding: const EdgeInsets.all(JpSpacing.gutter),
          mainAxisSpacing: JpSpacing.md,
          crossAxisSpacing: JpSpacing.md,
          childAspectRatio: 1.32,
          physics: const NeverScrollableScrollPhysics(),
          children: List.generate(8, (_) => const JpSkeleton(radius: JpRadius.lg)),
        ),
      ),
      data: (data) {
        if (data.products.isEmpty) {
          return JpEmptyState(
            icon: query.favoritesOnly ? Icons.star_outline_rounded : Icons.search_off_rounded,
            tone: JpTone.neutral,
            title: query.favoritesOnly
                ? 'Aucun favori'
                : query.isDefault
                ? 'Aucun article à vendre'
                : 'Aucun résultat',
            message: query.favoritesOnly
                ? 'Appuyez longuement sur un article pour l’ajouter aux favoris.'
                : query.isDefault
                ? 'Ajoutez des produits au catalogue pour commencer à vendre.'
                : 'Essayez un autre nom ou scannez le code-barres.',
          );
        }
        return Column(
          children: [
            if (data.fromCache)
              Padding(
                padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, 0, JpSpacing.gutter, JpSpacing.sm),
                child: JpBanner(
                  tone: JpTone.warning,
                  icon: Icons.cloud_off_rounded,
                  message: 'Hors ligne : catalogue enregistré sur le téléphone. Les ventes seront envoyées plus tard.',
                ),
              ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, 0, JpSpacing.gutter, JpSpacing.xxl),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: JpSpacing.md,
                  crossAxisSpacing: JpSpacing.md,
                  childAspectRatio: 1.32,
                ),
                itemCount: data.products.length,
                itemBuilder: (context, i) {
                  final product = data.products[i];
                  return PosProductCard(
                    product: product,
                    currency: currency,
                    inCart: cart.quantityOf(product.id),
                    favorite: favorites.contains(product.id),
                    onTap: () => onAdd(product),
                    onLongPress: () {
                      final wasFavorite = favorites.contains(product.id);
                      ref.read(favoritesProvider.notifier).toggle(product.id);
                      JpOverlays.toast(
                        context,
                        wasFavorite ? 'Retiré des favoris.' : 'Ajouté aux favoris.',
                        icon: wasFavorite ? Icons.star_outline_rounded : Icons.star_rounded,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    ).withBackground(p.background);
  }
}

extension on Widget {
  Widget withBackground(Color color) => ColoredBox(color: color, child: this);
}

/// Barre de panier fixe : résumé + accès à l'encaissement.
class _CartBar extends StatelessWidget {
  const _CartBar({required this.cart, required this.currency, required this.onCheckout});

  final Cart cart;
  final String currency;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final count = cart.lines.length;
    return AnimatedSwitcher(
      duration: JpMotion.base,
      transitionBuilder: (child, a) => SizeTransition(sizeFactor: a, alignment: Alignment.topCenter, child: child),
      child: cart.isEmpty
          ? const SizedBox(key: ValueKey('empty'), width: double.infinity)
          : DecoratedBox(
              key: const ValueKey('cart'),
              decoration: BoxDecoration(
                color: p.surface,
                border: Border(top: BorderSide(color: p.border)),
                boxShadow: JpShadows.lg(p.shadow),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.md, JpSpacing.gutter, JpSpacing.md),
                  child: Material(
                    color: p.brand,
                    borderRadius: JpRadius.all(JpRadius.md),
                    child: InkWell(
                      borderRadius: JpRadius.all(JpRadius.md),
                      onTap: onCheckout,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.md),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: JpSpacing.sm, vertical: 2),
                              decoration: BoxDecoration(
                                color: p.textOnBrand.withValues(alpha: 0.15),
                                borderRadius: JpRadius.all(JpRadius.pill),
                              ),
                              child: Text('$count', style: JpTypography.label.copyWith(color: p.textOnBrand)),
                            ),
                            const SizedBox(width: JpSpacing.md),
                            Expanded(
                              child: Text('Encaisser', style: JpTypography.titleSmall.copyWith(color: p.textOnBrand)),
                            ),
                            JpAmount(
                              cart.total,
                              currency: currency,
                              style: JpTypography.titleSmall,
                              color: p.textOnBrand,
                            ),
                            const SizedBox(width: JpSpacing.sm),
                            Icon(Icons.arrow_forward_rounded, color: p.textOnBrand),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
