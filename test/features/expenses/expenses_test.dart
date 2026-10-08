import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/domain/payment_method.dart';
import 'package:jend_pro_mobile/core/pagination/paged.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/expenses/application/expense_providers.dart';
import 'package:jend_pro_mobile/features/expenses/domain/expense_models.dart';
import 'package:jend_pro_mobile/features/expenses/presentation/expense_detail_screen.dart';
import 'package:jend_pro_mobile/features/expenses/presentation/expense_form_screen.dart';
import 'package:jend_pro_mobile/features/expenses/presentation/expenses_screen.dart';
import 'package:mocktail/mocktail.dart';

class _Actions extends Mock implements ExpenseActions {}

class _FakeList extends ExpenseListController {
  _FakeList(this.items);

  final List<Expense> items;

  @override
  Future<Paged<Expense>> build() async => Paged(items: items, hasMore: false);
}

const _categories = [ExpenseCategory(id: 'loyer', name: 'Loyer'), ExpenseCategory(id: 'transport', name: 'Transport')];

Expense _expense(String id, int amount, DateTime day, {String? description, String? receipt}) => Expense(
  id: id,
  categoryId: 'transport',
  categoryName: 'Transport',
  amount: amount,
  spentOn: day,
  method: PaymentMethod.cash,
  createdAt: day,
  description: description,
  receiptPath: receipt,
);

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  group('ExpenseInput / ExpenseMonth', () {
    test('colonnes envoyées : date ISO, code moyen, description nettoyée', () {
      final cols = ExpenseInput(
        categoryId: 'c',
        amount: 5000,
        spentOn: DateTime(2026, 3, 7),
        method: PaymentMethod.wave,
        description: '   ',
      ).toColumns();
      expect(cols['spent_on'], '2026-03-07');
      expect(cols['method'], PaymentMethod.wave.code);
      expect(cols['description'], isNull);
      expect(cols.containsKey('business_id'), isFalse);
    });

    test('navigation de mois et bornes', () {
      const jan = ExpenseMonth(2026, 1);
      expect(jan.previous, const ExpenseMonth(2025, 12));
      expect(const ExpenseMonth(2025, 12).next, jan);
      expect(jan.first, DateTime(2026, 1, 1));
      expect(const ExpenseMonth(2024, 2).last, DateTime(2024, 2, 29));
      expect(const ExpenseMonth(2026, 2).isAfter(jan), isTrue);
    });

    test('icône de catégorie déduite du nom', () {
      expect(
        const ExpenseCategory(id: 'a', name: 'Loyer').icon,
        isNot(const ExpenseCategory(id: 'b', name: 'Transport').icon),
      );
    });
  });

  Future<void> pump(WidgetTester t, Widget home, List overrides) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          activeBusinessProvider.overrideWithValue(null),
          expenseCategoriesProvider.overrideWith((ref) async => _categories),
          ...overrides.cast(),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('liste : regroupée par jour, total serveur, bouton selon droits', (t) async {
    final d1 = DateTime(2026, 10, 8);
    final d2 = DateTime(2026, 10, 6);
    await pump(t, const ExpensesScreen(), [
      permissionsProvider.overrideWithValue(const PermissionSet({Permission.expensesRead})),
      expenseMonthTotalProvider.overrideWith((ref) async => 8500),
      expenseListProvider.overrideWith(
        () => _FakeList([
          _expense('a', 3500, d1, description: 'Taxi marché', receipt: 'b/expenses/1.jpg'),
          _expense('b', 3000, d1),
          _expense('c', 2000, d2),
        ]),
      ),
    ]);
    expect(find.text('Taxi marché'), findsOneWidget);
    expect(find.textContaining('JEUDI 8 OCTOBRE'), findsOneWidget);
    expect(find.textContaining('MARDI 6 OCTOBRE'), findsOneWidget);
    expect(find.text('Total du mois'), findsOneWidget);
    expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
    expect(find.text('Dépense'), findsNothing, reason: 'pas de création sans expenses.create');
  });

  testWidgets('liste vide : invitation à saisir', (t) async {
    await pump(t, const ExpensesScreen(), [
      permissionsProvider.overrideWithValue(const PermissionSet({Permission.expensesRead, Permission.expensesCreate})),
      expenseMonthTotalProvider.overrideWith((ref) async => null),
      expenseListProvider.overrideWith(() => _FakeList(const [])),
    ]);
    expect(find.text('Aucune dépense ce mois-ci'), findsOneWidget);
    expect(find.text('Ajouter une dépense'), findsOneWidget);
    expect(find.text('Total du mois'), findsNothing);
  });

  testWidgets('saisie : montant puis catégorie obligatoires, puis création', (t) async {
    final actions = _Actions();
    registerFallbackValue(ExpenseInput(categoryId: '', amount: 0, spentOn: DateTime(2026), method: PaymentMethod.cash));
    when(() => actions.create(any())).thenAnswer((_) async => _expense('n', 2500, DateTime(2026, 10, 8)));
    await pump(t, const ExpenseFormScreen(), [
      permissionsProvider.overrideWithValue(const PermissionSet({Permission.expensesCreate})),
      expenseActionsProvider.overrideWithValue(actions),
    ]);
    expect(find.text('Nouvelle'), findsNothing, reason: 'créer une catégorie exige expenses.manage');

    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(find.text('Indiquez le montant.'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, '2500');
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(find.text('Choisissez une catégorie.'), findsOneWidget);
    verifyNever(() => actions.create(any()));

    await t.tap(find.text('Transport'));
    await t.tap(find.text('Enregistrer'));
    await t.pump();
    final input = verify(() => actions.create(captureAny())).captured.single as ExpenseInput;
    expect(input.amount, 2500);
    expect(input.categoryId, 'transport');
    expect(input.method, PaymentMethod.cash);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('fiche : actions réservées à expenses.manage', (t) async {
    final e = _expense('x', 4000, DateTime(2026, 10, 8), description: 'Carburant');
    for (final (perms, visible) in [
      (const PermissionSet({Permission.expensesRead}), false),
      (const PermissionSet({Permission.expensesRead, Permission.expensesManage}), true),
    ]) {
      await pump(t, const ExpenseDetailScreen(expenseId: 'x'), [
        permissionsProvider.overrideWithValue(perms),
        expenseDetailProvider('x').overrideWith((ref) async => e),
      ]);
      expect(find.text('Carburant'), findsOneWidget);
      expect(find.byTooltip('Supprimer'), visible ? findsOneWidget : findsNothing);
      await t.pumpWidget(const SizedBox());
    }
  });
}
