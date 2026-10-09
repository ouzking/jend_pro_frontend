// Test d'intégration de la caisse contre un Supabase réel.
//   flutter test test/integration --dart-define-from-file=env/dev.json
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/config/env.dart';
import 'package:jend_pro_mobile/core/domain/payment_method.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/business/data/business_repository.dart';
import 'package:jend_pro_mobile/features/inventory/data/inventory_repository.dart';
import 'package:jend_pro_mobile/features/products/data/products_repository.dart';
import 'package:jend_pro_mobile/features/products/domain/catalog_models.dart';
import 'package:jend_pro_mobile/features/sales/data/sales_repository.dart';
import 'package:jend_pro_mobile/features/sales/domain/cart.dart';
import 'package:jend_pro_mobile/features/sales/domain/sale_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support.dart';

void main() {
  final skip = Env.isConfigured ? false : 'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY non fournis';

  test(
    'caisse : vente, idempotence, crédit, erreurs, annulation',
    () async {
      final client = SupabaseClient(
        Env.supabaseUrl,
        Env.supabasePublishableKey,
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      );
      final auth = AuthRepository(client);
      final business = BusinessRepository(client);
      final products = ProductsRepository(client);
      final inventory = InventoryRepository(client);
      final sales = SalesRepository(client);

      await signUpForTest(
        auth,
        fullName: 'Test Caisse',
        email: 'pos-${DateTime.now().millisecondsSinceEpoch}@test.jendpro.local',
        password: 'motdepasse-test',
      );
      final bid = await business.createBusiness(name: 'Boutique Caisse');
      final loc = await business.fetchDefaultLocationId(bid);
      final huile = await products.createProduct(
        bid,
        const NewProduct(name: 'Huile 5 L', salePrice: 6500, barcode: '6009876543210'),
      );
      await products.createProduct(
        bid,
        const NewProduct(name: 'Riz au kg', salePrice: 650, allowsFractionalQuantity: true),
      );
      await inventory.setInitialStock(businessId: bid, productId: huile.id, locationId: loc, quantity: 10);

      // Grille de caisse + scan.
      final sellable = await sales.fetchSellable(bid);
      expect(sellable.map((p) => p.name), ['Huile 5 L', 'Riz au kg']);
      final scanned = await sales.findByBarcode(bid, '6009876543210');
      expect(scanned?.stockQuantity, 10);

      // Panier : 3 huiles, remise globale 0, payé Wave 10 000 + espèces 10 000 (dû 9 500 → monnaie 500).
      final cart = const Cart().add(scanned!, quantity: 3);
      final settlement = Settlement.compute(
        total: cart.total,
        tendered: const [
          PaymentEntry(method: PaymentMethod.wave, amount: 10000, externalReference: 'TX-1'),
          PaymentEntry(method: PaymentMethod.cash, amount: 10000),
        ],
      );
      expect(settlement.change, 500);
      final request = SaleRequest(
        businessId: bid,
        clientReference: const Uuid().v4(),
        locationId: loc,
        items: [for (final l in cart.lines) l.toJson()],
        payments: [for (final p in settlement.payments) p.toJson()],
      );
      final saleId = await sales.createSale(request);

      // Idempotence : même référence → même vente, pas de doublon ni de double sortie de stock.
      expect(await sales.createSale(request), saleId);
      final receipt = await sales.fetchSale(saleId);
      expect(receipt.total, 19500);
      expect(receipt.amountPaid, 19500);
      expect(receipt.creditAmount, 0);
      expect(receipt.number, startsWith('V-'));
      expect(receipt.lines.single.unitPrice, 6500);
      expect(receipt.payments.map((p) => p.method), [PaymentMethod.wave, PaymentMethod.cash]);
      expect((await products.fetchProduct(huile.id)).stockQuantity, 7);

      // Crédit : exige un client avec plafond suffisant.
      final creditRequest = SaleRequest(
        businessId: bid,
        clientReference: const Uuid().v4(),
        locationId: loc,
        items: [
          {'product_id': huile.id, 'quantity': 1},
        ],
      );
      await expectLater(
        sales.createSale(creditRequest),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'CUSTOMER_REQUIRED_FOR_CREDIT')),
      );
      final fatou = await sales.createCustomer(bid, name: 'Fatou Sow', phone: '77 123 45 67');
      expect(fatou.creditLimit, 0, reason: 'pas de crédit par défaut');
      expect((await sales.searchCustomers(bid, 'fat')).single.id, fatou.id);
      expect((await sales.searchCustomers(bid, '771234')).single.id, fatou.id);
      await client.rpc<dynamic>(
        'set_customer_credit_limit',
        params: {'p_customer_id': fatou.id, 'p_credit_limit': 50000},
      );
      final creditSaleId = await sales.createSale(
        SaleRequest(
          businessId: bid,
          clientReference: const Uuid().v4(),
          locationId: loc,
          items: creditRequest.items,
          customerId: fatou.id,
          payments: [const PaymentEntry(method: PaymentMethod.cash, amount: 2500).toJson()],
        ),
      );
      final creditSale = await sales.fetchSale(creditSaleId);
      expect(creditSale.creditAmount, 4000);
      expect(creditSale.customerName, 'Fatou Sow');

      // Paiement supérieur au total refusé.
      await expectLater(
        sales.createSale(
          SaleRequest(
            businessId: bid,
            clientReference: const Uuid().v4(),
            locationId: loc,
            items: creditRequest.items,
            payments: [const PaymentEntry(method: PaymentMethod.cash, amount: 99999).toJson()],
          ),
        ),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'PAYMENT_EXCEEDS_TOTAL')),
      );

      // Historique.
      final history = await sales.fetchSales(bid, offset: 0, limit: 20);
      expect(history.map((s) => s.id), [creditSaleId, saleId]);

      // Annulation : stock remis, remboursement sortant.
      await sales.cancelSale(saleId, reason: 'Erreur de caisse');
      final cancelled = await sales.fetchSale(saleId);
      expect(cancelled.cancelled, isTrue);
      expect(cancelled.payments.where((p) => !p.incoming).single.amount, 19500);
      expect((await products.fetchProduct(huile.id)).stockQuantity, 9);
      await expectLater(
        sales.cancelSale(saleId, reason: 'Encore'),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'SALE_ALREADY_CANCELLED')),
      );

      await auth.signOut();
      await client.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
