import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/supabase/guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/expense_models.dart';

final expensesRepositoryProvider = Provider<ExpensesRepository>(
  (ref) => ExpensesRepository(ref.watch(supabaseClientProvider)),
);

/// Dépenses, catégories et justificatifs (bucket **privé** `documents`).
class ExpensesRepository {
  ExpensesRepository(this._client);

  final SupabaseClient _client;

  static const _bucket = 'documents';

  Future<List<ExpenseCategory>> fetchCategories(String businessId) => guardSupabase(() async {
    final rows = await _client
        .from('expense_categories')
        .select('id, name')
        .eq('business_id', businessId)
        .eq('status', 'ACTIVE')
        .order('name', ascending: true);
    return rows.map(ExpenseCategory.fromRow).toList();
  });

  Future<ExpenseCategory> createCategory(String businessId, String name) => guardSupabase(() async {
    final row = await _client
        .from('expense_categories')
        .insert({'business_id': businessId, 'name': name.trim()})
        .select('id, name')
        .single();
    return ExpenseCategory.fromRow(row);
  });

  Future<void> archiveCategory(String id) =>
      guardSupabase(() => _client.from('expense_categories').update({'status': 'ARCHIVED'}).eq('id', id));

  /// Dépenses d'une période (plus récentes d'abord), filtre catégorie.
  Future<List<Expense>> fetchExpenses(
    String businessId, {
    required DateTime from,
    required DateTime to,
    String? categoryId,
    required int offset,
    required int limit,
  }) => guardSupabase(() async {
    var q = _client
        .from('expenses')
        .select(Expense.columns)
        .eq('business_id', businessId)
        .gte('spent_on', Formatters.isoDay(from))
        .lte('spent_on', Formatters.isoDay(to));
    if (categoryId != null) q = q.eq('category_id', categoryId);
    final rows = await q
        .order('spent_on', ascending: false)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map(Expense.fromRow).toList();
  });

  Future<Expense> fetchExpense(String id) => guardSupabase(() async {
    final row = await _client.from('expenses').select(Expense.columns).eq('id', id).single();
    return Expense.fromRow(row);
  });

  Future<Expense> create(String businessId, ExpenseInput input) => guardSupabase(() async {
    final row = await _client
        .from('expenses')
        .insert({'business_id': businessId, ...input.toColumns()})
        .select(Expense.columns)
        .single();
    return Expense.fromRow(row);
  });

  Future<Expense> update(String id, ExpenseInput input) => guardSupabase(() async {
    final rows = await _client.from('expenses').update(input.toColumns()).eq('id', id).select(Expense.columns);
    if (rows.isEmpty) {
      throw const AppFailure(FailureKind.permission, 'Vous n’avez pas l’autorisation de modifier cette dépense.');
    }
    return Expense.fromRow(rows.first);
  });

  /// Suppression (`expenses.manage`) : la ligne reste dans le journal d'audit.
  Future<void> delete(String id) => guardSupabase(() async {
    final rows = await _client.from('expenses').delete().eq('id', id).select('id');
    if (rows.isEmpty) {
      throw const AppFailure(FailureKind.permission, 'Vous n’avez pas l’autorisation de supprimer cette dépense.');
    }
  });

  /// Envoie un justificatif : `documents/{business_id}/expenses/{horodatage}.{ext}`.
  Future<String> uploadReceipt(String businessId, Uint8List bytes, {required String mimeType}) =>
      guardSupabase(() async {
        final ext = switch (mimeType) {
          'image/png' => 'png',
          'image/webp' => 'webp',
          'application/pdf' => 'pdf',
          _ => 'jpg',
        };
        final path = '$businessId/expenses/${DateTime.now().microsecondsSinceEpoch}.$ext';
        await _client.storage.from(_bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mimeType));
        return path;
      });

  /// URL **signée de courte durée** (bucket privé : jamais d'URL publique).
  Future<String> signedReceiptUrl(String path, {int seconds = 120}) =>
      guardSupabase(() => _client.storage.from(_bucket).createSignedUrl(path, seconds));

  Future<void> deleteReceipt(String path) =>
      _client.storage.from(_bucket).remove([path]).then<void>((_) {}, onError: (_) {});
}
