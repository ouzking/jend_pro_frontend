import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/domain/payment_method.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/core/storage/preferences.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/business/domain/workspace.dart';
import 'package:jend_pro_mobile/features/sales/application/pos_providers.dart';
import 'package:jend_pro_mobile/features/sales/data/sales_repository.dart';
import 'package:jend_pro_mobile/features/sales/domain/cart.dart';
import 'package:jend_pro_mobile/features/sales/domain/sale_models.dart';
import 'package:jend_pro_mobile/features/sales/presentation/checkout_panel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo extends Mock implements SalesRepository {}

class _Location extends PosLocationNotifier {
  @override
  String? build() => 'shop';
}

const _business = BusinessMembership(businessId: 'b1', businessName: 'Boutique', roleCode: 'OWNER', roleName: 'P');
const _huile = SellableProduct(
  id: 'huile',
  name: 'Huile 5 L',
  unit: 'bidon',
  salePrice: 4250,
  trackStock: true,
  allowsFractional: false,
);
const _network = AppFailure(FailureKind.network, 'Pas de connexion', code: 'NETWORK');
const _stock = AppFailure(FailureKind.conflict, 'Stock insuffisant pour ce produit.', code: 'INSUFFICIENT_STOCK');

void main() {
  late _Repo repo;
  late SharedPreferences prefs;

  setUpAll(
    () => registerFallbackValue(const SaleRequest(businessId: '', clientReference: '', locationId: '', items: [])),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repo = _Repo();
  });

  ProviderContainer container({Set<String> permissions = const {Permission.salesCreate}}) {
    final c = ProviderContainer(
      // Pas de relance automatique en test (minuteurs en attente).
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        activeBusinessProvider.overrideWithValue(_business),
        permissionsProvider.overrideWithValue(PermissionSet(permissions)),
        salesRepositoryProvider.overrideWithValue(repo),
        posLocationProvider.overrideWith(_Location.new),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Settlement exact(Cart cart) => Settlement.compute(
    total: cart.total,
    tendered: [PaymentEntry(method: PaymentMethod.cash, amount: cart.total)],
  );

  group('envoi et file hors ligne', () {
    test('coupure réseau : vente gardée (même référence), panier vidé', () async {
      final c = container();
      when(() => repo.createSale(any())).thenThrow(_network);
      c.read(cartProvider.notifier).add(_huile);
      final cart = c.read(cartProvider);

      final outcome = await c
          .read(saleSubmitterProvider)
          .submit(cart: cart, settlement: exact(cart), locationId: 'shop');

      expect(outcome, isA<SaleQueued>());
      expect(c.read(cartProvider).isEmpty, isTrue);
      final pending = c.read(pendingSalesProvider);
      expect(pending, hasLength(1));
      expect(pending.single.request.items, [
        {'product_id': 'huile', 'quantity': 1},
      ]);
      expect(pending.single.request.payments.single['amount'], 4250);
    });

    test('synchronisation : rejoue avec la même référence puis vide la file', () async {
      final c = container();
      when(() => repo.createSale(any())).thenThrow(_network);
      c.read(cartProvider.notifier).add(_huile);
      final cart = c.read(cartProvider);
      await c.read(saleSubmitterProvider).submit(cart: cart, settlement: exact(cart), locationId: 'shop');
      final reference = c.read(pendingSalesProvider).single.request.clientReference;

      when(() => repo.createSale(any())).thenAnswer((_) async => 'sale-1');
      expect(await c.read(pendingSalesProvider.notifier).sync(), 1);
      expect(c.read(pendingSalesProvider), isEmpty);
      final sent = verify(() => repo.createSale(captureAny())).captured.last as SaleRequest;
      expect(sent.clientReference, reference);
    });

    test('refus métier au rejeu : vente bloquée, les suivantes continuent', () async {
      final c = container();
      when(() => repo.createSale(any())).thenThrow(_network);
      for (var i = 0; i < 2; i++) {
        c.read(cartProvider.notifier).add(_huile);
        final cart = c.read(cartProvider);
        await c.read(saleSubmitterProvider).submit(cart: cart, settlement: exact(cart), locationId: 'shop');
      }
      final first = c.read(pendingSalesProvider).first.request.clientReference;
      when(() => repo.createSale(any())).thenAnswer((inv) async {
        final r = inv.positionalArguments.first as SaleRequest;
        if (r.clientReference == first) throw _stock;
        return 'ok';
      });

      expect(await c.read(pendingSalesProvider.notifier).sync(), 1);
      final left = c.read(pendingSalesProvider);
      expect(left.single.blocked, isTrue);
      expect(left.single.lastError, contains('Stock insuffisant'));
    });

    test('erreur métier à l’encaissement : remontée, rien en file, panier conservé', () async {
      final c = container();
      when(() => repo.createSale(any())).thenThrow(_stock);
      c.read(cartProvider.notifier).add(_huile);
      final cart = c.read(cartProvider);
      await expectLater(
        c.read(saleSubmitterProvider).submit(cart: cart, settlement: exact(cart), locationId: 'shop'),
        throwsA(isA<AppFailure>()),
      );
      expect(c.read(pendingSalesProvider), isEmpty);
      expect(c.read(cartProvider).isEmpty, isFalse);
    });
  });

  group('écran d’encaissement', () {
    Future<ProviderContainer> pump(WidgetTester t, {Set<String> permissions = const {Permission.salesCreate}}) async {
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final c = container(permissions: permissions);
      c.read(cartProvider.notifier).add(_huile);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(theme: AppTheme.light(), home: const CheckoutScreen()),
        ),
      );
      await t.pumpAndSettle();
      return c;
    }

    testWidgets('paiement exact par défaut : une seule pression pour valider', (t) async {
      when(() => repo.createSale(any())).thenAnswer((_) async => 'sale-1');
      when(() => repo.fetchSale(any())).thenThrow(_network);
      await pump(t);
      expect(find.textContaining('Montant exact'), findsOneWidget);
      await t.tap(find.textContaining('Valider'));
      await t.pumpAndSettle();
      final sent = verify(() => repo.createSale(captureAny())).captured.single as SaleRequest;
      expect(sent.payments, [
        {'method': 'CASH', 'amount': 4250},
      ]);
      expect(find.text('Vente enregistrée'), findsOneWidget);
    });

    testWidgets('espèces : la monnaie à rendre s’affiche', (t) async {
      await pump(t);
      await t.tap(find.text('Autre montant'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).last, '5000');
      await t.pumpAndSettle();
      // Récapitulatif en bas de liste (construite à la demande).
      await t.scrollUntilVisible(find.text('Monnaie à rendre'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Monnaie à rendre'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'750 FCFA')), findsOneWidget);
    });

    testWidgets('reste dû sans client : vente bloquée avec explication', (t) async {
      await pump(t, permissions: const {Permission.salesCreate, Permission.salesCredit, Permission.customersRead});
      await t.tap(find.text('Autre montant'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).last, '1000');
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Valider'));
      await t.pumpAndSettle();
      expect(find.textContaining('Choisissez un client'), findsOneWidget);
      verifyNever(() => repo.createSale(any()));
    });
  });
}
