import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/app/router/redirect.dart';
import 'package:jend_pro_mobile/app/router/routes.dart';
import 'package:jend_pro_mobile/core/contact/contact_links.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/domain/payment_method.dart';
import 'package:jend_pro_mobile/core/formatting/formatters.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/features/auth/application/auth_session.dart';
import 'package:jend_pro_mobile/features/business/domain/workspace.dart';
import 'package:jend_pro_mobile/features/customers/application/customer_providers.dart';
import 'package:jend_pro_mobile/features/customers/domain/customer_models.dart';
import 'package:jend_pro_mobile/features/customers/presentation/widgets/customer_sheets.dart';
import 'package:mocktail/mocktail.dart';

class _Actions extends Mock implements CustomerActions {}

Customer _customer({int balance = 8000, int? limit = 20000}) => Customer(
  id: 'c1',
  name: 'Fatou Sow',
  phone: '771234567',
  balance: balance,
  creditLimit: limit,
  archived: false,
  createdAt: DateTime(2026),
);

void main() {
  setUpAll(() {
    registerFallbackValue(_customer());
    registerFallbackValue(PaymentMethod.cash);
  });

  group('Customer', () {
    test('crédit disponible et utilisation du plafond', () {
      final c = _customer();
      expect(c.creditAvailable, 12000);
      expect(c.creditUsage, closeTo(0.4, 0.001));
      expect(_customer(limit: null).creditAvailable, isNull);
      expect(_customer(limit: 0).creditAllowed, isFalse);
      expect(_customer(balance: 25000).creditAvailable, 0, reason: 'jamais négatif');
    });
  });

  group('contact', () {
    test('numéros sénégalais : affichage et format international', () {
      expect(Formatters.phone('771234567'), '77 123 45 67');
      expect(Formatters.phone('+33612345678'), '+33612345678');
      expect(ContactLinks.international('77 123 45 67'), '221771234567');
      expect(ContactLinks.international('+33 6 12 34 56 78'), '33612345678');
      expect(ContactLinks.international(''), isNull);
    });
  });

  test('routes clients selon les permissions', () {
    String? go(String path, Set<String> perms) => resolveRedirect(
      path: path,
      auth: const AuthSession(userId: 'u'),
      workspace: AsyncData(
        Workspace(memberships: const [_m], invitations: const [], active: _m, permissions: PermissionSet(perms)),
      ),
    );
    expect(go(Routes.customerDetail('c1'), {Permission.customersRead}), isNull);
    expect(go(Routes.customerDetail('c1'), {Permission.productsRead}), Routes.home);
    expect(go(Routes.customerNew, {Permission.customersCreate}), isNull);
    expect(go(Routes.customerEdit('c1'), {Permission.customersRead}), Routes.home);
  });

  group('règlement', () {
    late _Actions actions;

    setUp(() {
      actions = _Actions();
      when(
        () => actions.recordPayment(
          any(),
          amount: any(named: 'amount'),
          method: any(named: 'method'),
          reference: any(named: 'reference'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async {});
    });

    Future<void> open(WidgetTester t) async {
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: [customerActionsProvider.overrideWithValue(actions)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (c) =>
                    TextButton(onPressed: () => showPaymentSheet(c, _customer()), child: const Text('ouvrir')),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('ouvrir'));
      await t.pumpAndSettle();
    }

    testWidgets('pré-rempli avec la dette entière ; règlement total en un geste', (t) async {
      await open(t);
      expect(find.text('La dette sera entièrement réglée.'), findsOneWidget);
      await t.tap(find.text('Encaisser'));
      await t.pumpAndSettle();
      verify(
        () => actions.recordPayment(
          any(),
          amount: 8000,
          method: PaymentMethod.cash,
          reference: any(named: 'reference'),
          note: any(named: 'note'),
        ),
      ).called(1);
    });

    testWidgets('au-delà de la dette : refus avant tout appel', (t) async {
      await open(t);
      await t.enterText(find.byType(TextFormField).first, '9000');
      await t.pump();
      await t.tap(find.text('Encaisser'));
      await t.pumpAndSettle();
      expect(find.textContaining('ne peut pas dépasser la dette'), findsOneWidget);
      verifyNever(
        () => actions.recordPayment(
          any(),
          amount: any(named: 'amount'),
          method: any(named: 'method'),
          reference: any(named: 'reference'),
          note: any(named: 'note'),
        ),
      );
    });

    testWidgets('partiel : le reste dû est affiché', (t) async {
      await open(t);
      await t.enterText(find.byType(TextFormField).first, '5000');
      await t.pump();
      expect(find.textContaining('Restera dû'), findsOneWidget);
    });
  });
}

const _m = BusinessMembership(businessId: 'b', businessName: 'B', roleCode: 'OWNER', roleName: 'P');
