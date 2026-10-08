import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/pagination/paged.dart';
import '../../business/application/workspace_controller.dart';
import '../../dashboard/application/dashboard_controller.dart';
import '../../products/application/catalog_providers.dart';
import '../data/inventory_repository.dart';
import '../domain/inventory_models.dart';

/// Emplacements actifs (par défaut en premier).
final locationsProvider = FutureProvider.autoDispose<List<StockLocation>>((ref) {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  if (businessId == null) return Future.value(const []);
  return ref.watch(inventoryRepositoryProvider).fetchLocations(businessId);
});

/// Filtre de l'onglet Stock : état + emplacement (`null` = tous).
class StockView {
  const StockView({this.filter = StockFilter.all, this.locationId});

  final StockFilter filter;
  final String? locationId;

  @override
  bool operator ==(Object other) => other is StockView && other.filter == filter && other.locationId == locationId;

  @override
  int get hashCode => Object.hash(filter, locationId);
}

final stockViewProvider = NotifierProvider<StockViewNotifier, StockView>(StockViewNotifier.new);

class StockViewNotifier extends Notifier<StockView> {
  @override
  StockView build() {
    ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    return const StockView();
  }

  void filter(StockFilter filter) => state = StockView(filter: filter, locationId: state.locationId);

  void location(String? locationId) => state = StockView(filter: state.filter, locationId: locationId);
}

final stockListProvider = AsyncNotifierProvider.autoDispose<StockListController, Paged<StockRow>>(
  StockListController.new,
);

class StockListController extends AsyncNotifier<Paged<StockRow>> {
  static const pageSize = 40;

  @override
  Future<Paged<StockRow>> build() async {
    final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    final view = ref.watch(stockViewProvider);
    if (businessId == null) return const Paged(items: [], hasMore: false);
    final items = await ref
        .read(inventoryRepositoryProvider)
        .fetchStock(businessId, filter: view.filter, locationId: view.locationId, offset: 0, limit: pageSize);
    // `list_low_stock` renvoie tout d'un coup : pas de page suivante.
    return Paged(items: items, hasMore: view.filter != StockFilter.low && items.length == pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    final businessId = ref.read(activeBusinessProvider)?.businessId;
    if (current == null || businessId == null || !current.hasMore || current.loadingMore || state.isLoading) return;
    final view = ref.read(stockViewProvider);
    state = AsyncData(current.copyWith(loadingMore: true, loadMoreError: () => null));
    try {
      final next = await ref
          .read(inventoryRepositoryProvider)
          .fetchStock(
            businessId,
            filter: view.filter,
            locationId: view.locationId,
            offset: current.items.length,
            limit: pageSize,
          );
      if (ref.mounted) {
        state = AsyncData(current.append(next, pageSize: pageSize, keyOf: (r) => '${r.productId}/${r.locationId}'));
      }
    } catch (e) {
      if (ref.mounted) state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: () => e));
    }
  }
}

/// Stock d'un produit, emplacement par emplacement.
final productStockProvider = FutureProvider.autoDispose.family<List<LocationStock>, String>((ref, productId) {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  if (businessId == null) return Future.value(const []);
  return ref.watch(inventoryRepositoryProvider).fetchProductStock(businessId, productId);
});

/// Historique des mouvements d'un produit (paginé, plus récent d'abord).
final movementsProvider = AsyncNotifierProvider.family<MovementsController, Paged<StockMovement>, String>(
  MovementsController.new,
  isAutoDispose: true,
);

class MovementsController extends AsyncNotifier<Paged<StockMovement>> {
  MovementsController(this.productId);

  final String productId;
  static const pageSize = 30;

  @override
  Future<Paged<StockMovement>> build() async {
    final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    if (businessId == null) return const Paged(items: [], hasMore: false);
    final items = await ref
        .read(inventoryRepositoryProvider)
        .fetchMovements(businessId, productId, offset: 0, limit: pageSize);
    return Paged(items: items, hasMore: items.length == pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    final businessId = ref.read(activeBusinessProvider)?.businessId;
    if (current == null || businessId == null || !current.hasMore || current.loadingMore || state.isLoading) return;
    state = AsyncData(current.copyWith(loadingMore: true, loadMoreError: () => null));
    try {
      final next = await ref
          .read(inventoryRepositoryProvider)
          .fetchMovements(businessId, productId, offset: current.items.length, limit: pageSize);
      if (ref.mounted) state = AsyncData(current.append(next, pageSize: pageSize, keyOf: (m) => m.id));
    } catch (e) {
      if (ref.mounted) state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: () => e));
    }
  }
}

final inventoryActionsProvider = Provider<InventoryActions>(InventoryActions.new);

/// Écritures de stock (RPC uniquement) + rafraîchissement de ce qui en dépend.
class InventoryActions {
  InventoryActions(this._ref);

  final Ref _ref;

  InventoryRepository get _repo => _ref.read(inventoryRepositoryProvider);

  String get _businessId => _ref.read(activeBusinessProvider)!.businessId;

  void _refresh(String productId) {
    _ref.invalidate(productStockProvider(productId));
    _ref.invalidate(movementsProvider(productId));
    _ref.invalidate(stockListProvider);
    _ref.invalidate(productDetailProvider(productId));
    _ref.invalidate(productListProvider);
    _ref.invalidate(dashboardProvider);
  }

  Future<void> adjust({
    required String productId,
    required String locationId,
    required MovementType type,
    required num quantity,
    String? reason,
  }) async {
    await _repo.adjust(
      businessId: _businessId,
      productId: productId,
      locationId: locationId,
      type: type,
      quantity: quantity,
      reason: reason,
    );
    _refresh(productId);
  }

  Future<void> count({
    required String productId,
    required String locationId,
    required num counted,
    String? reason,
  }) async {
    await _repo.count(
      businessId: _businessId,
      productId: productId,
      locationId: locationId,
      countedQuantity: counted,
      reason: reason,
    );
    _refresh(productId);
  }

  Future<void> transfer({
    required String productId,
    required String fromLocationId,
    required String toLocationId,
    required num quantity,
    String? reason,
  }) async {
    await _repo.transfer(
      businessId: _businessId,
      productId: productId,
      fromLocationId: fromLocationId,
      toLocationId: toLocationId,
      quantity: quantity,
      reason: reason,
    );
    _refresh(productId);
  }
}
