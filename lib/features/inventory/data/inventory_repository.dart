import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/inventory_models.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepository(ref.watch(supabaseClientProvider)),
);

/// Stock : lecture directe (`inventory`, `inventory_movements`), écritures
/// **uniquement** par RPC (le moteur de stock verrouille, contrôle le stock
/// négatif et écrit le mouvement dans la même transaction).
class InventoryRepository {
  InventoryRepository(this._client);

  final SupabaseClient _client;

  Future<List<StockLocation>> fetchLocations(String businessId) => guardSupabase(() async {
    final rows = await _client
        .from('locations')
        .select('id, name, type, is_default')
        .eq('business_id', businessId)
        .eq('status', 'ACTIVE')
        .order('is_default', ascending: false)
        .order('name', ascending: true);
    return rows.map(StockLocation.fromRow).toList();
  });

  /// Lignes de stock, les plus critiques d'abord (quantité croissante).
  Future<List<StockRow>> fetchStock(
    String businessId, {
    required StockFilter filter,
    String? locationId,
    required int offset,
    required int limit,
  }) => guardSupabase(() async {
    if (filter == StockFilter.low) return _fetchLowStock(businessId, locationId);
    var query = _client
        .from('inventory')
        .select(StockRow.columns)
        .eq('business_id', businessId)
        .eq('product.status', 'ACTIVE');
    if (locationId != null) query = query.eq('location_id', locationId);
    if (filter == StockFilter.out) query = query.lte('quantity', 0);
    final rows = await query.order('quantity', ascending: true).range(offset, offset + limit - 1);
    return rows.map(StockRow.fromRow).toList();
  });

  /// `list_low_stock` (calculé en base) complété par unité et image.
  Future<List<StockRow>> _fetchLowStock(String businessId, String? locationId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_low_stock',
      params: {'p_business_id': businessId, 'p_location_id': locationId},
    );
    final items = rows.cast<Map<String, dynamic>>();
    if (items.isEmpty) return const [];
    final ids = items.map((r) => r['product_id'] as String).toSet().toList();
    final products = await _client
        .from('products')
        .select('id, unit, image_path, allows_fractional_quantity')
        .inFilter('id', ids);
    final byId = {for (final p in products) p['id'] as String: p};
    return [for (final r in items) StockRow.fromLowStock(r, products: byId)]
      ..sort((a, b) => a.quantity.compareTo(b.quantity));
  }

  /// Stock d'un produit par emplacement (tous les emplacements actifs).
  Future<List<LocationStock>> fetchProductStock(String businessId, String productId) => guardSupabase(() async {
    final locations = await fetchLocations(businessId);
    final rows = await _client
        .from('inventory')
        .select('location_id, quantity')
        .eq('business_id', businessId)
        .eq('product_id', productId);
    final byLocation = {for (final r in rows) r['location_id'] as String: num.parse('${r['quantity']}')};
    return [for (final l in locations) LocationStock(location: l, quantity: byLocation[l.id])];
  });

  Future<List<StockMovement>> fetchMovements(
    String businessId,
    String productId, {
    required int offset,
    required int limit,
  }) => guardSupabase(() async {
    final rows = await _client
        .from('inventory_movements')
        .select(StockMovement.columns)
        .eq('business_id', businessId)
        .eq('product_id', productId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map(StockMovement.fromRow).toList();
  });

  /// Stock d'ouverture (une seule fois par produit × emplacement).
  Future<void> setInitialStock({
    required String businessId,
    required String productId,
    required String locationId,
    required num quantity,
  }) => adjust(
    businessId: businessId,
    productId: productId,
    locationId: locationId,
    type: MovementType.initial,
    quantity: quantity,
  );

  /// `adjust_stock` : [quantity] est un **delta signé** (perte de 3 → −3).
  /// Types acceptés : INITIAL, ADJUSTMENT, LOSS, DAMAGE (motif obligatoire
  /// sauf INITIAL).
  Future<void> adjust({
    required String businessId,
    required String productId,
    required String locationId,
    required MovementType type,
    required num quantity,
    String? reason,
  }) => guardSupabase(
    () => _client.rpc<dynamic>(
      'adjust_stock',
      params: {
        'p_business_id': businessId,
        'p_product_id': productId,
        'p_location_id': locationId,
        'p_type': type.code,
        'p_quantity': quantity,
        'p_reason': reason,
      },
    ),
  );

  /// Inventaire physique : on envoie la quantité **comptée** ; l'écart est
  /// calculé par le serveur sous verrou (une vente simultanée n'est pas perdue).
  Future<void> count({
    required String businessId,
    required String productId,
    required String locationId,
    required num countedQuantity,
    String? reason,
  }) => guardSupabase(
    () => _client.rpc<dynamic>(
      'count_stock',
      params: {
        'p_business_id': businessId,
        'p_product_id': productId,
        'p_location_id': locationId,
        'p_counted_quantity': countedQuantity,
        'p_reason': reason,
      },
    ),
  );

  Future<void> transfer({
    required String businessId,
    required String productId,
    required String fromLocationId,
    required String toLocationId,
    required num quantity,
    String? reason,
  }) => guardSupabase(
    () => _client.rpc<dynamic>(
      'transfer_stock',
      params: {
        'p_business_id': businessId,
        'p_product_id': productId,
        'p_from_location_id': fromLocationId,
        'p_to_location_id': toLocationId,
        'p_quantity': quantity,
        'p_reason': reason,
      },
    ),
  );
}
