import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/pagination/paged.dart';
import '../../../core/storage/preferences.dart';
import '../../business/application/workspace_controller.dart';
import '../../dashboard/application/dashboard_controller.dart';
import '../../inventory/application/inventory_providers.dart';
import '../../inventory/domain/inventory_models.dart';
import '../../products/application/catalog_providers.dart';
import '../data/offline_sales_queue.dart';
import '../data/sales_repository.dart';
import '../domain/cart.dart';
import '../domain/sale_models.dart';

String? _businessId(Ref ref) => ref.read(activeBusinessProvider)?.businessId;

// ---------------------------------------------------------------------------
// Emplacement de vente
// ---------------------------------------------------------------------------

/// Emplacement de la caisse (par défaut : emplacement principal).
final posLocationProvider = NotifierProvider<PosLocationNotifier, String?>(PosLocationNotifier.new);

class PosLocationNotifier extends Notifier<String?> {
  @override
  String? build() {
    final locations = ref.watch(locationsProvider).value ?? const <StockLocation>[];
    final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    if (businessId == null || locations.isEmpty) return null;
    final saved = ref.read(sharedPreferencesProvider).getString('pos_location:$businessId');
    return locations.any((l) => l.id == saved) ? saved : locations.first.id;
  }

  Future<void> select(String locationId) async {
    final businessId = ref.read(activeBusinessProvider)?.businessId;
    if (businessId != null) await ref.read(sharedPreferencesProvider).setString('pos_location:$businessId', locationId);
    state = locationId;
  }
}

// ---------------------------------------------------------------------------
// Panier
// ---------------------------------------------------------------------------

/// Panier en cours (conservé si la caisse est refermée par erreur, vidé au
/// changement d'entreprise et après une vente).
final cartProvider = NotifierProvider<CartNotifier, Cart>(CartNotifier.new);

class CartNotifier extends Notifier<Cart> {
  @override
  Cart build() {
    ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    return const Cart();
  }

  void add(SellableProduct product, {num quantity = 1}) => state = state.add(product, quantity: quantity);

  void setQuantity(String productId, num quantity) => state = state.setQuantity(productId, quantity);

  void setLineDiscount(String productId, int discount) => state = state.setLineDiscount(productId, discount);

  void remove(String productId) => state = state.remove(productId);

  void setGlobalDiscount(int discount) => state = state.setGlobalDiscount(discount);

  void setCustomer(SaleCustomer? customer) => state = state.setCustomer(customer);

  void setNotes(String? notes) => state = state.setNotes(notes);

  void clear() => state = const Cart();
}

// ---------------------------------------------------------------------------
// Favoris (préférence de l'appareil, par entreprise)
// ---------------------------------------------------------------------------

final favoritesProvider = NotifierProvider<FavoritesNotifier, Set<String>>(FavoritesNotifier.new);

class FavoritesNotifier extends Notifier<Set<String>> {
  String? get _key {
    final id = ref.read(activeBusinessProvider)?.businessId;
    return id == null ? null : 'pos_favorites:$id';
  }

  @override
  Set<String> build() {
    ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    final key = _key;
    if (key == null) return const {};
    return {...?ref.read(sharedPreferencesProvider).getStringList(key)};
  }

  Future<void> toggle(String productId) async {
    final next = {...state};
    next.contains(productId) ? next.remove(productId) : next.add(productId);
    state = next;
    final key = _key;
    if (key != null) await ref.read(sharedPreferencesProvider).setStringList(key, next.toList());
  }
}

// ---------------------------------------------------------------------------
// Grille de produits (avec cache hors ligne)
// ---------------------------------------------------------------------------

class PosQuery {
  const PosQuery({this.text = '', this.categoryId, this.favoritesOnly = false});

  final String text;
  final String? categoryId;
  final bool favoritesOnly;

  bool get isDefault => text.isEmpty && categoryId == null && !favoritesOnly;

  @override
  bool operator ==(Object other) =>
      other is PosQuery && other.text == text && other.categoryId == categoryId && other.favoritesOnly == favoritesOnly;

  @override
  int get hashCode => Object.hash(text, categoryId, favoritesOnly);
}

