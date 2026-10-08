// Test d'intégration du stock contre un Supabase réel.
//   flutter test test/integration --dart-define-from-file=env/dev.json
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/config/env.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/business/data/business_repository.dart';
import 'package:jend_pro_mobile/features/inventory/data/inventory_repository.dart';
import 'package:jend_pro_mobile/features/inventory/domain/inventory_models.dart';
import 'package:jend_pro_mobile/features/products/data/products_repository.dart';
import 'package:jend_pro_mobile/features/products/domain/catalog_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final skip = Env.isConfigured ? false : 'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY non fournis';

  test(
    'stock : mouvements, inventaire, transfert, filtres, erreurs',
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

      await auth.signUp(
        fullName: 'Test Stock',
        email: 'stock-${DateTime.now().millisecondsSinceEpoch}@test.jendpro.local',
        password: 'motdepasse-test',
      );
      final bid = await business.createBusiness(name: 'Boutique Stock');
      await client.from('locations').insert({'business_id': bid, 'name': 'Dépôt', 'type': 'WAREHOUSE'});

      final locations = await inventory.fetchLocations(bid);
      expect(locations.first.isDefault, isTrue, reason: 'emplacement par défaut en premier');
      final shop = locations.first.id;
      final depot = locations.firstWhere((l) => l.isWarehouse).id;

      final riz = await products.createProduct(
        bid,
        const NewProduct(name: 'Riz 25 kg', salePrice: 14500, minStockLevel: 10),
      );
      final eau = await products.createProduct(bid, const NewProduct(name: 'Eau 1,5 L', salePrice: 400));

      Future<void> adjust(MovementType type, num qty, [String? reason]) => inventory.adjust(
        businessId: bid,
        productId: riz.id,
        locationId: shop,
        type: type,
        quantity: qty,
        reason: reason,
      );

      await inventory.setInitialStock(businessId: bid, productId: riz.id, locationId: shop, quantity: 20);
      await adjust(MovementType.adjustment, 5, 'Réassort');
      await adjust(MovementType.loss, -3, 'Sac percé');
      await adjust(MovementType.damage, -1, 'Humidité');
      await inventory.count(
        businessId: bid,
        productId: riz.id,
        locationId: shop,
        countedQuantity: 15,
        reason: 'Inventaire',
      );
      await inventory.transfer(
        businessId: bid,
        productId: riz.id,
        fromLocationId: shop,
        toLocationId: depot,
        quantity: 5,
      );

      // Eau : stock initial puis tout vendu « à la main » (rupture).
      await inventory.setInitialStock(businessId: bid, productId: eau.id, locationId: shop, quantity: 2);
      await inventory.adjust(
        businessId: bid,
        productId: eau.id,
        locationId: shop,
        type: MovementType.adjustment,
        quantity: -2,
        reason: 'Correction',
      );

      final perLocation = await inventory.fetchProductStock(bid, riz.id);
      expect({for (final s in perLocation) s.location.id: s.quantity}, {shop: 10, depot: 5});

      final movements = await inventory.fetchMovements(bid, riz.id, offset: 0, limit: 50);
      expect(movements.first.type, anyOf(MovementType.transferIn, MovementType.transferOut));
      expect(movements.map((m) => m.type).toSet(), {
        MovementType.initial,
        MovementType.adjustment,
        MovementType.loss,
        MovementType.damage,
        MovementType.transferOut,
        MovementType.transferIn,
      });
      final countMove = movements.firstWhere((m) => m.reason == 'Inventaire');
      expect(countMove.quantity, -6, reason: '21 → 15 compté');
      expect(countMove.quantityAfter, 15);

      final all = await inventory.fetchStock(bid, filter: StockFilter.all, offset: 0, limit: 30);
      expect(all.first.productName, 'Eau 1,5 L', reason: 'les plus critiques en premier');
      expect(all.first.isOut, isTrue);
      expect(all.length, 3);

      final out = await inventory.fetchStock(bid, filter: StockFilter.out, offset: 0, limit: 30);
      expect(out.single.productName, 'Eau 1,5 L');

      final low = await inventory.fetchStock(bid, filter: StockFilter.low, locationId: shop, offset: 0, limit: 30);
      expect(low.single.productName, 'Riz 25 kg');
      expect(low.single.unit, 'pièce');
      expect(low.single.quantity, 10);

      final depotOnly = await inventory.fetchStock(
        bid,
        filter: StockFilter.all,
        locationId: depot,
        offset: 0,
        limit: 30,
      );
      expect(depotOnly.single.quantity, 5);

      await expectLater(
        adjust(MovementType.loss, -1),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'REASON_REQUIRED')),
      );
      await expectLater(
        inventory.transfer(businessId: bid, productId: riz.id, fromLocationId: depot, toLocationId: shop, quantity: 50),
        throwsA(
          isA<AppFailure>()
              .having((f) => f.code, 'code', 'INSUFFICIENT_STOCK')
              .having((f) => f.detail?['available'], 'available', 5),
        ),
      );

      await auth.signOut();
      await client.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
