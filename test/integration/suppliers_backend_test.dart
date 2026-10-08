// Test d'intégration des fournisseurs contre un Supabase réel.
//   flutter test test/integration -j 1 --dart-define-from-file=env/dev.json
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/config/env.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/business/data/business_repository.dart';
import 'package:jend_pro_mobile/features/products/data/products_repository.dart';
import 'package:jend_pro_mobile/features/products/domain/catalog_models.dart';
import 'package:jend_pro_mobile/features/suppliers/data/suppliers_repository.dart';
import 'package:jend_pro_mobile/features/suppliers/domain/supplier_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final skip = Env.isConfigured ? false : 'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY non fournis';

  test(
    'fournisseurs : fiche, produits fournis, achat reçu, dette, archivage',
    () async {
      final client = SupabaseClient(
        Env.supabaseUrl,
        Env.supabasePublishableKey,
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      );
      final auth = AuthRepository(client);
      final business = BusinessRepository(client);
      final products = ProductsRepository(client);
      final suppliers = SuppliersRepository(client);

      await auth.signUp(
        fullName: 'Test Fournisseurs',
        email: 'suppliers-${DateTime.now().millisecondsSinceEpoch}@test.jendpro.local',
        password: 'motdepasse-test',
      );
      final bid = await business.createBusiness(name: 'Boutique Fournisseurs');
      final loc = await business.fetchDefaultLocationId(bid);
      final riz = await products.createProduct(bid, const NewProduct(name: 'Riz 25 kg', salePrice: 14500));

      final sedima = await suppliers.create(bid, {
        'name': 'Sedima Distribution',
        'contact_name': 'M. Diop',
        'phone': '33 820 11 22',
      });
      await suppliers.create(bid, {'name': 'Agro Sahel'});
      expect(sedima.phone, '338201122');

      final list = await suppliers.fetchSuppliers(bid, offset: 0, limit: 30);
      expect(list.map((s) => s.name), ['Agro Sahel', 'Sedima Distribution']);
      expect((await suppliers.fetchSuppliers(bid, query: 'diop', offset: 0, limit: 30)).single.id, sedima.id);

      // Produits fournis.
      await suppliers.linkProduct(bid, sedima.id, riz.id, supplierSku: 'SED-RZ25');
      await expectLater(
        suppliers.linkProduct(bid, sedima.id, riz.id),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'UNIQUE_VIOLATION')),
      );
      var linked = await suppliers.fetchProducts(bid, sedima.id);
      expect(linked.single.supplierSku, 'SED-RZ25');
      expect(linked.single.productName, 'Riz 25 kg');
      await suppliers.updateSku(sedima.id, riz.id, 'SED-RIZ');
      expect((await suppliers.fetchProducts(bid, sedima.id)).single.supplierSku, 'SED-RIZ');

      // Achat reçu partiellement payé → dette fournisseur (vue calculée) et dernier coût.
      final purchaseId = await client.rpc<String>(
        'save_purchase',
        params: {
          'p_business_id': bid,
          'p_purchase_id': null,
          'p_supplier_id': sedima.id,
          'p_location_id': loc,
          'p_items': [
            {'product_id': riz.id, 'quantity': 10, 'unit_cost': 12000},
          ],
        },
      );
      await client.rpc<dynamic>('receive_purchase', params: {'p_purchase_id': purchaseId});
      await client.rpc<dynamic>(
        'record_purchase_payment',
        params: {'p_purchase_id': purchaseId, 'p_amount': 50000, 'p_method': 'CASH', 'p_location_id': loc},
      );
      final balances = await suppliers.fetchBalances(bid);
      expect(balances[sedima.id]?.amountDue, 70000);
      expect((await suppliers.fetchBalances(bid, owedOnly: true)).keys, [sedima.id]);
      linked = await suppliers.fetchProducts(bid, sedima.id);
      expect(linked.single.lastCost, 12000);
      final purchases = await suppliers.fetchPurchases(bid, sedima.id);
      expect(purchases.single.status, 'RECEIVED');
      expect(purchases.single.remaining, 70000);

      // Modification, retrait du produit, archivage.
      expect((await suppliers.update(sedima.id, {'email': 'contact@sedima.sn'})).email, 'contact@sedima.sn');
      await suppliers.unlinkProduct(sedima.id, riz.id);
      expect(await suppliers.fetchProducts(bid, sedima.id), isEmpty);
      expect((await suppliers.setArchived(sedima.id, archived: true)).archived, isTrue);
      expect(
        (await suppliers.fetchSuppliers(bid, segment: SupplierSegment.archived, offset: 0, limit: 30)).single.id,
        sedima.id,
      );

      await auth.signOut();
      await client.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
