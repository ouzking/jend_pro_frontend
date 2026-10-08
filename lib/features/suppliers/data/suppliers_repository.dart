import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/supabase/guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/supplier_models.dart';

final suppliersRepositoryProvider = Provider<SuppliersRepository>(
  (ref) => SuppliersRepository(ref.watch(supabaseClientProvider)),
);

/// Fournisseurs, produits fournis et dettes fournisseurs (vue calculée).
class SuppliersRepository {
  SuppliersRepository(this._client);

  final SupabaseClient _client;

  static const editableColumns = {'name', 'contact_name', 'phone', 'email', 'address', 'notes'};

  Future<List<Supplier>> fetchSuppliers(
    String businessId, {
    String query = '',
    SupplierSegment segment = SupplierSegment.all,
    List<String>? ids,
    required int offset,
    required int limit,
  }) => guardSupabase(() async {
    var q = _client
        .from('suppliers')
        .select(Supplier.columns)
        .eq('business_id', businessId)
        .eq('status', segment == SupplierSegment.archived ? 'ARCHIVED' : 'ACTIVE');
    if (ids != null) q = q.inFilter('id', ids);
    final term = query.replaceAll(RegExp(r'[,()*%\\]'), ' ').trim();
    if (term.isNotEmpty) {
      q = q.or('name.ilike.*$term*,contact_name.ilike.*$term*,phone.ilike.*${term.replaceAll(' ', '')}*');
    }
    final rows = await q.order('name', ascending: true).range(offset, offset + limit - 1);
    return rows.map(Supplier.fromRow).toList();
  });

  /// Dettes par fournisseur (`purchases.read`, sinon vide).
  Future<Map<String, SupplierBalance>> fetchBalances(String businessId, {bool owedOnly = false}) =>
      guardSupabase(() async {
        var q = _client
            .from('supplier_balances')
            .select('supplier_id, amount_due, advances_paid, unpaid_purchases')
            .eq('business_id', businessId);
        if (owedOnly) q = q.gt('amount_due', 0);
        final rows = await q;
        return {
          for (final r in rows)
            if (r['supplier_id'] != null) r['supplier_id'] as String: SupplierBalance.fromRow(r),
        };
      });

  Future<Supplier> fetchSupplier(String id) => guardSupabase(() async {
    final row = await _client.from('suppliers').select(Supplier.columns).eq('id', id).single();
    return Supplier.fromRow(row);
  });

  Future<Supplier> create(String businessId, Map<String, Object?> fields) => guardSupabase(() async {
    assert(fields.keys.every(editableColumns.contains));
    final row = await _client
        .from('suppliers')
        .insert({'business_id': businessId, ...fields})
        .select(Supplier.columns)
        .single();
    return Supplier.fromRow(row);
  });

  Future<Supplier> update(String id, Map<String, Object?> changes) => guardSupabase(() async {
    assert(changes.keys.every(editableColumns.contains));
    return _single(await _client.from('suppliers').update(changes).eq('id', id).select(Supplier.columns));
  });

  Future<Supplier> setArchived(String id, {required bool archived}) => guardSupabase(
    () async => _single(
      await _client
          .from('suppliers')
          .update({'status': archived ? 'ARCHIVED' : 'ACTIVE'})
          .eq('id', id)
          .select(Supplier.columns),
    ),
  );

  Supplier _single(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      throw const AppFailure(FailureKind.permission, 'Vous n’avez pas l’autorisation de modifier ce fournisseur.');
    }
    return Supplier.fromRow(rows.first);
  }

  Future<List<SupplierProduct>> fetchProducts(String businessId, String supplierId) => guardSupabase(() async {
    final rows = await _client
        .from('supplier_products')
        .select(SupplierProduct.columns)
        .eq('business_id', businessId)
        .eq('supplier_id', supplierId);
    return rows.map(SupplierProduct.fromRow).toList()
      ..sort((a, b) => a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));
  });

  Future<void> linkProduct(String businessId, String supplierId, String productId, {String? supplierSku}) =>
      guardSupabase(
        () => _client.from('supplier_products').insert({
          'business_id': businessId,
          'supplier_id': supplierId,
          'product_id': productId,
          if (supplierSku?.trim().isNotEmpty ?? false) 'supplier_sku': supplierSku!.trim(),
        }),
      );

  Future<void> updateSku(String supplierId, String productId, String? sku) => guardSupabase(
    () => _client
        .from('supplier_products')
        .update({'supplier_sku': (sku?.trim().isEmpty ?? true) ? null : sku!.trim()})
        .eq('supplier_id', supplierId)
        .eq('product_id', productId),
  );

  Future<void> unlinkProduct(String supplierId, String productId) => guardSupabase(
    () => _client.from('supplier_products').delete().eq('supplier_id', supplierId).eq('product_id', productId),
  );

  /// Achats du fournisseur (plus récents d'abord).
  Future<List<PurchaseSummary>> fetchPurchases(String businessId, String supplierId, {int limit = 20}) =>
      guardSupabase(() async {
        final rows = await _client
            .from('purchases')
            .select(PurchaseSummary.columns)
            .eq('business_id', businessId)
            .eq('supplier_id', supplierId)
            .order('created_at', ascending: false)
            .limit(limit);
        return rows.map(PurchaseSummary.fromRow).toList();
      });
}
