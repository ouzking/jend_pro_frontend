import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/domain/payment_method.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/supabase/guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../sales/domain/sale_models.dart';
import '../domain/customer_models.dart';

final customersRepositoryProvider = Provider<CustomersRepository>(
  (ref) => CustomersRepository(ref.watch(supabaseClientProvider)),
);

/// Clients et comptes de crédit. Solde et plafond ne s'écrivent **que** par
/// RPC (moteur de compte : verrou, solde jamais négatif, audit).
class CustomersRepository {
  CustomersRepository(this._client);

  final SupabaseClient _client;

  /// Champs modifiables directement (droits par colonne en base).
  static const editableColumns = {'name', 'phone', 'email', 'address', 'notes'};

  Future<List<Customer>> fetchCustomers(
    String businessId,
    CustomerFilter filter, {
    required int offset,
    required int limit,
  }) => guardSupabase(() async {
    var q = _client
        .from('customers')
        .select(Customer.columns)
        .eq('business_id', businessId)
        .eq('status', filter.segment == CustomerSegment.archived ? 'ARCHIVED' : 'ACTIVE');
    if (filter.segment == CustomerSegment.debtors) q = q.gt('balance', 0);
    final term = filter.query.replaceAll(RegExp(r'[,()*%\\]'), ' ').trim();
    if (term.isNotEmpty) q = q.or('name.ilike.*$term*,phone.ilike.*${term.replaceAll(' ', '')}*');
    // Débiteurs : les plus grosses dettes d'abord (index dédié en base).
    final ordered = filter.segment == CustomerSegment.debtors
        ? q.order('balance', ascending: false)
        : q.order('name', ascending: true);
    final rows = await ordered.range(offset, offset + limit - 1);
    return rows.map(Customer.fromRow).toList();
  });

  Future<Customer> fetchCustomer(String id) => guardSupabase(() async {
    final row = await _client.from('customers').select(Customer.columns).eq('id', id).single();
    return Customer.fromRow(row);
  });

  Future<Customer> create(
    String businessId, {
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
  }) => guardSupabase(() async {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    final row = await _client
        .from('customers')
        .insert({
          'business_id': businessId,
          'name': name.trim(),
          'phone': clean(phone),
          'email': clean(email),
          'address': clean(address),
          'notes': clean(notes),
        })
        .select(Customer.columns)
        .single();
    return Customer.fromRow(row);
  });

  Future<Customer> update(String id, Map<String, Object?> changes) => guardSupabase(() async {
    assert(changes.keys.every(editableColumns.contains), 'Colonne non modifiable : ${changes.keys}');
    final rows = await _client.from('customers').update(changes).eq('id', id).select(Customer.columns);
    if (rows.isEmpty) {
      throw const AppFailure(FailureKind.permission, 'Vous n’avez pas l’autorisation de modifier ce client.');
    }
    return Customer.fromRow(rows.first);
  });

  /// Archiver (refusé tant que le client doit de l'argent) / réactiver.
  Future<Customer> setArchived(String id, {required bool archived}) => guardSupabase(() async {
    final rows = await _client
        .from('customers')
        .update({'status': archived ? 'ARCHIVED' : 'ACTIVE'})
        .eq('id', id)
        .select(Customer.columns);
    if (rows.isEmpty) {
      throw const AppFailure(FailureKind.permission, 'Vous n’avez pas l’autorisation de modifier ce client.');
    }
    return Customer.fromRow(rows.first);
  });

  /// Plafond : `0` aucun crédit, `null` sans plafond (`customers.manage`).
  Future<void> setCreditLimit(String id, int? limit) => guardSupabase(
    () => _client.rpc<void>('set_customer_credit_limit', params: {'p_customer_id': id, 'p_credit_limit': limit}),
  );

  /// Règlement d'une dette (`customers.payments`) : paiement entrant +
  /// écriture négative, atomiquement. Ne peut pas dépasser le solde dû.
  Future<void> recordPayment({
    required String customerId,
    required int amount,
    required PaymentMethod method,
    required String locationId,
    String? externalReference,
    String? note,
  }) => guardSupabase(
    () => _client.rpc<dynamic>(
      'record_customer_payment',
      params: {
        'p_customer_id': customerId,
        'p_amount': amount,
        'p_method': method.code,
        'p_location_id': locationId,
        'p_external_reference': (externalReference?.trim().isEmpty ?? true) ? null : externalReference!.trim(),
        'p_note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
      },
    ),
  );

  /// Reprise / correction de solde (`customers.manage`), montant **signé**,
  /// motif obligatoire (ex. dettes du cahier au démarrage).
  Future<void> adjustBalance(String id, {required int amount, required String reason}) => guardSupabase(
    () => _client.rpc<dynamic>(
      'adjust_customer_balance',
      params: {'p_customer_id': id, 'p_amount': amount, 'p_reason': reason.trim()},
    ),
  );

  Future<List<CustomerTransaction>> fetchTransactions(
    String businessId,
    String customerId, {
    required int offset,
    required int limit,
  }) => guardSupabase(() async {
    final rows = await _client
        .from('customer_transactions')
        .select(CustomerTransaction.columns)
        .eq('business_id', businessId)
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map(CustomerTransaction.fromRow).toList();
  });

  /// Achats du client (visibles selon `sales.read` / `sales.read_own`).
  Future<List<Sale>> fetchSales(String businessId, String customerId, {int limit = 20}) => guardSupabase(() async {
    final rows = await _client
        .from('sales')
        .select(Sale.columns)
        .eq('business_id', businessId)
        .eq('customer_id', customerId)
        .order('sold_at', ascending: false)
        .limit(limit);
    return rows.map(Sale.fromRow).toList();
  });
}
