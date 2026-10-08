import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/pagination/paged.dart';
import '../../business/application/workspace_controller.dart';
import '../../business/data/business_repository.dart';
import '../../dashboard/application/dashboard_controller.dart';
import '../../inventory/data/inventory_repository.dart';
import '../data/products_repository.dart';
import '../domain/catalog_models.dart';

/// Filtres de la liste (réinitialisés au changement d'entreprise).
final productFilterProvider = NotifierProvider<ProductFilterNotifier, ProductFilter>(ProductFilterNotifier.new);

class ProductFilterNotifier extends Notifier<ProductFilter> {
  @override
  ProductFilter build() {
    ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    return const ProductFilter();
  }

  void search(String query) => state = state.copyWith(query: query.trim());

  void category(String? categoryId) => state = state.copyWith(categoryId: () => categoryId);

  void status(ProductStatusFilter status) => state = state.copyWith(status: status);
}

/// Page courante de la liste du catalogue.
typedef ProductPage = Paged<Product>;

/// Liste paginée (jamais de catalogue entier en mémoire : pages de 30).
final productListProvider = AsyncNotifierProvider.autoDispose<ProductListController, ProductPage>(
  ProductListController.new,
);

class ProductListController extends AsyncNotifier<ProductPage> {
  static const pageSize = 30;

  @override
  Future<ProductPage> build() async {
    final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    final filter = ref.watch(productFilterProvider);
    if (businessId == null) return const ProductPage(items: [], hasMore: false);
    final items = await ref
        .read(productsRepositoryProvider)
        .fetchProducts(businessId, filter, offset: 0, limit: pageSize);
    return ProductPage(items: items, hasMore: items.length == pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    final businessId = ref.read(activeBusinessProvider)?.businessId;
    if (current == null || businessId == null || !current.hasMore || current.loadingMore || state.isLoading) return;
    state = AsyncData(current.copyWith(loadingMore: true, loadMoreError: () => null));
    try {
      final next = await ref
          .read(productsRepositoryProvider)
          .fetchProducts(businessId, ref.read(productFilterProvider), offset: current.items.length, limit: pageSize);
      if (!ref.mounted) return;
      // Les produits ajoutés entre-temps peuvent décaler la pagination :
      // on déduplique par identifiant.
      final seen = {for (final p in current.items) p.id};
      state = AsyncData(
        ProductPage(items: [...current.items, ...next.where((p) => seen.add(p.id))], hasMore: next.length == pageSize),
      );
    } catch (e) {
      if (ref.mounted) state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: () => e));
    }
  }
}

/// Catégories actives de l'entreprise.
final categoriesProvider = FutureProvider.autoDispose<List<Category>>((ref) {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  if (businessId == null) return Future.value(const []);
  return ref.watch(productsRepositoryProvider).fetchCategories(businessId);
});

final productDetailProvider = FutureProvider.autoDispose.family<Product, String>(
  (ref, id) => ref.watch(productsRepositoryProvider).fetchProduct(id),
);

final productActionsProvider = Provider<ProductActions>(ProductActions.new);

/// Écritures du catalogue. Chaque action passe par le repository (la base
/// décide) puis rafraîchit ce qui en dépend.
class ProductActions {
  ProductActions(this._ref);

  final Ref _ref;

  ProductsRepository get _products => _ref.read(productsRepositoryProvider);

  String get _businessId => _ref.read(activeBusinessProvider)!.businessId;

  void _refresh([String? productId]) {
    _ref.invalidate(productListProvider);
    _ref.invalidate(dashboardProvider);
    if (productId != null) _ref.invalidate(productDetailProvider(productId));
  }

  /// Création + stock d'ouverture facultatif (emplacement par défaut).
  Future<ProductSummary> create(NewProduct product, {num? initialStock, Uint8List? image, String? imageMime}) async {
    final created = await _products.createProduct(_businessId, product);
    try {
      if (initialStock != null && initialStock > 0 && created.trackStock) {
        final locationId = await _ref.read(businessRepositoryProvider).fetchDefaultLocationId(_businessId);
        await _ref
            .read(inventoryRepositoryProvider)
            .setInitialStock(
              businessId: _businessId,
              productId: created.id,
              locationId: locationId,
              quantity: initialStock,
            );
      }
      if (image != null && imageMime != null) {
        await _products.uploadImage(_businessId, await _products.fetchProduct(created.id), image, mimeType: imageMime);
      }
    } finally {
      // Le produit existe même si le stock ou la photo échouent : la liste
      // doit le montrer, l'erreur est remontée à l'écran.
      _refresh(created.id);
    }
    return created;
  }

  Future<Product> update(Product product, Map<String, Object?> changes, {int? costPrice}) async {
    var updated = product;
    if (changes.isNotEmpty) updated = await _products.updateProduct(product.id, changes);
    if (costPrice != null && costPrice != product.costPrice) await _products.setCost(product.id, costPrice);
    _refresh(product.id);
    return updated;
  }

  Future<void> setArchived(Product product, {required bool archived}) async {
    await _products.setArchived(product.id, archived: archived);
    _refresh(product.id);
  }

  Future<void> uploadImage(Product product, Uint8List bytes, String mimeType) async {
    await _products.uploadImage(_businessId, product, bytes, mimeType: mimeType);
    _refresh(product.id);
  }

  Future<Category> createCategory(String name) async {
    final category = await _products.createCategory(_businessId, name);
    _ref.invalidate(categoriesProvider);
    return category;
  }

  Future<void> renameCategory(Category category, String name) async {
    await _products.renameCategory(category.id, name);
    _ref.invalidate(categoriesProvider);
    _ref.invalidate(productListProvider);
  }

  Future<void> archiveCategory(Category category) async {
    await _products.archiveCategory(category.id);
    _ref.invalidate(categoriesProvider);
    if (_ref.read(productFilterProvider).categoryId == category.id) {
      _ref.read(productFilterProvider.notifier).category(null);
    }
  }

  Future<Product?> findByBarcode(String code) => _products.findByBarcode(_businessId, code);

  String imageUrl(String path) => _products.publicImageUrl(path);
}
