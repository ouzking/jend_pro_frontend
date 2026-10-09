// Test d'intégration des clients contre un Supabase réel.
//   flutter test test/integration --dart-define-from-file=env/dev.json
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/config/env.dart';
import 'package:jend_pro_mobile/core/domain/payment_method.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/business/data/business_repository.dart';
import 'package:jend_pro_mobile/features/customers/data/customers_repository.dart';
import 'package:jend_pro_mobile/features/customers/domain/customer_models.dart';
import 'package:jend_pro_mobile/features/products/data/products_repository.dart';
import 'package:jend_pro_mobile/features/products/domain/catalog_models.dart';
import 'package:jend_pro_mobile/features/sales/data/sales_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support.dart';

void main() {
  final skip = Env.isConfigured ? false : 'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY non fournis';

  test(
    'clients : fiche, plafond, reprise, vente à crédit, règlement, relevé, archivage',
    () async {
      final client = SupabaseClient(
        Env.supabaseUrl,
        Env.supabasePublishableKey,
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      );
      final auth = AuthRepository(client);
      final business = BusinessRepository(client);
      final products = ProductsRepository(client);
      final sales = SalesRepository(client);
      final customers = CustomersRepository(client);

      await signUpForTest(
        auth,
        fullName: 'Test Clients',
        email: 'customers-${DateTime.now().millisecondsSinceEpoch}@test.jendpro.local',
        password: 'motdepasse-test',
      );
      final bid = await business.createBusiness(name: 'Boutique Clients');
      final loc = await business.fetchDefaultLocationId(bid);
      final service = await products.createProduct(
        bid,
        const NewProduct(name: 'Livraison', salePrice: 5000, trackStock: false),
      );

      final fatou = await customers.create(bid, name: 'Fatou Sow', phone: '77 123 45 67', notes: 'Cliente fidèle');
      await customers.create(bid, name: 'Awa Ndiaye');
      expect(fatou.phone, '771234567', reason: 'normalisé par la base');
      expect(fatou.creditLimit, 0);

      // Reprise du cahier de crédit + plafond.
      await customers.adjustBalance(fatou.id, amount: 3000, reason: 'Reprise du cahier');
      await customers.setCreditLimit(fatou.id, 20000);
      // Vente à crédit : 5 000, rien payé.
      await sales.createSale(
        SaleRequest(
          businessId: bid,
          clientReference: const Uuid().v4(),
          locationId: loc,
          items: [
            {'product_id': service.id, 'quantity': 1},
          ],
          customerId: fatou.id,
        ),
      );
      var f = await customers.fetchCustomer(fatou.id);
      expect(f.balance, 8000);
      expect(f.creditAvailable, 12000);

      // Débiteurs, recherche.
      final debtors = await customers.fetchCustomers(
        bid,
        const CustomerFilter(segment: CustomerSegment.debtors),
        offset: 0,
        limit: 30,
      );
      expect(debtors.single.id, fatou.id);
      final all = await customers.fetchCustomers(bid, const CustomerFilter(), offset: 0, limit: 30);
      expect(all.map((c) => c.name), ['Awa Ndiaye', 'Fatou Sow']);
      final byPhone = await customers.fetchCustomers(bid, const CustomerFilter(query: '77 123'), offset: 0, limit: 30);
      expect(byPhone.single.id, fatou.id);

      // Règlement : au-delà du dû refusé, puis règlement partiel Wave.
      await expectLater(
        customers.recordPayment(customerId: fatou.id, amount: 9000, method: PaymentMethod.cash, locationId: loc),
        throwsA(isA<AppFailure>().having((e) => e.code, 'code', 'AMOUNT_EXCEEDS_BALANCE')),
      );
      await customers.recordPayment(
        customerId: fatou.id,
        amount: 5000,
        method: PaymentMethod.wave,
        locationId: loc,
        externalReference: 'TX-77',
        note: 'Acompte',
      );
      f = await customers.fetchCustomer(fatou.id);
      expect(f.balance, 3000);

      // Relevé (plus récent d'abord) avec lien vers la vente.
      final statement = await customers.fetchTransactions(bid, fatou.id, offset: 0, limit: 30);
      expect(statement.map((t) => t.type), [
        CustomerTransactionType.payment,
        CustomerTransactionType.creditSale,
        CustomerTransactionType.adjustment,
      ]);
      expect(statement.first.amount, -5000);
      expect(statement.first.balanceAfter, 3000);
      expect(statement[1].saleNumber, startsWith('V-'));

      final purchases = await customers.fetchSales(bid, fatou.id);
      expect(purchases.single.creditAmount, 5000);

      // Modification, archivage refusé avec dette, puis autorisé une fois soldé.
      final edited = await customers.update(fatou.id, {'email': 'fatou@exemple.sn'});
      expect(edited.email, 'fatou@exemple.sn');
      await expectLater(
        customers.setArchived(fatou.id, archived: true),
        throwsA(isA<AppFailure>().having((e) => e.code, 'code', 'CUSTOMER_HAS_BALANCE')),
      );
      await customers.recordPayment(customerId: fatou.id, amount: 3000, method: PaymentMethod.cash, locationId: loc);
      expect((await customers.setArchived(fatou.id, archived: true)).archived, isTrue);

      // Plafond illimité.
      final awa = all.first;
      await customers.setCreditLimit(awa.id, null);
      expect((await customers.fetchCustomer(awa.id)).unlimitedCredit, isTrue);

      await auth.signOut();
      await client.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
