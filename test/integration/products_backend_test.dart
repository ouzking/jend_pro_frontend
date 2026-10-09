// Test d'intégration du catalogue contre un Supabase réel.
//   flutter test test/integration --dart-define-from-file=env/dev.json
@Tags(['integration'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/config/env.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/business/data/business_repository.dart';
import 'package:jend_pro_mobile/features/inventory/data/inventory_repository.dart';
import 'package:jend_pro_mobile/features/products/data/products_repository.dart';
import 'package:jend_pro_mobile/features/products/domain/catalog_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support.dart';

// PNG 1×1 transparent.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  final skip = Env.isConfigured ? false : 'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY non fournis';

  test(
    'catalogue : liste, recherche, détail, modification, coût, photo, archivage',
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

      await signUpForTest(
        auth,
        fullName: 'Test Catalogue',
        email: 'catalog-${DateTime.now().millisecondsSinceEpoch}@test.jendpro.local',
        password: 'motdepasse-test',
      );
      final bid = await business.createBusiness(name: 'Boutique Catalogue');
      final loc = await business.fetchDefaultLocationId(bid);
      final boissons = await products.createCategory(bid, 'Boissons');

      final bissap = await products.createProduct(
        bid,
        NewProduct(
          name: 'Bissap 1 L',
          salePrice: 1500,
          costPrice: 900,
          unit: 'bouteille',
          categoryId: boissons.id,
          sku: 'BIS-1L',
          barcode: '6001234567890',
          minStockLevel: 10,
          description: 'Fait maison',
        ),
      );
      await products.createProduct(bid, const NewProduct(name: 'Livraison', salePrice: 500, trackStock: false));
      await inventory.setInitialStock(businessId: bid, productId: bissap.id, locationId: loc, quantity: 6);

      // Liste : jointures catégorie, stock (somme), coût.
      final page = await products.fetchProducts(bid, const ProductFilter(), offset: 0, limit: 30);
      expect(page.map((p) => p.name), ['Bissap 1 L', 'Livraison']);
      final b = page.first;
      expect(b.categoryName, 'Boissons');
      expect(b.stockQuantity, 6);
      expect(b.stockLevel, StockLevel.low, reason: '6 ≤ seuil 10');
      expect(b.costPrice, 900);
      expect(b.unitMargin, 600);
      expect(page.last.stockLevel, StockLevel.notTracked);

      // Recherche nom / SKU / code-barres, saisie « dangereuse » neutralisée.
      Future<List<String>> search(String q) async => (await products.fetchProducts(
        bid,
        ProductFilter(query: q),
        offset: 0,
        limit: 30,
      )).map((p) => p.name).toList();
      expect(await search('bissap'), ['Bissap 1 L']);
      expect(await search('bis-1'), ['Bissap 1 L']);
      expect(await search('6001234567890'), ['Bissap 1 L']);
      expect(await search('liv'), ['Livraison']);
      expect(await search('a,b)(*'), isA<List<String>>());

      // Filtre catégorie.
      final filtered = await products.fetchProducts(bid, ProductFilter(categoryId: boissons.id), offset: 0, limit: 30);
      expect(filtered.single.id, bissap.id);

      // Scanner.
      expect((await products.findByBarcode(bid, '600 1234 567890'))?.id, bissap.id);
      expect(await products.findByBarcode(bid, '000'), isNull);

      // Modification (colonnes autorisées seulement) + coût.
      final updated = await products.updateProduct(bissap.id, {'sale_price': 1750, 'name': 'Bissap rouge 1 L'});
      expect(updated.salePrice, 1750);
      await products.setCost(bissap.id, 1000);
      expect((await products.fetchProduct(bissap.id)).costPrice, 1000);

      // Unicité du code-barres.
      await expectLater(
        products.createProduct(bid, const NewProduct(name: 'Doublon', salePrice: 1, barcode: '6001234567890')),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'UNIQUE_VIOLATION')),
      );

      // Photo.
      final withImage = await products.uploadImage(bid, updated, _png, mimeType: 'image/png');
      expect(withImage.imagePath, startsWith('$bid/${bissap.id}/'));
      expect(products.publicImageUrl(withImage.imagePath!), contains('/product-images/'));

      // Archivage / réactivation.
      await products.setArchived(bissap.id, archived: true);
      final archived = await products.fetchProducts(
        bid,
        const ProductFilter(status: ProductStatusFilter.archived),
        offset: 0,
        limit: 30,
      );
      expect(archived.single.id, bissap.id);
      await products.setArchived(bissap.id, archived: false);
      expect((await products.fetchProduct(bissap.id)).archived, isFalse);

      // Catégories : renommer, archiver.
      await products.renameCategory(boissons.id, 'Jus et boissons');
      expect((await products.fetchCategories(bid)).single.name, 'Jus et boissons');
      await products.archiveCategory(boissons.id);
      expect(await products.fetchCategories(bid), isEmpty);

      await auth.signOut();
      await client.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
