// Caisse : envoi des ventes, file hors ligne, rejeu, catalogue en cache.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/domain/payment_method.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/core/storage/preferences.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/business/domain/workspace.dart';
import 'package:jend_pro_mobile/features/inventory/application/inventory_providers.dart';
import 'package:jend_pro_mobile/features/inventory/domain/inventory_models.dart';
import 'package:jend_pro_mobile/features/sales/application/pos_providers.dart';
import 'package:jend_pro_mobile/features/sales/data/offline_sales_queue.dart';
import 'package:jend_pro_mobile/features/sales/data/sales_repository.dart';
import 'package:jend_pro_mobile/features/sales/domain/cart.dart';
import 'package:jend_pro_mobile/features/sales/domain/sale_models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo extends Mock implements SalesRepository {}

const _network = AppFailure(FailureKind.network, 'Connexion internet indisponible.', code: 'NETWORK');
const _stock = AppFailure(FailureKind.conflict, 'Stock insuffisant pour ce produit.', code: 'INSUFFICIENT_STOCK');

const _riz = SellableProduct(
  id: 'riz',
  name: 'Riz 5 kg',
  unit: 'sac',
  salePrice: 4500,
  trackStock: true,
  allowsFractional: false,
  barcode: '600123',
  categoryId: 'cereales',
);
const _huile = SellableProduct(
  id: 'huile',
  name: 'Huile 1 L',
  unit: 'bouteille',
  salePrice: 1500,
  trackStock: true,
  allowsFractional: false,
);

PendingSale _pending(String ref, {String? error}) => PendingSale(
  request: SaleRequest(
    businessId: 'b1',
    clientReference: ref,
    locationId: 'loc',
    items: const [
      {'product_id': 'riz', 'quantity': 1},
    ],
  ),
  createdAt: DateTime(2026, 10, 9),
  total: 4500,
  lastError: error,
);

