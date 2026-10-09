// Test d'intégration des dépenses contre un Supabase réel.
//   flutter test test/integration -j 1 --dart-define-from-file=env/dev.json
@Tags(['integration'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/config/env.dart';
import 'package:jend_pro_mobile/core/domain/payment_method.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/business/data/business_repository.dart';
import 'package:jend_pro_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:jend_pro_mobile/features/dashboard/domain/dashboard_models.dart';
import 'package:jend_pro_mobile/features/expenses/data/expenses_repository.dart';
import 'package:jend_pro_mobile/features/expenses/domain/expense_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  final skip = Env.isConfigured ? false : 'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY non fournis';

  test(
    'dépenses : catégories par défaut, saisie, justificatif privé, période, modification, suppression',
    () async {
      final client = SupabaseClient(
        Env.supabaseUrl,
        Env.supabasePublishableKey,
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      );
      final auth = AuthRepository(client);
      final business = BusinessRepository(client);
      final expenses = ExpensesRepository(client);

      await signUpForTest(
        auth,
        fullName: 'Test Dépenses',
        email: 'expenses-${DateTime.now().millisecondsSinceEpoch}@test.jendpro.local',
        password: 'motdepasse-test',
      );
      final bid = await business.createBusiness(name: 'Boutique Dépenses');

      final categories = await expenses.fetchCategories(bid);
      expect(categories.length, 10, reason: 'catégories par défaut');
      final loyer = categories.firstWhere((c) => c.name == 'Loyer');
      final transport = categories.firstWhere((c) => c.name == 'Transport');

      // Justificatif dans le bucket privé + URL signée.
      final receipt = await expenses.uploadReceipt(bid, _png, mimeType: 'image/png');
      expect(receipt, startsWith('$bid/expenses/'));
      final url = await expenses.signedReceiptUrl(receipt);
      expect(url, contains('token='));

      final today = DateTime.now();
      final lastMonth = DateTime(today.year, today.month - 1, 15);
      final rent = await expenses.create(
        bid,
        ExpenseInput(
          categoryId: loyer.id,
          amount: 150000,
          spentOn: today,
          method: PaymentMethod.bankTransfer,
          description: 'Loyer du mois',
          receiptPath: receipt,
        ),
      );
      expect(rent.categoryName, 'Loyer');
      await expenses.create(
        bid,
        ExpenseInput(categoryId: transport.id, amount: 3500, spentOn: today, method: PaymentMethod.cash),
      );
      await expenses.create(
        bid,
        ExpenseInput(categoryId: transport.id, amount: 2000, spentOn: lastMonth, method: PaymentMethod.cash),
      );

      final month = ExpenseMonth.of(today);
      final thisMonth = await expenses.fetchExpenses(bid, from: month.first, to: month.last, offset: 0, limit: 50);
      expect(thisMonth.map((e) => e.amount).toSet(), {150000, 3500});
      final onlyTransport = await expenses.fetchExpenses(
        bid,
        from: month.first,
        to: month.last,
        categoryId: transport.id,
        offset: 0,
        limit: 50,
      );
      expect(onlyTransport.single.amount, 3500);

      // Le total de la période vient du serveur (tableau de bord).
      final summary = await DashboardRepository(
        client,
      ).fetchSummary(bid, DashboardPeriod.custom(month.first, month.last));
      expect(summary.expenses, 153500);

      // Modification puis suppression.
      final edited = await expenses.update(
        rent.id,
        ExpenseInput(
          categoryId: loyer.id,
          amount: 160000,
          spentOn: today,
          method: PaymentMethod.bankTransfer,
          receiptPath: receipt,
        ),
      );
      expect(edited.amount, 160000);
      expect(edited.description, isNull);
      await expenses.delete(rent.id);
      expect(
        (await expenses.fetchExpenses(bid, from: month.first, to: month.last, offset: 0, limit: 50)).single.amount,
        3500,
      );

      // Catégorie personnalisée.
      final custom = await expenses.createCategory(bid, 'Marketing');
      expect((await expenses.fetchCategories(bid)).map((c) => c.id), contains(custom.id));

      await auth.signOut();
      await client.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
