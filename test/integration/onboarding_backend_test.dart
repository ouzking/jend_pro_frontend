// Test d'intégration contre un Supabase réel (backend local en général).
// Ignoré tant que SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY ne sont pas fournis :
//   flutter test test/integration --dart-define-from-file=env/dev.json
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/config/env.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/business/data/business_repository.dart';
import 'package:jend_pro_mobile/features/inventory/data/inventory_repository.dart';
import 'package:jend_pro_mobile/features/products/data/products_repository.dart';
import 'package:jend_pro_mobile/features/products/domain/catalog_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final skip = Env.isConfigured ? false : 'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY non fournis';

  test(
    'parcours d’onboarding complet contre le backend',
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

      // 1. Inscription (confirmation e-mail désactivée en local).
      final email = 'onboarding-${DateTime.now().millisecondsSinceEpoch}@test.jendpro.local';
      final needsConfirmation = await auth.signUp(
        fullName: 'Test Onboarding',
        email: email,
        password: 'motdepasse-test',
      );
      expect(needsConfirmation, isFalse, reason: 'le backend local ouvre la session directement');
      final profile = await auth.fetchProfile();
      expect(profile?.fullName, 'Test Onboarding', reason: 'trigger profiles');

      // 2. Commerce + rôle OWNER + permissions.
      final userId = client.auth.currentUser!.id;
      expect(await business.fetchMemberships(userId), isEmpty);
      final businessId = await business.createBusiness(name: 'Boutique Test', phone: '771234567', city: 'Dakar');
      final memberships = await business.fetchMemberships(userId);
      expect(memberships.single.roleCode, 'OWNER');
      final permissions = PermissionSet(await business.fetchPermissions(businessId));
      expect(permissions.can(Permission.settingsManage), isTrue);
      expect(permissions.can(Permission.inventoryAdjust), isTrue);
      final subscription = await business.fetchSubscription(businessId);
      expect(subscription?.status, 'TRIALING');

      // 3. Informations (champs modifiés seulement) — `.select()` prouve l'écriture.
      final updated = await business.updateProfile(businessId, {
        'legal_name': 'Boutique Test SARL',
        'ninea': '0012345',
      });
      expect(updated.legalName, 'Boutique Test SARL');

      // 4. Catégories idempotentes (insensibles à la casse).
      final cats = await products.ensureCategories(businessId, ['Boissons', 'Épicerie']);
      expect(cats.map((c) => c.name), ['Boissons', 'Épicerie']);
      final again = await products.ensureCategories(businessId, ['boissons']);
      expect(again.single.id, cats.first.id);

      // 5. Produit + coût d'achat.
      final riz = await products.createProduct(
        businessId,
        NewProduct(name: 'Riz 5 kg', salePrice: 4500, costPrice: 3800, unit: 'sac', categoryId: cats[1].id),
      );
      expect(riz.salePrice, 4500);
      final cost = await client.from('product_costs').select('cost_price').eq('product_id', riz.id).single();
      expect(cost['cost_price'], 3800);

      // 6. Stock initial à l'emplacement par défaut, une seule fois.
      final locationId = await business.fetchDefaultLocationId(businessId);
      await inventory.setInitialStock(businessId: businessId, productId: riz.id, locationId: locationId, quantity: 20);
      final stock = await client.from('inventory').select('quantity').eq('product_id', riz.id).single();
      expect(num.parse('${stock['quantity']}'), 20);
      await expectLater(
        inventory.setInitialStock(businessId: businessId, productId: riz.id, locationId: locationId, quantity: 5),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'INITIAL_ALREADY_SET')),
      );

      // 7. Quantité fractionnaire refusée pour un produit vendu à l'unité.
      await expectLater(
        inventory.setInitialStock(businessId: businessId, productId: riz.id, locationId: locationId, quantity: 1.5),
        throwsA(isA<AppFailure>()),
      );

      await auth.signOut();
      await client.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
