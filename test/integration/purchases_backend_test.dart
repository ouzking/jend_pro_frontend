// Test d'intégration des achats contre un Supabase réel.
//   flutter test test/integration -j 1 --dart-define-from-file=env/dev.json
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
import 'package:jend_pro_mobile/features/purchases/data/purchases_repository.dart';
import 'package:jend_pro_mobile/features/purchases/domain/purchase_models.dart';
import 'package:jend_pro_mobile/features/suppliers/data/suppliers_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support.dart';

void main() {
  final skip = Env.isConfigured ? false : 'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY non fournis';

  test(
    'achats : brouillon, modification, commande, acompte, réception (stock + CMP), paiement, annulation',
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
      final suppliers = SuppliersRepository(client);
      final purchases = PurchasesRepository(client);

      await signUpForTest(
        auth,
        fullName: 'Test Achats',
        email: 'purchases-${DateTime.now().millisecondsSinceEpoch}@test.jendpro.local',
        password: 'motdepasse-test',
      );
      final bid = await business.createBusiness(name: 'Boutique Achats');
      final loc = await business.fetchDefaultLocationId(bid);
      final sedima = await suppliers.create(bid, {'name': 'Sedima'});
      final riz = await products.createProduct(
        bid,
        const NewProduct(name: 'Riz 25 kg', salePrice: 14500, costPrice: 11000),
      );
      final huile = await products.createProduct(bid, const NewProduct(name: 'Huile 5 L', salePrice: 6500));
      await inventory.setInitialStock(businessId: bid, productId: riz.id, locationId: loc, quantity: 10);

      DraftLine line(String id, String name, num q, int cost) =>
          DraftLine(productId: id, productName: name, unit: 'u', allowsFractional: false, quantity: q, unitCost: cost);

      // Brouillon puis modification (lignes remplacées en bloc).
      var draft = PurchaseDraft(supplier: sedima, locationId: loc, lines: [line(riz.id, 'Riz', 10, 12000)]);
      final id = await purchases.save(bid, draft);
      var p = await purchases.fetchPurchase(id);
      expect(p.status, PurchaseStatus.draft);
      expect(p.total, 120000);
      expect(p.number, startsWith('A-'));

      draft = PurchaseDraft(
        purchaseId: id,
        supplier: sedima,
        locationId: loc,
        lines: [line(riz.id, 'Riz', 10, 12000), line(huile.id, 'Huile', 6, 5000)],
        discount: 5000,
        supplierReference: 'FAC-118',
      );
      expect(await purchases.save(bid, draft), id);
      p = await purchases.fetchPurchase(id);
      expect(p.lines, hasLength(2));
      expect(p.subtotal, 150000);
      expect(p.total, 145000);
      expect(p.supplierReference, 'FAC-118');
      expect(p.supplierName, 'Sedima');

      // Commande + acompte (avant réception).
      await purchases.order(id);
      await purchases.recordPayment(id, amount: 45000, method: PaymentMethod.wave, locationId: loc, reference: 'W-1');
      await expectLater(
        purchases.cancel(id, reason: 'Erreur'),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'PURCHASE_HAS_PAYMENTS')),
      );

      // Réception : stock et coût moyen pondéré.
      await purchases.receive(id);
      p = await purchases.fetchPurchase(id);
      expect(p.status, PurchaseStatus.received);
      expect(p.remaining, 100000);
      final rizNow = await products.fetchProduct(riz.id);
      expect(rizNow.stockQuantity, 20);
      // CMP : (10 × 11 000 + 10 × 12 000) / 20 = 11 500.
      expect(rizNow.costPrice, 11500);
      expect((await products.fetchProduct(huile.id)).stockQuantity, 6);
      await expectLater(
        purchases.save(bid, draft),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'PURCHASE_NOT_EDITABLE')),
      );

      // Paiement du solde.
      await purchases.recordPayment(id, amount: 100000, method: PaymentMethod.cash, locationId: loc);
      p = await purchases.fetchPurchase(id);
      expect(p.fullyPaid, isTrue);
      expect(p.payments.map((x) => x.amount), [45000, 100000]);

      // Listes par segment.
      final second = await purchases.save(
        bid,
        PurchaseDraft(supplier: sedima, locationId: loc, lines: [line(huile.id, 'Huile', 2, 5000)]),
      );
      final open = await purchases.fetchPurchases(bid, segment: PurchaseSegment.open, offset: 0, limit: 20);
      expect(open.single.id, second);
      expect(await purchases.fetchPurchases(bid, segment: PurchaseSegment.unpaid, offset: 0, limit: 20), isEmpty);

      // Annulation d'un brouillon sans paiement.
      await purchases.cancel(second, reason: 'Doublon');
      expect((await purchases.fetchPurchase(second)).status, PurchaseStatus.cancelled);

      await auth.signOut();
      await client.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
