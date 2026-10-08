import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/domain/payment_method.dart';
import '../../../core/supabase/guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/sale_models.dart';

final salesRepositoryProvider = Provider<SalesRepository>((ref) => SalesRepository(ref.watch(supabaseClientProvider)));

/// Requête de vente telle qu'envoyée à `create_sale` (aussi stockée telle
/// quelle dans la file hors ligne).
class SaleRequest {
  const SaleRequest({
    required this.businessId,
    required this.clientReference,
    required this.locationId,
    required this.items,
    this.payments = const [],
    this.customerId,
    this.discount = 0,
    this.notes,
  });

  factory SaleRequest.fromJson(Map<String, dynamic> j) => SaleRequest(
    businessId: j['business_id'] as String,
    clientReference: j['client_reference'] as String,
    locationId: j['location_id'] as String,
    items: (j['items'] as List).cast<Map<String, dynamic>>(),
    payments: (j['payments'] as List).cast<Map<String, dynamic>>(),
    customerId: j['customer_id'] as String?,
    discount: (j['discount'] as num?)?.toInt() ?? 0,
    notes: j['notes'] as String?,
  );

  final String businessId;

  /// UUID généré **une fois** à la validation du panier : un renvoi après
  /// coupure réseau renvoie la vente déjà créée, jamais un doublon.
  final String clientReference;
  final String locationId;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> payments;
  final String? customerId;
  final int discount;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'business_id': businessId,
    'client_reference': clientReference,
    'location_id': locationId,
    'items': items,
    'payments': payments,
    'customer_id': customerId,
    'discount': discount,
    'notes': notes,
  };
}

/// Caisse : produits vendables, clients, `create_sale`, `cancel_sale`,
/// lecture des ventes (RLS : toutes, ou seulement les siennes).
class SalesRepository {
  SalesRepository(this._client);

  final SupabaseClient _client;

  /// Produits actifs pour la grille de caisse (recherche nom / code).
  Future<List<SellableProduct>> fetchSellable(
    String businessId, {
    String query = '',
    String? categoryId,
    List<String>? ids,
    int limit = 200,
  }) => guardSupabase(() async {
    var q = _client
        .from('products')
        .select(SellableProduct.columns)
        .eq('business_id', businessId)
        .eq('status', 'ACTIVE');
    if (categoryId != null) q = q.eq('category_id', categoryId);
    if (ids != null) q = q.inFilter('id', ids);
    final term = query.replaceAll(RegExp(r'[,()*%\\]'), ' ').trim();
    if (term.isNotEmpty) q = q.or('name.ilike.*$term*,barcode.eq.${term.replaceAll(' ', '')}');
    final rows = await q.order('name', ascending: true).limit(limit);
    return rows.map(SellableProduct.fromRow).toList();
  });

  Future<SellableProduct?> findByBarcode(String businessId, String code) => guardSupabase(() async {
    final row = await _client
        .from('products')
        .select(SellableProduct.columns)
        .eq('business_id', businessId)
        .eq('status', 'ACTIVE')
        .eq('barcode', code.replaceAll(RegExp(r'\s'), ''))
        .maybeSingle();
    return row == null ? null : SellableProduct.fromRow(row);
  });

  Future<List<SaleCustomer>> searchCustomers(String businessId, String query) => guardSupabase(() async {
    var q = _client.from('customers').select(SaleCustomer.columns).eq('business_id', businessId).eq('status', 'ACTIVE');
    final term = query.replaceAll(RegExp(r'[,()*%\\]'), ' ').trim();
    if (term.isNotEmpty) q = q.or('name.ilike.*$term*,phone.ilike.*${term.replaceAll(' ', '')}*');
    final rows = await q.order('name', ascending: true).limit(20);
    return rows.map(SaleCustomer.fromRow).toList();
  });

  /// Création rapide à la caisse (`customers.create`) : plafond et solde
  /// sont gérés côté serveur (plafond 0 par défaut).
  Future<SaleCustomer> createCustomer(String businessId, {required String name, String? phone}) =>
      guardSupabase(() async {
        final row = await _client
            .from('customers')
            .insert({
              'business_id': businessId,
              'name': name.trim(),
              if (phone?.trim().isNotEmpty ?? false) 'phone': phone!.trim(),
            })
            .select(SaleCustomer.columns)
            .single();
        return SaleCustomer.fromRow(row);
      });

  /// Vente atomique et idempotente. Renvoie l'identifiant de la vente.
  Future<String> createSale(SaleRequest r) => guardSupabase(
    () => _client.rpc<String>(
      'create_sale',
      params: {
        'p_business_id': r.businessId,
        'p_client_reference': r.clientReference,
        'p_location_id': r.locationId,
        'p_items': r.items,
        'p_payments': r.payments,
        'p_customer_id': r.customerId,
        'p_discount_amount': r.discount,
        'p_notes': r.notes,
      },
    ),
  );

  Future<Sale> fetchSale(String saleId) => guardSupabase(() async {
    final row = await _client.from('sales').select(Sale.columns).eq('id', saleId).single();
    return Sale.fromRow(row);
  });

  /// Historique (plus récentes d'abord), filtrable par période locale.
  Future<List<Sale>> fetchSales(
    String businessId, {
    DateTime? from,
    DateTime? to,
    required int offset,
    required int limit,
  }) => guardSupabase(() async {
    var q = _client.from('sales').select(Sale.columns).eq('business_id', businessId);
    if (from != null) q = q.gte('sold_at', from.toUtc().toIso8601String());
    if (to != null) q = q.lt('sold_at', to.toUtc().toIso8601String());
    final rows = await q.order('sold_at', ascending: false).range(offset, offset + limit - 1);
    return rows.map(Sale.fromRow).toList();
  });

  /// Annulation totale (`sales.cancel`) : stock remis, crédit annulé,
  /// remboursement enregistré comme paiement sortant.
  Future<void> cancelSale(String saleId, {required String reason, PaymentMethod refundMethod = PaymentMethod.cash}) =>
      guardSupabase(
        () => _client.rpc<dynamic>(
          'cancel_sale',
          params: {'p_sale_id': saleId, 'p_reason': reason.trim(), 'p_refund_method': refundMethod.code},
        ),
      );
}
