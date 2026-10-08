import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/inventory/application/inventory_providers.dart';
import 'package:jend_pro_mobile/features/purchases/application/purchase_providers.dart';
import 'package:jend_pro_mobile/features/purchases/domain/purchase_models.dart';
import 'package:jend_pro_mobile/features/purchases/presentation/purchase_detail_screen.dart';
import 'package:jend_pro_mobile/features/purchases/presentation/purchase_editor_screen.dart';
import 'package:mocktail/mocktail.dart';

class _Actions extends Mock implements PurchaseActions {}

DraftLine _line(String id, num q, int cost) =>
    DraftLine(productId: id, productName: id, unit: 'u', allowsFractional: true, quantity: q, unitCost: cost);

Purchase _purchase(PurchaseStatus status, {int paid = 0}) => Purchase(
  id: 'p1',
  number: 'A-000014',
  status: status,
  subtotal: 120000,
  discount: 0,
  total: 120000,
  amountPaid: paid,
  locationId: 'loc',
  createdAt: DateTime(2026, 10, 8),
  supplierName: 'Sedima',
  lines: const [
    PurchaseLine(
      productId: 'riz',
      productName: 'Riz 25 kg',
      unit: 'sac',
      quantity: 10,
      unitCost: 12000,
      lineTotal: 120000,
      allowsFractional: false,
    ),
  ],
);

const _all = PermissionSet({
  Permission.purchasesRead,
  Permission.purchasesCreate,
  Permission.purchasesReceive,
  Permission.purchasesPayments,
  Permission.purchasesCancel,
});

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  group('PurchaseDraft', () {
    test('un produit une seule fois ; totaux arrondis ; remise bornée', () {
      var d = const PurchaseDraft().upsertLine(_line('riz', 10, 12000)).upsertLine(_line('riz', 12, 11500));
      expect(d.lines.single.quantity, 12);
      d = d.upsertLine(_line('sel', 2.5, 333));
      expect(d.subtotal, 12 * 11500 + 833, reason: '2,5 × 333 = 832,5 → 833');
      expect(d.copyWith(discount: 999999).total, 0);
      expect(d.removeLine('riz').lines.single.productId, 'sel');
      expect(d.lines.first.toJson(), {'product_id': 'riz', 'quantity': 12, 'unit_cost': 11500});
    });
  });

  Future<void> pumpDetail(WidgetTester t, Purchase p, PermissionSet perms) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          permissionsProvider.overrideWithValue(perms),
          activeBusinessProvider.overrideWithValue(null),
          purchaseDetailProvider('p1').overrideWith((ref) async => p),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const PurchaseDetailScreen(purchaseId: 'p1'),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  group('fiche d’achat : actions selon statut et droits', () {
    testWidgets('brouillon : réceptionner, acompte, modifier, commander, annuler', (t) async {
      await pumpDetail(t, _purchase(PurchaseStatus.draft), _all);
      expect(find.text('Réceptionner la marchandise'), findsOneWidget);
      expect(find.text('Verser un acompte'), findsOneWidget);
      expect(find.text('Modifier'), findsOneWidget);
      expect(find.text('Commander'), findsOneWidget);
      expect(find.text('Annuler cet achat'), findsOneWidget);
    });

    testWidgets('acompte versé : annulation impossible', (t) async {
      await pumpDetail(t, _purchase(PurchaseStatus.ordered, paid: 20000), _all);
      expect(find.text('Annuler cet achat'), findsNothing);
      expect(find.text('Commander'), findsNothing);
    });

    testWidgets('reçu : seulement « Payer le fournisseur »', (t) async {
      await pumpDetail(t, _purchase(PurchaseStatus.received, paid: 50000), _all);
      expect(find.text('Payer le fournisseur'), findsOneWidget);
      expect(find.text('Réceptionner la marchandise'), findsNothing);
      expect(find.text('Modifier'), findsNothing);
    });

    testWidgets('gestionnaire de stock (sans paiements ni annulation)', (t) async {
      await pumpDetail(
        t,
        _purchase(PurchaseStatus.draft),
        const PermissionSet({Permission.purchasesRead, Permission.purchasesCreate, Permission.purchasesReceive}),
      );
      expect(find.text('Réceptionner la marchandise'), findsOneWidget);
      expect(find.text('Verser un acompte'), findsNothing);
      expect(find.text('Annuler cet achat'), findsNothing);
    });
  });

  testWidgets('saisie : refus sans article, aucun appel', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final actions = _Actions();
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          permissionsProvider.overrideWithValue(_all),
          activeBusinessProvider.overrideWithValue(null),
          locationsProvider.overrideWith((ref) async => const []),
          purchaseActionsProvider.overrideWithValue(actions),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const PurchaseEditorScreen()),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(find.text('Ajoutez au moins un article.'), findsOneWidget);
    verifyZeroInteractions(actions);
  });
}