void main() {
  late _Repo repo;
  late SharedPreferences prefs;

  setUpAll(() => registerFallbackValue(_pending('x').request));

  Future<ProviderContainer> make({Map<String, Object> stored = const {}}) async {
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    repo = _Repo();
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        salesRepositoryProvider.overrideWithValue(repo),
        activeBusinessProvider.overrideWithValue(
          const BusinessMembership(businessId: 'b1', businessName: 'B', roleCode: 'CASHIER', roleName: 'Caissier'),
        ),
        locationsProvider.overrideWith(
          (ref) async => const [
            StockLocation(id: 'loc', name: 'Boutique', isDefault: true, isWarehouse: false),
            StockLocation(id: 'depot', name: 'Dépôt', isDefault: false, isWarehouse: true),
          ],
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Settlement cash(int total) => Settlement.compute(
    total: total,
    tendered: [PaymentEntry(method: PaymentMethod.cash, amount: total)],
  );

  group('encaissement', () {
    test('en ligne : vente enregistrée, panier vidé', () async {
      final c = await make();
      when(() => repo.createSale(any())).thenAnswer((_) async => 'sale-1');
      c.read(cartProvider.notifier).add(_riz, quantity: 2);
      final cart = c.read(cartProvider);
      final out = await c
          .read(saleSubmitterProvider)
          .submit(cart: cart, settlement: cash(cart.total), locationId: 'loc');
      expect(out, isA<SaleRecorded>().having((s) => s.saleId, 'saleId', 'sale-1'));
      expect(c.read(cartProvider).lines, isEmpty);
      final sent = verify(() => repo.createSale(captureAny())).captured.single as SaleRequest;
      expect(sent.items.single, {'product_id': 'riz', 'quantity': 2}, reason: 'jamais de prix envoyé');
    });

    test('coupure réseau : vente gardée avec sa référence, panier vidé', () async {
      final c = await make();
      when(() => repo.createSale(any())).thenAnswer((_) async => throw _network);
      c.read(cartProvider.notifier).add(_riz);
      final cart = c.read(cartProvider);
      final out = await c
          .read(saleSubmitterProvider)
          .submit(cart: cart, settlement: cash(cart.total), locationId: 'loc');
      expect(out, isA<SaleQueued>());
      final queued = c.read(pendingSalesProvider).single;
      expect(queued.request.clientReference, (out as SaleQueued).pending.request.clientReference);
      expect(queued.total, 4500);
      expect(c.read(cartProvider).lines, isEmpty);
      expect(prefs.getString('pending_sales_v1'), contains(queued.request.clientReference));
    });

    test('refus métier : erreur remontée, panier conservé, rien en file', () async {
      final c = await make();
      when(() => repo.createSale(any())).thenAnswer((_) async => throw _stock);
      c.read(cartProvider.notifier).add(_riz);
      final cart = c.read(cartProvider);
      await expectLater(
        c.read(saleSubmitterProvider).submit(cart: cart, settlement: cash(cart.total), locationId: 'loc'),
        throwsA(_stock),
      );
      expect(c.read(cartProvider).lines.single.product.id, 'riz');
      expect(c.read(pendingSalesProvider), isEmpty);
    });
  });

  group('rejeu de la file', () {
    Future<ProviderContainer> withQueue(List<PendingSale> sales) async {
      final c = await make();
      for (final s in sales) {
        await c.read(pendingSalesProvider.notifier).enqueue(s);
      }
      return c;
    }

    test('dans l’ordre ; un refus métier bloque la vente et on continue', () async {
      final c = await withQueue([_pending('a'), _pending('b'), _pending('c')]);
      final order = <String>[];
      when(() => repo.createSale(any())).thenAnswer((inv) async {
        final r = inv.positionalArguments.single as SaleRequest;
        order.add(r.clientReference);
        if (r.clientReference == 'b') throw _stock;
        return 'id-${r.clientReference}';
      });
      expect(await c.read(pendingSalesProvider.notifier).sync(), 2);
      expect(order, ['a', 'b', 'c']);
      final left = c.read(pendingSalesProvider).single;
      expect((left.request.clientReference, left.blocked, left.lastError), ('b', true, _stock.message));

      // Bloquée : ignorée par le rejeu automatique, renvoyée sur demande.
      expect(await c.read(pendingSalesProvider.notifier).sync(), 0);
      when(() => repo.createSale(any())).thenAnswer((_) async => 'id-b');
      expect(await c.read(pendingSalesProvider.notifier).sync(includeBlocked: true), 1);
      expect(c.read(pendingSalesProvider), isEmpty);
    });

    test('nouvelle coupure : arrêt immédiat, rien de perdu', () async {
      final c = await withQueue([_pending('a'), _pending('b')]);
      when(() => repo.createSale(any())).thenAnswer((_) async => throw _network);
      expect(await c.read(pendingSalesProvider.notifier).sync(), 0);
      verify(() => repo.createSale(any())).called(1);
      expect(c.read(pendingSalesProvider).map((p) => (p.request.clientReference, p.blocked)), [
        ('a', false),
        ('b', false),
      ]);
    });

    test('pas de double envoi pendant un rejeu en cours', () async {
      final c = await withQueue([_pending('a')]);
      final gate = Completer<String>();
      when(() => repo.createSale(any())).thenAnswer((_) => gate.future);
      final first = c.read(pendingSalesProvider.notifier).sync();
      expect(await c.read(pendingSalesProvider.notifier).sync(), 0);
      gate.complete('id-a');
      expect(await first, 1);
      verify(() => repo.createSale(any())).called(1);
    });

    test('file conservée entre deux lancements de l’app', () async {
      final c = await withQueue([_pending('a')]);
      final saved = prefs.getString('pending_sales_v1')!;
      final again = await make(stored: {'pending_sales_v1': saved});
      expect(again.read(pendingSalesProvider).single.request.clientReference, 'a');
      expect(c.read(pendingSalesProvider).length, 1);
      expect(OfflineSalesQueue(prefs).forBusiness('autre'), isEmpty);
    });
  });

  group('catalogue de caisse hors ligne', () {
    test('en ligne : grille complète mise en cache', () async {
      final c = await make();
      when(
        () => repo.fetchSellable('b1', query: '', categoryId: null, ids: null),
      ).thenAnswer((_) async => [_riz, _huile]);
      c.listen(posCatalogProvider, (_, _) {});
      final catalog = await c.read(posCatalogProvider.future);
      expect((catalog.products.length, catalog.fromCache), (2, false));
      expect(prefs.getString('pos_catalog:b1'), contains('Riz 5 kg'));
    });

    test('hors ligne : recherche dans le cache (nom ou code-barres)', () async {
      final c = await make();
      when(
        () => repo.fetchSellable(
          'b1',
          query: any(named: 'query'),
          categoryId: any(named: 'categoryId'),
          ids: any(named: 'ids'),
        ),
      ).thenAnswer((_) async => [_riz, _huile]);
      c.listen(posCatalogProvider, (_, _) {});
      await c.read(posCatalogProvider.future);

      when(
        () => repo.fetchSellable(
          'b1',
          query: any(named: 'query'),
          categoryId: any(named: 'categoryId'),
          ids: any(named: 'ids'),
        ),
      ).thenAnswer((_) async => throw _network);
      c.read(posQueryProvider.notifier).text(' huile ');
      var catalog = await c.read(posCatalogProvider.future);
      expect((catalog.fromCache, catalog.products.single.id), (true, 'huile'));

      c.read(posQueryProvider.notifier).text('600123');
      catalog = await c.read(posCatalogProvider.future);
      expect(catalog.products.single.id, 'riz');
    });

    test('hors ligne sans cache : erreur affichée ; erreur métier jamais masquée', () async {
      final c = await make();
      when(
        () => repo.fetchSellable(
          'b1',
          query: any(named: 'query'),
          categoryId: any(named: 'categoryId'),
          ids: any(named: 'ids'),
        ),
      ).thenAnswer((_) async => throw _network);
      c.listen(posCatalogProvider, (_, _) {});
      await expectLater(c.read(posCatalogProvider.future), throwsA(_network));
    });
  });

  test('emplacement et favoris mémorisés par commerce', () async {
    final c = await make(stored: {'pos_location:b1': 'depot'});
    c.listen(posLocationProvider, (_, _) {});
    await c.read(locationsProvider.future);
    expect(c.read(posLocationProvider), 'depot');
    await c.read(posLocationProvider.notifier).select('loc');
    expect(prefs.getString('pos_location:b1'), 'loc');

    await c.read(favoritesProvider.notifier).toggle('riz');
    expect(prefs.getStringList('pos_favorites:b1'), ['riz']);
    await c.read(favoritesProvider.notifier).toggle('riz');
    expect(c.read(favoritesProvider), isEmpty);
  });
}
