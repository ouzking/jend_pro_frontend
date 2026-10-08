import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/domain/payment_method.dart';
import '../../../core/supabase/guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../suppliers/domain/supplier_models.dart';
import '../domain/purchase_models.dart';

final purchasesRepositoryProvider = Provider<PurchasesRepository>(
  (ref) => PurchasesRepository(ref.watch(supabaseClientProvider)),
);

/// Achats : lecture directe, toutes les écritures par RPC (totaux recalculés
/// par le serveur, réception atomique stock + coût moyen pondéré).
class PurchasesRepository {
  PurchasesRepository(this._client);

  final SupabaseClient _client;

  Future<List<PurchaseSummary>> fetchPurchases(
    String businessId, {
    PurchaseSegment segment = PurchaseSegment.all,
    required int offset,
    required int limit,
  }) => guardSupabase(() async {
    var q = _client.from('purchases').select(PurchaseSummary.columns).eq('business_id', businessId);
    q = switch (segment) {
      PurchaseSegment.all => q,
      PurchaseSegment.open => q.inFilter('status', ['DRAFT', 'ORDERED']),
      PurchaseSegment.received => q.eq('status', 'RECEIVED'),
      PurchaseSegment.unpaid => q.eq('status', 'RECEIVED').neq('payment_status', 'PAID'),
    };
    final rows = await q.order('created_at', ascending: false).range(offset, offset + limit - 1);
    return rows.map(PurchaseSummary.fromRow).toList();
  });

  Future<Purchase> fetchPurchase(String id) => guardSupabase(() async {
    final row = await _client.from('purchases').select(Purchase.columns).eq('id', id).single();
    return Purchase.fromRow(row);
  });

  /// Crée (`purchaseId == null`) ou remplace **en bloc** les lignes d'un
  /// achat brouillon / commandé. Renvoie l'identifiant de l'achat.
  Future<String> save(String businessId, PurchaseDraft draft) => guardSupabase(
    () => _client.rpc<String>(
      'save_purchase',
      params: {
        'p_business_id': businessId,
        'p_purchase_id': draft.purchaseId,
        'p_supplier_id': draft.supplier?.id,
        'p_location_id': draft.locationId,
        'p_items': [for (final l in draft.lines) l.toJson()],
        'p_discount_amount': draft.discount,
        'p_supplier_reference': (draft.supplierReference?.trim().isEmpty ?? true)
            ? null
            : draft.supplierReference!.trim(),
        'p_notes': (draft.notes?.trim().isEmpty ?? true) ? null : draft.notes!.trim(),
      },
    ),
  );

  Future<void> order(String id) =>
      guardSupabase(() => _client.rpc<void>('order_purchase', params: {'p_purchase_id': id}));

  /// Réception : entrée en stock + coût moyen pondéré + dernier coût
  /// fournisseur, en une transaction (`purchases.receive`).
  Future<void> receive(String id) =>
      guardSupabase(() => _client.rpc<void>('receive_purchase', params: {'p_purchase_id': id}));

  Future<void> cancel(String id, {required String reason}) => guardSupabase(
    () => _client.rpc<void>('cancel_purchase', params: {'p_purchase_id': id, 'p_reason': reason.trim()}),
  );

  /// Paiement fournisseur (acompte avant réception possible).
  Future<void> recordPayment(
    String id, {
    required int amount,
    required PaymentMethod method,
    required String locationId,
    String? reference,
    String? note,
  }) => guardSupabase(
    () => _client.rpc<dynamic>(
      'record_purchase_payment',
      params: {
        'p_purchase_id': id,
        'p_amount': amount,
        'p_method': method.code,
        'p_location_id': locationId,
        'p_external_reference': (reference?.trim().isEmpty ?? true) ? null : reference!.trim(),
        'p_note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
      },
    ),
  );
}
