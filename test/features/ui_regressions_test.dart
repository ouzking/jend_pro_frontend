// Régressions signalées sur téléphone (Galaxy S22, barre de navigation à
// 3 boutons) : feuille « Fournisseur » d'un achat, sortie de la caisse.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/core/storage/preferences.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/business/domain/workspace.dart';
import 'package:jend_pro_mobile/features/inventory/application/inventory_providers.dart';
import 'package:jend_pro_mobile/features/inventory/domain/inventory_models.dart';
import 'package:jend_pro_mobile/features/products/application/catalog_providers.dart';
import 'package:jend_pro_mobile/features/purchases/presentation/purchase_editor_screen.dart';
import 'package:jend_pro_mobile/features/sales/application/pos_providers.dart';
import 'package:jend_pro_mobile/features/sales/domain/sale_models.dart';
import 'package:jend_pro_mobile/features/sales/presentation/pos_screen.dart';
import 'package:jend_pro_mobile/features/suppliers/data/suppliers_repository.dart';
import 'package:jend_pro_mobile/features/suppliers/domain/supplier_models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Suppliers extends Mock implements SuppliersRepository {}

class _Location extends PosLocationNotifier {
  @override
  String? build() => 'shop';
}

const _business = BusinessMembership(businessId: 'b1', businessName: 'Boutique', roleCode: 'OWNER', roleName: 'P');
const _dpr = 2.75;
const _navBar = 48.0;
const _screenHeight = 2340 / _dpr;

void main() {
  late SharedPreferences prefs;

  setUpAll(() => initializeDateFormatting('fr'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  void phone(WidgetTester t, {double keyboard = 0}) {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = _dpr;
    t.view.padding = const FakeViewPadding(top: 24 * _dpr, bottom: _navBar * _dpr);
    t.view.viewPadding = const FakeViewPadding(top: 24 * _dpr, bottom: _navBar * _dpr);
    t.view.viewInsets = FakeViewPadding(bottom: keyboard * _dpr);
    addTearDown(t.view.reset);
  }

  group('achat : feuille « Fournisseur »', () {
    late _Suppliers repo;

    Future<void> openSupplierSheet(WidgetTester t, int count) async {
      repo = _Suppliers();
      when(() => repo.fetchSuppliers(any(), query: any(named: 'query'), offset: 0, limit: 30)).thenAnswer(
        (_) async => [for (var i = 0; i < count; i++) Supplier(id: 's$i', name: 'Fournisseur $i', archived: false)],
      );
      await t.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            activeBusinessProvider.overrideWithValue(_business),
            permissionsProvider.overrideWithValue(const PermissionSet({Permission.purchasesCreate})),
            locationsProvider.overrideWith(
              (ref) async => const [StockLocation(id: 'shop', name: 'Boutique', isDefault: true, isWarehouse: false)],
            ),
            suppliersRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const PurchaseEditorScreen()),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Sans fournisseur').first);
      await t.pumpAndSettle();
    }

    testWidgets('hauteur stable, liste au-dessus de la barre de navigation', (t) async {
      phone(t);
      await openSupplierSheet(t, 3);
      final sheet = t.getRect(find.byType(BottomSheet));
      expect(sheet.height, greaterThan(_screenHeight * 0.6), reason: 'la feuille doit bien monter');
      final last = t.getRect(find.text('Fournisseur 2'));
      expect(last.bottom, lessThan(_screenHeight - _navBar));
    });

    testWidgets('longue liste : défilement, dernier fournisseur accessible', (t) async {
      phone(t);
      await openSupplierSheet(t, 30);
      await t.scrollUntilVisible(find.text('Fournisseur 29'), 300, scrollable: find.byType(Scrollable).last);
      expect(t.getRect(find.text('Fournisseur 29')).bottom, lessThan(_screenHeight - _navBar));
      await t.tap(find.text('Fournisseur 29'));
      await t.pumpAndSettle();
      expect(find.text('Fournisseur 29'), findsOneWidget, reason: 'fournisseur choisi affiché dans l’achat');
    });

    testWidgets('clavier ouvert : la recherche reste visible au-dessus', (t) async {
      phone(t, keyboard: 320);
      await openSupplierSheet(t, 30);
      final search = t.getRect(find.widgetWithText(JpTextField, 'Rechercher un fournisseur'));
      expect(search.bottom, lessThan(_screenHeight - 320));
      expect(search.top, greaterThan(0));
    });
  });

  testWidgets('caisse : « Quitter » ferme bien la caisse quand le panier n’est pas vide', (t) async {
    phone(t);
    const huile = SellableProduct(
      id: 'huile',
      name: 'Huile 5 L',
      unit: 'bidon',
      salePrice: 4250,
      trackStock: true,
      allowsFractional: false,
      stockQuantity: 5,
    );
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          activeBusinessProvider.overrideWithValue(_business),
          permissionsProvider.overrideWithValue(const PermissionSet({Permission.salesCreate})),
          posLocationProvider.overrideWith(_Location.new),
          locationsProvider.overrideWith(
            (ref) async => const [StockLocation(id: 'shop', name: 'Boutique', isDefault: true, isWarehouse: false)],
          ),
          categoriesProvider.overrideWith((ref) async => const []),
          posCatalogProvider.overrideWith((ref) async => const PosCatalog(products: [huile])),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PosScreen())),
                  child: const Text('ouvrir la caisse'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('ouvrir la caisse'));
    await t.pumpAndSettle();
    await t.tap(find.text('Huile 5 L').first);
    await t.pumpAndSettle();

    // Bouton de fermeture, puis « Quitter ».
    await t.tap(find.byTooltip('Fermer la caisse'));
    await t.pumpAndSettle();
    await t.tap(find.text('Quitter'));
    await t.pumpAndSettle();
    expect(find.byType(PosScreen), findsNothing);
    expect(find.text('ouvrir la caisse'), findsOneWidget);

    // Retour système (bouton ← d'Android), puis « Quitter » : même résultat ;
    // « Rester » garde la caisse ouverte.
    await t.tap(find.text('ouvrir la caisse'));
    await t.pumpAndSettle();
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    await nav.maybePop();
    await t.pumpAndSettle();
    await t.tap(find.text('Rester'));
    await t.pumpAndSettle();
    expect(find.byType(PosScreen), findsOneWidget);
    await nav.maybePop();
    await t.pumpAndSettle();
    await t.tap(find.text('Quitter'));
    await t.pumpAndSettle();
    expect(find.byType(PosScreen), findsNothing);
  });
}
