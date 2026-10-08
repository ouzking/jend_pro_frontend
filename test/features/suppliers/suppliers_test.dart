import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/app/router/redirect.dart';
import 'package:jend_pro_mobile/app/router/routes.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/pagination/paged.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/features/auth/application/auth_session.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/business/domain/workspace.dart';
import 'package:jend_pro_mobile/features/suppliers/application/supplier_providers.dart';
import 'package:jend_pro_mobile/features/suppliers/domain/supplier_models.dart';
import 'package:jend_pro_mobile/features/suppliers/presentation/suppliers_screen.dart';

const _m = BusinessMembership(businessId: 'b', businessName: 'B', roleCode: 'OWNER', roleName: 'P');

class _List extends SupplierListController {
  _List(this.items);
  final List<Supplier> items;
  @override
  Future<Paged<Supplier>> build() async => Paged(items: items, hasMore: false);
}

void main() {
  test('routes fournisseurs selon les permissions', () {
    String? go(String path, Set<String> perms) => resolveRedirect(
      path: path,
      auth: const AuthSession(userId: 'u'),
      workspace: AsyncData(
        Workspace(memberships: const [_m], invitations: const [], active: _m, permissions: PermissionSet(perms)),
      ),
    );
    // STOCK_MANAGER : lecture + gestion ; CASHIER : rien.
    expect(go(Routes.suppliers, {Permission.suppliersRead}), isNull);
    expect(go(Routes.supplierNew, {Permission.suppliersRead}), Routes.home);
    expect(go(Routes.supplierNew, {Permission.suppliersManage}), isNull);
    expect(go(Routes.supplierDetail('s'), {Permission.salesCreate}), Routes.home);
  });

  Future<void> pump(WidgetTester t, List<Supplier> items, Map<String, SupplierBalance> balances) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          permissionsProvider.overrideWithValue(
            const PermissionSet({Permission.suppliersRead, Permission.suppliersManage, Permission.purchasesRead}),
          ),
          activeBusinessProvider.overrideWithValue(null),
          supplierListProvider.overrideWith(() => _List(items)),
          supplierBalancesProvider.overrideWith((ref) async => balances),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const SuppliersScreen()),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('dette fournisseur : total et montant par fournisseur', (t) async {
    await pump(
      t,
      const [Supplier(id: 's1', name: 'Sedima', archived: false, contactName: 'M. Diop')],
      const {'s1': SupplierBalance(amountDue: 70000)},
    );
    expect(find.text('Vous devez à vos fournisseurs'), findsOneWidget);
    expect(find.text('À payer'), findsWidgets);
    expect(find.text('Sedima'), findsOneWidget);
  });

  testWidgets('liste vide : invitation à ajouter un fournisseur', (t) async {
    await pump(t, const [], const {});
    expect(find.text('Aucun fournisseur'), findsOneWidget);
    expect(find.text('Ajouter un fournisseur'), findsOneWidget);
    expect(find.text('Vous devez à vos fournisseurs'), findsNothing);
  });
}
