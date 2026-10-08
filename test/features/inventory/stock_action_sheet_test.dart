import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/features/inventory/application/inventory_providers.dart';
import 'package:jend_pro_mobile/features/inventory/domain/inventory_models.dart';
import 'package:jend_pro_mobile/features/inventory/presentation/stock_action_sheet.dart';
import 'package:jend_pro_mobile/features/products/domain/catalog_models.dart';
import 'package:mocktail/mocktail.dart';

class _Actions extends Mock implements InventoryActions {}

const _riz = Product(
  id: 'p1',
  name: 'Riz 25 kg',
  unit: 'sac',
  salePrice: 14500,
  trackStock: true,
  allowsFractionalQuantity: false,
  minStockLevel: 10,
  archived: false,
  stockQuantity: 21,
);

const _shop = StockLocation(id: 'shop', name: 'Boutique', isDefault: true, isWarehouse: false);
const _depot = StockLocation(id: 'depot', name: 'Dépôt', isDefault: false, isWarehouse: true);

void main() {
  late _Actions actions;

  setUpAll(() => registerFallbackValue(MovementType.adjustment));
  setUp(() {
    actions = _Actions();
    when(
      () => actions.adjust(
        productId: any(named: 'productId'),
        locationId: any(named: 'locationId'),
        type: any(named: 'type'),
        quantity: any(named: 'quantity'),
        reason: any(named: 'reason'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => actions.count(
        productId: any(named: 'productId'),
        locationId: any(named: 'locationId'),
        counted: any(named: 'counted'),
        reason: any(named: 'reason'),
      ),
    ).thenAnswer((_) async {});
  });

  Future<void> open(WidgetTester t, StockAction action, List<LocationStock> stock) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [inventoryActionsProvider.overrideWithValue(actions)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showStockActionSheet(context, action: action, product: _riz, stock: stock),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
  }

  Future<void> fill(WidgetTester t, {required String qty, String? reason}) async {
    await t.enterText(find.byType(TextFormField).at(0), qty);
    if (reason != null) await t.enterText(find.byType(TextFormField).at(1), reason);
    await t.pump();
  }

  Future<void> submit(WidgetTester t, String label) async {
    final button = find.widgetWithText(JpButton, label);
    await t.ensureVisible(button);
    await t.tap(button);
    await t.pumpAndSettle();
  }

  testWidgets('sortie : motif obligatoire, quantité négative, type perte', (t) async {
    await open(t, StockAction.remove, const [LocationStock(location: _shop, quantity: 21)]);
    await fill(t, qty: '3');
    expect(find.text('Nouveau stock : 18 sac'), findsOneWidget);
    await submit(t, 'Valider');
    expect(find.text('Le motif est obligatoire.'), findsOneWidget);

    await fill(t, qty: '3', reason: 'Sac percé');
    await submit(t, 'Valider');
    verify(
      () => actions.adjust(
        productId: 'p1',
        locationId: 'shop',
        type: MovementType.loss,
        quantity: -3,
        reason: 'Sac percé',
      ),
    ).called(1);
  });

  testWidgets('première entrée à un emplacement = stock initial (sans motif)', (t) async {
    await open(t, StockAction.add, const [
      LocationStock(location: _shop),
      LocationStock(location: _depot, quantity: 4),
    ]);
    expect(find.textContaining('stock initial'), findsOneWidget);
    await fill(t, qty: '12');
    await submit(t, 'Valider');
    verify(
      () => actions.adjust(productId: 'p1', locationId: 'shop', type: MovementType.initial, quantity: 12, reason: null),
    ).called(1);
  });

  testWidgets('inventaire : on envoie la quantité comptée et on montre l’écart', (t) async {
    await open(t, StockAction.count, const [LocationStock(location: _shop, quantity: 21)]);
    await fill(t, qty: '15');
    expect(find.text('Écart : −6 sac'), findsOneWidget);
    await submit(t, 'Enregistrer le comptage');
    verify(() => actions.count(productId: 'p1', locationId: 'shop', counted: 15, reason: null)).called(1);
  });

  testWidgets('stock insuffisant : la quantité disponible est affichée', (t) async {
    when(
      () => actions.adjust(
        productId: any(named: 'productId'),
        locationId: any(named: 'locationId'),
        type: any(named: 'type'),
        quantity: any(named: 'quantity'),
        reason: any(named: 'reason'),
      ),
    ).thenThrow(
      const AppFailure(
        FailureKind.conflict,
        'Stock insuffisant pour ce produit.',
        code: 'INSUFFICIENT_STOCK',
        detail: {'available': 2, 'requested': 5},
      ),
    );
    await open(t, StockAction.remove, const [LocationStock(location: _shop, quantity: 2)]);
    await fill(t, qty: '5', reason: 'Casse');
    await submit(t, 'Valider');
    expect(find.text('Stock insuffisant : 2 sac disponible(s).'), findsOneWidget);
  });

  test('StockRow : rupture et stock faible', () {
    StockRow row(num q, num min) => StockRow(
      productId: 'p',
      productName: 'x',
      unit: 'u',
      locationId: 'l',
      quantity: q,
      minLevel: min,
      allowsFractional: false,
    );
    expect(row(0, 5).isOut, isTrue);
    expect(row(-2, 0).isOut, isTrue);
    expect(row(5, 5).isLow, isTrue);
    expect(row(6, 5).isLow, isFalse);
    expect(row(3, 0).isLow, isFalse, reason: 'seuil 0 = pas d’alerte');
  });
}
