// Test d'intégration des paramètres contre un Supabase réel.
//   flutter test test/integration -j 1 --dart-define-from-file=env/dev.json
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/config/env.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/business/data/business_repository.dart';
import 'package:jend_pro_mobile/features/inventory/data/inventory_repository.dart';
import 'package:jend_pro_mobile/features/products/data/products_repository.dart';
import 'package:jend_pro_mobile/features/products/domain/catalog_models.dart';
import 'package:jend_pro_mobile/features/settings/data/settings_repository.dart';
import 'package:jend_pro_mobile/features/settings/domain/settings_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Matcher _failure(String code) => isA<AppFailure>().having((f) => f.code, 'code', code);

void main() {
  final skip = Env.isConfigured ? false : 'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY non fournis';

  test(
    'paramètres : commerce, fuseau, emplacements, formules, abonnement, profil',
    () async {
      final client = SupabaseClient(
        Env.supabaseUrl,
        Env.supabasePublishableKey,
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      );
      final auth = AuthRepository(client);
      await auth.signUp(
        fullName: 'Test Réglages',
        email: 'settings-${DateTime.now().millisecondsSinceEpoch}@test.jendpro.local',
        password: 'motdepasse-test',
      );
      final business = BusinessRepository(client);
      final settings = SettingsRepository(client);
      final bid = await business.createBusiness(name: 'Boutique Réglages');

      // Fiche du commerce.
      var s = await settings.fetchBusiness(bid);
      expect((s.timezone, s.currencyCode, s.allowNegativeStock), ('Africa/Dakar', 'XOF', false));
      s = await settings.updateBusiness(bid, {
        'name': 'Boutique Réglée',
        'ninea': '0123456 2G3',
        'city': 'Thiès',
        'timezone': 'Africa/Abidjan',
        'allow_negative_stock': true,
      });
      expect(
        (s.name, s.ninea, s.city, s.timezone, s.allowNegativeStock),
        ('Boutique Réglée', '0123456 2G3', 'Thiès', 'Africa/Abidjan', true),
      );
      await expectLater(
        settings.updateBusiness(bid, {'timezone': 'Mars/Olympus'}),
        throwsA(_failure('INVALID_TIMEZONE')),
      );

      // Emplacements : par défaut non archivable, dépôt avec stock non archivable.
      var locations = await settings.fetchLocations(bid);
      final main = locations.single;
      expect((main.isDefault, main.kind), (true, LocationKind.store));
      await expectLater(settings.setLocationArchived(main.id, archived: true), throwsA(isA<AppFailure>()));

      final status = await business.fetchSubscription(bid);
      final maxLocations = status!.limits.locations;
      expect(status.usage.locations, 1);

      if (maxLocations != null && maxLocations <= 1) {
        await expectLater(
          settings.createLocation(bid, name: 'Dépôt', kind: LocationKind.warehouse),
          throwsA(_failure('PLAN_LIMIT_REACHED')),
        );
      } else {
        final depot = await settings.createLocation(
          bid,
          name: ' Dépôt Pikine ',
          kind: LocationKind.warehouse,
          address: 'Zone industrielle',
        );
        expect((depot.name, depot.kind, depot.isDefault), ('Dépôt Pikine', LocationKind.warehouse, false));
        final renamed = await settings.updateLocation(depot.id, name: 'Dépôt central', kind: LocationKind.warehouse);
        expect((renamed.name, renamed.address), ('Dépôt central', null));

        final product = await ProductsRepository(
          client,
        ).createProduct(bid, const NewProduct(name: 'Riz', salePrice: 500));
        await InventoryRepository(
          client,
        ).setInitialStock(businessId: bid, productId: product.id, locationId: depot.id, quantity: 3);
        await expectLater(
          settings.setLocationArchived(depot.id, archived: true),
          throwsA(_failure('LOCATION_HAS_STOCK')),
        );

        final empty = await settings.createLocation(bid, name: 'Kiosque', kind: LocationKind.store);
        expect((await settings.setLocationArchived(empty.id, archived: true)).archived, isTrue);
        locations = await settings.fetchLocations(bid);
        expect(locations.where((l) => !l.archived).length, 2);
        expect((await business.fetchSubscription(bid))!.usage.locations, 2);
      }

      // Formules publiques (ordre d'affichage, Entreprise masquée).
      final plans = await settings.fetchPlans();
      expect(plans.map((p) => p.code), ['FREE', 'STARTER', 'PRO', 'BUSINESS']);
      expect(plans.last.limits.products, isNull, reason: 'illimité');

      // Profil.
      await settings.updateMyProfile(fullName: '  Awa Diop ', phone: '771234567');
      final profile = await auth.fetchProfile();
      expect((profile!.fullName, profile.phone), ('Awa Diop', '771234567'));

      await auth.signOut();
      await client.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