final posQueryProvider = NotifierProvider<PosQueryNotifier, PosQuery>(PosQueryNotifier.new);

class PosQueryNotifier extends Notifier<PosQuery> {
  @override
  PosQuery build() => const PosQuery();

  void text(String text) => state = PosQuery(text: text.trim(), categoryId: state.categoryId);

  void category(String? id) => state = PosQuery(text: state.text, categoryId: id);

  void favorites() => state = const PosQuery(favoritesOnly: true);

  void reset() => state = const PosQuery();
}

/// Résultat de la grille + indicateur « données en cache » (hors ligne).
class PosCatalog {
  const PosCatalog({required this.products, this.fromCache = false});

  final List<SellableProduct> products;
  final bool fromCache;
}

final posCatalogProvider = FutureProvider.autoDispose<PosCatalog>((ref) async {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  final query = ref.watch(posQueryProvider);
  final favorites = ref.watch(favoritesProvider);
  if (businessId == null) return const PosCatalog(products: []);
  final repo = ref.watch(salesRepositoryProvider);
  final prefs = ref.read(sharedPreferencesProvider);
  final cacheKey = 'pos_catalog:$businessId';

  List<SellableProduct> fromCache() {
    final raw = prefs.getString(cacheKey);
    if (raw == null) return const [];
    final all = (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(SellableProduct.fromRow).toList();
    final t = query.text.toLowerCase();
    return all
        .where((p) => !query.favoritesOnly || favorites.contains(p.id))
        .where((p) => query.categoryId == null || p.categoryId == query.categoryId)
        .where((p) => t.isEmpty || p.name.toLowerCase().contains(t) || p.barcode == t)
        .toList();
  }

  try {
    if (query.favoritesOnly && favorites.isEmpty) return const PosCatalog(products: []);
    final products = await repo.fetchSellable(
      businessId,
      query: query.text,
      categoryId: query.categoryId,
      ids: query.favoritesOnly ? favorites.toList() : null,
    );
    if (query.isDefault) {
      // Le catalogue complet (≤ 200) sert de secours hors ligne.
      await prefs.setString(cacheKey, jsonEncode([for (final p in products) p.toJson()]));
    }
    return PosCatalog(products: products);
  } on AppFailure catch (f) {
    if (f.kind != FailureKind.network) rethrow;
    final cached = fromCache();
    if (cached.isEmpty && query.isDefault) rethrow;
    return PosCatalog(products: cached, fromCache: true);
  }
});

// ---------------------------------------------------------------------------
// Envoi des ventes + file hors ligne
// ---------------------------------------------------------------------------

final offlineQueueProvider = Provider<OfflineSalesQueue>(
  (ref) => OfflineSalesQueue(ref.watch(sharedPreferencesProvider)),
);

/// Ventes en attente pour l'entreprise active.
final pendingSalesProvider = NotifierProvider<PendingSalesNotifier, List<PendingSale>>(PendingSalesNotifier.new);

class PendingSalesNotifier extends Notifier<List<PendingSale>> {
  bool _syncing = false;

  @override
  List<PendingSale> build() {
    final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    if (businessId == null) return const [];
    return ref.read(offlineQueueProvider).forBusiness(businessId);
  }

  void _reload() {
    final businessId = _businessId(ref);
    state = businessId == null ? const [] : ref.read(offlineQueueProvider).forBusiness(businessId);
  }

  Future<void> enqueue(PendingSale sale) async {
    await ref.read(offlineQueueProvider).add(sale);
    _reload();
  }

  Future<void> discard(PendingSale sale) async {
    await ref.read(offlineQueueProvider).remove(sale.request.clientReference);
    _reload();
  }

  /// Rejoue les ventes dans l'ordre. S'arrête à la première coupure réseau ;
  /// un refus métier marque la vente (décision de l'utilisateur) et on passe
  /// à la suivante. Renvoie le nombre de ventes synchronisées.
  Future<int> sync({bool includeBlocked = false}) async {
    if (_syncing) return 0;
    _syncing = true;
    var synced = 0;
    try {
      final queue = ref.read(offlineQueueProvider);
      for (final pending in [...state]) {
        if (pending.blocked && !includeBlocked) continue;
        try {
          await ref.read(salesRepositoryProvider).createSale(pending.request);
          await queue.remove(pending.request.clientReference);
          synced++;
        } on AppFailure catch (f) {
          if (f.kind == FailureKind.network) break;
          await queue.update(pending.withError(f.message));
        }
      }
    } finally {
      _syncing = false;
      if (ref.mounted) _reload();
    }
    if (synced > 0) _refreshAfterSale(ref);
    return synced;
  }
}

/// Issue d'un encaissement.
sealed class SaleOutcome {
  const SaleOutcome();
}

/// Vente enregistrée par le serveur.
class SaleRecorded extends SaleOutcome {
  const SaleRecorded(this.saleId, this.settlement);

  final String saleId;
  final Settlement settlement;
}

/// Pas de réseau : vente gardée sur l'appareil, envoyée plus tard.
class SaleQueued extends SaleOutcome {
  const SaleQueued(this.pending, this.settlement);

  final PendingSale pending;
  final Settlement settlement;
}

final saleSubmitterProvider = Provider<SaleSubmitter>(SaleSubmitter.new);

class SaleSubmitter {
  SaleSubmitter(this._ref);

  final Ref _ref;

  /// Valide le panier. Une erreur **métier** (stock, crédit, droits…) remonte
  /// en `AppFailure` : le panier est conservé pour correction.
  Future<SaleOutcome> submit({required Cart cart, required Settlement settlement, required String locationId}) async {
    final businessId = _businessId(_ref)!;
    final request = SaleRequest(
      businessId: businessId,
      // Générée une fois, à la validation : base de l'idempotence.
      clientReference: const Uuid().v4(),
      locationId: locationId,
      items: [for (final l in cart.lines) l.toJson()],
      payments: [for (final p in settlement.payments) p.toJson()],
      customerId: cart.customer?.id,
      discount: cart.globalDiscount,
      notes: cart.notes,
    );
    try {
      final saleId = await _ref.read(salesRepositoryProvider).createSale(request);
      _ref.read(cartProvider.notifier).clear();
      _refreshAfterSale(_ref);
      return SaleRecorded(saleId, settlement);
    } on AppFailure catch (f) {
      if (f.kind != FailureKind.network) rethrow;
      final pending = PendingSale(request: request, createdAt: DateTime.now(), total: cart.total);
      await _ref.read(pendingSalesProvider.notifier).enqueue(pending);
      _ref.read(cartProvider.notifier).clear();
      return SaleQueued(pending, settlement);
    }
  }
}

void _refreshAfterSale(Ref ref) {
  ref.invalidate(dashboardProvider);
  ref.invalidate(posCatalogProvider);
  ref.invalidate(productListProvider);
  ref.invalidate(stockListProvider);
  ref.invalidate(salesHistoryProvider);
}

// ---------------------------------------------------------------------------
// Historique et détail
// ---------------------------------------------------------------------------

final saleDetailProvider = FutureProvider.autoDispose.family<Sale, String>(
  (ref, id) => ref.watch(salesRepositoryProvider).fetchSale(id),
);

final salesHistoryProvider = AsyncNotifierProvider.autoDispose<SalesHistoryController, Paged<Sale>>(
  SalesHistoryController.new,
);

class SalesHistoryController extends AsyncNotifier<Paged<Sale>> {
  static const pageSize = 30;

  @override
  Future<Paged<Sale>> build() async {
    final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    if (businessId == null) return const Paged(items: [], hasMore: false);
    final items = await ref.read(salesRepositoryProvider).fetchSales(businessId, offset: 0, limit: pageSize);
    return Paged(items: items, hasMore: items.length == pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    final businessId = _businessId(ref);
    if (current == null || businessId == null || !current.hasMore || current.loadingMore || state.isLoading) return;
    state = AsyncData(current.copyWith(loadingMore: true, loadMoreError: () => null));
    try {
      final next = await ref
          .read(salesRepositoryProvider)
          .fetchSales(businessId, offset: current.items.length, limit: pageSize);
      if (ref.mounted) state = AsyncData(current.append(next, pageSize: pageSize, keyOf: (s) => s.id));
    } catch (e) {
      if (ref.mounted) state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: () => e));
    }
  }
}
