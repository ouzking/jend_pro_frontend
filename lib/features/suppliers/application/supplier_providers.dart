import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/pagination/paged.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../data/suppliers_repository.dart';
import '../domain/supplier_models.dart';

String? _bid(Ref ref) => ref.read(activeBusinessProvider)?.businessId;

class SupplierQuery {
  const SupplierQuery({this.text = '', this.segment = SupplierSegment.all});

  final String text;
  final SupplierSegment segment;

  @override
  bool operator ==(Object other) => other is SupplierQuery && other.text == text && other.segment == segment;

  @override
  int get hashCode => Object.hash(text, segment);
}

final supplierQueryProvider = NotifierProvider<SupplierQueryNotifier, SupplierQuery>(SupplierQueryNotifier.new);

class SupplierQueryNotifier extends Notifier<SupplierQuery> {
  @override
  SupplierQuery build() {
    ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    return const SupplierQuery();
  }

  void search(String text) => state = SupplierQuery(text: text.trim(), segment: state.segment);

  void segment(SupplierSegment s) => state = SupplierQuery(text: state.text, segment: s);
}

/// Dettes fournisseurs (vide sans `purchases.read`).
final supplierBalancesProvider = FutureProvider.autoDispose<Map<String, SupplierBalance>>((ref) {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  if (businessId == null || !ref.watch(permissionsProvider).can(Permission.purchasesRead)) {
    return Future.value(const {});
  }
  return ref.watch(suppliersRepositoryProvider).fetchBalances(businessId);
});

final supplierListProvider = AsyncNotifierProvider.autoDispose<SupplierListController, Paged<Supplier>>(
  SupplierListController.new,
);

class SupplierListController extends AsyncNotifier<Paged<Supplier>> {
  static const pageSize = 30;

  Future<List<Supplier>> _fetch(String businessId, SupplierQuery q, int offset) async {
    final repo = ref.read(suppliersRepositoryProvider);
    List<String>? ids;
    if (q.segment == SupplierSegment.toPay) {
      ids = (await repo.fetchBalances(businessId, owedOnly: true)).keys.toList();
      if (ids.isEmpty) return const [];
    }
    return repo.fetchSuppliers(
      businessId,
      query: q.text,
      segment: q.segment,
      ids: ids,
      offset: offset,
      limit: pageSize,
    );
  }

  @override
  Future<Paged<Supplier>> build() async {
    final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    final q = ref.watch(supplierQueryProvider);
    if (businessId == null) return const Paged(items: [], hasMore: false);
    final items = await _fetch(businessId, q, 0);
    return Paged(items: items, hasMore: items.length == pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    final businessId = _bid(ref);
    if (current == null || businessId == null || !current.hasMore || current.loadingMore || state.isLoading) return;
    state = AsyncData(current.copyWith(loadingMore: true, loadMoreError: () => null));
    try {
      final next = await _fetch(businessId, ref.read(supplierQueryProvider), current.items.length);
      if (ref.mounted) state = AsyncData(current.append(next, pageSize: pageSize, keyOf: (s) => s.id));
    } catch (e) {
      if (ref.mounted) state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: () => e));
    }
  }
}

final supplierDetailProvider = FutureProvider.autoDispose.family<Supplier, String>(
  (ref, id) => ref.watch(suppliersRepositoryProvider).fetchSupplier(id),
);

final supplierProductsProvider = FutureProvider.autoDispose.family<List<SupplierProduct>, String>((ref, id) {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  if (businessId == null) return Future.value(const []);
  return ref.watch(suppliersRepositoryProvider).fetchProducts(businessId, id);
});

final supplierPurchasesProvider = FutureProvider.autoDispose.family<List<PurchaseSummary>, String>((ref, id) {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  if (businessId == null || !ref.watch(permissionsProvider).can(Permission.purchasesRead)) {
    return Future.value(const []);
  }
  return ref.watch(suppliersRepositoryProvider).fetchPurchases(businessId, id);
});

final supplierActionsProvider = Provider<SupplierActions>(SupplierActions.new);

class SupplierActions {
  SupplierActions(this._ref);

  final Ref _ref;

  SuppliersRepository get _repo => _ref.read(suppliersRepositoryProvider);

  String get _businessId => _bid(_ref)!;

  void _refresh([String? id]) {
    _ref.invalidate(supplierListProvider);
    _ref.invalidate(supplierBalancesProvider);
    if (id != null) {
      _ref.invalidate(supplierDetailProvider(id));
      _ref.invalidate(supplierProductsProvider(id));
    }
  }

  Future<Supplier> create(Map<String, Object?> fields) async {
    final s = await _repo.create(_businessId, fields);
    _refresh(s.id);
    return s;
  }

  Future<void> update(Supplier s, Map<String, Object?> changes) async {
    if (changes.isNotEmpty) await _repo.update(s.id, changes);
    _refresh(s.id);
  }

  Future<void> setArchived(Supplier s, {required bool archived}) async {
    await _repo.setArchived(s.id, archived: archived);
    _refresh(s.id);
  }

  Future<void> linkProduct(String supplierId, String productId, {String? sku}) async {
    await _repo.linkProduct(_businessId, supplierId, productId, supplierSku: sku);
    _refresh(supplierId);
  }

  Future<void> updateSku(String supplierId, String productId, String? sku) async {
    await _repo.updateSku(supplierId, productId, sku);
    _refresh(supplierId);
  }

  Future<void> unlinkProduct(String supplierId, String productId) async {
    await _repo.unlinkProduct(supplierId, productId);
    _refresh(supplierId);
  }
}
