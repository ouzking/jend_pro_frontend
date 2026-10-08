import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/payment_method.dart';
import '../../../core/pagination/paged.dart';
import '../../business/application/workspace_controller.dart';
import '../../business/data/business_repository.dart';
import '../../dashboard/application/dashboard_controller.dart';
import '../../inventory/application/inventory_providers.dart';
import '../../products/application/catalog_providers.dart';
import '../../suppliers/application/supplier_providers.dart';
import '../../suppliers/domain/supplier_models.dart';
import '../data/purchases_repository.dart';
import '../domain/purchase_models.dart';

String? _bid(Ref ref) => ref.read(activeBusinessProvider)?.businessId;

final purchaseSegmentProvider = NotifierProvider<PurchaseSegmentNotifier, PurchaseSegment>(PurchaseSegmentNotifier.new);

class PurchaseSegmentNotifier extends Notifier<PurchaseSegment> {
  @override
  PurchaseSegment build() => PurchaseSegment.all;

  void select(PurchaseSegment s) => state = s;
}

final purchaseListProvider = AsyncNotifierProvider.autoDispose<PurchaseListController, Paged<PurchaseSummary>>(
  PurchaseListController.new,
);

class PurchaseListController extends AsyncNotifier<Paged<PurchaseSummary>> {
  static const pageSize = 30;

  @override
  Future<Paged<PurchaseSummary>> build() async {
    final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    final segment = ref.watch(purchaseSegmentProvider);
    if (businessId == null) return const Paged(items: [], hasMore: false);
    final items = await ref
        .read(purchasesRepositoryProvider)
        .fetchPurchases(businessId, segment: segment, offset: 0, limit: pageSize);
    return Paged(items: items, hasMore: items.length == pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    final businessId = _bid(ref);
    if (current == null || businessId == null || !current.hasMore || current.loadingMore || state.isLoading) return;
    state = AsyncData(current.copyWith(loadingMore: true, loadMoreError: () => null));
    try {
      final next = await ref
          .read(purchasesRepositoryProvider)
          .fetchPurchases(
            businessId,
            segment: ref.read(purchaseSegmentProvider),
            offset: current.items.length,
            limit: pageSize,
          );
      if (ref.mounted) state = AsyncData(current.append(next, pageSize: pageSize, keyOf: (x) => x.id));
    } catch (e) {
      if (ref.mounted) state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: () => e));
    }
  }
}

final purchaseDetailProvider = FutureProvider.autoDispose.family<Purchase, String>(
  (ref, id) => ref.watch(purchasesRepositoryProvider).fetchPurchase(id),
);

final purchaseActionsProvider = Provider<PurchaseActions>(PurchaseActions.new);

/// Cycle de vie d'un achat + rafraîchissement (stock, coûts, dettes…).
class PurchaseActions {
  PurchaseActions(this._ref);

  final Ref _ref;

  PurchasesRepository get _repo => _ref.read(purchasesRepositoryProvider);

  String get _businessId => _bid(_ref)!;

  void _refresh(String id, {String? supplierId, bool stock = false}) {
    _ref.invalidate(purchaseListProvider);
    _ref.invalidate(purchaseDetailProvider(id));
    _ref.invalidate(supplierBalancesProvider);
    if (supplierId != null) {
      _ref.invalidate(supplierPurchasesProvider(supplierId));
      _ref.invalidate(supplierProductsProvider(supplierId));
    }
    if (stock) {
      _ref.invalidate(productListProvider);
      _ref.invalidate(stockListProvider);
      _ref.invalidate(dashboardProvider);
    }
  }

  Future<String> save(PurchaseDraft draft, {bool receive = false}) async {
    final id = await _repo.save(_businessId, draft);
    try {
      if (receive) await _repo.receive(id);
    } finally {
      _refresh(id, supplierId: draft.supplier?.id, stock: receive);
    }
    return id;
  }

  Future<void> order(Purchase p) async {
    await _repo.order(p.id);
    _refresh(p.id, supplierId: p.supplierId);
  }

  Future<void> receive(Purchase p) async {
    await _repo.receive(p.id);
    _refresh(p.id, supplierId: p.supplierId, stock: true);
  }

  Future<void> cancel(Purchase p, String reason) async {
    await _repo.cancel(p.id, reason: reason);
    _refresh(p.id, supplierId: p.supplierId);
  }

  Future<void> pay(Purchase p, {required int amount, required PaymentMethod method, String? reference}) async {
    final locationId = await _ref.read(businessRepositoryProvider).fetchDefaultLocationId(_businessId);
    await _repo.recordPayment(p.id, amount: amount, method: method, locationId: locationId, reference: reference);
    _refresh(p.id, supplierId: p.supplierId);
    _ref.invalidate(dashboardProvider);
  }
}

/// Fournisseur pré-choisi depuis sa fiche (« Nouvel achat »).
final supplierForNewPurchaseProvider = FutureProvider.autoDispose.family<Supplier?, String?>((ref, id) {
  if (id == null) return Future.value();
  return ref.watch(supplierDetailProvider(id).future);
});
