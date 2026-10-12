// Téléphone en paysage (Galaxy S22 : 851 × 393 points) : aucun débordement.
// Un débordement (bande jaune et noire en debug) fait échouer le test.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jend_pro_mobile/app/shell/app_shell.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/core/storage/preferences.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/business/domain/workspace.dart';
import 'package:jend_pro_mobile/features/dashboard/domain/dashboard_models.dart';
import 'package:jend_pro_mobile/features/inventory/application/inventory_providers.dart';
import 'package:jend_pro_mobile/features/inventory/domain/inventory_models.dart';
import 'package:jend_pro_mobile/features/notifications/application/notification_providers.dart';
import 'package:jend_pro_mobile/features/products/application/catalog_providers.dart';
import 'package:jend_pro_mobile/features/reports/application/report_providers.dart';
import 'package:jend_pro_mobile/features/reports/domain/report_models.dart';
import 'package:jend_pro_mobile/features/reports/presentation/reports_screen.dart';
import 'package:jend_pro_mobile/features/sales/application/pos_providers.dart';
import 'package:jend_pro_mobile/features/sales/domain/sale_models.dart';
import 'package:jend_pro_mobile/features/sales/presentation/pos_screen.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends Mock implements AuthRepository {}

class _Workspace extends WorkspaceController {
  @override
  Future<Workspace?> build() async => const Workspace(memberships: [], invitations: []);
}

class _Unread extends UnreadNotificationsNotifier {
  @override
  int build() => 2;
}

class _Location extends PosLocationNotifier {
  @override
  String? build() => 'shop';
}

const _business = BusinessMembership(businessId: 'b1', businessName: 'Boutique', roleCode: 'OWNER', roleName: 'P');
const _all = PermissionSet({
  Permission.salesCreate,
  Permission.salesRead,
  Permission.productsRead,
  Permission.customersRead,
  Permission.reportsRead,
  Permission.inventoryRead,
});

void main() {
  late SharedPreferences prefs;

  setUpAll(() => initializeDateFormatting('fr'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  void landscape(WidgetTester t) {
    t.view.physicalSize = const Size(2340, 1080);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
  }

  Widget scope(Widget child, {List overrides = const []}) => ProviderScope(
    retry: (_, _) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      activeBusinessProvider.overrideWithValue(_business),
      permissionsProvider.overrideWithValue(_all),
      workspaceProvider.overrideWith(_Workspace.new),
      unreadNotificationsProvider.overrideWith(_Unread.new),
      ...overrides.cast(),
    ],
    child: child,
  );

  testWidgets('barre de navigation latérale (Vendre + 4 onglets)', (t) async {
    landscape(t);
    Widget page(String name) => Scaffold(body: Center(child: Text(name)));
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(navigationShell: shell),
          branches: [
            for (final name in ['home', 'catalog', 'customers', 'more'])
              StatefulShellBranch(
                routes: [GoRoute(path: '/$name', builder: (_, _) => page(name))],
              ),
          ],
        ),
      ],
    );
    await t.pumpWidget(scope(MaterialApp.router(theme: AppTheme.light(), routerConfig: router)));
    await t.pumpAndSettle();
    expect(find.text('Vendre'), findsOneWidget);
    expect(find.text('Plus'), findsOneWidget);
    await t.tap(find.text('Plus'));
    await t.pumpAndSettle();
    expect(find.text('more'), findsOneWidget);
  });

  testWidgets('connexion', (t) async {
    landscape(t);
    await t.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(_Auth())],
        child: MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Se connecter'), findsWidgets);
  });

  testWidgets('caisse avec panier', (t) async {
    landscape(t);
    const huile = SellableProduct(
      id: 'huile',
      name: 'Huile 5 L',
      unit: 'bidon',
      salePrice: 4250,
      trackStock: true,
      allowsFractional: false,
      stockQuantity: 12,
    );
    await t.pumpWidget(
      scope(
        MaterialApp(theme: AppTheme.light(), home: const PosScreen()),
        overrides: [
          posLocationProvider.overrideWith(_Location.new),
          locationsProvider.overrideWith(
            (ref) async => const [StockLocation(id: 'shop', name: 'Boutique', isDefault: true, isWarehouse: false)],
          ),
          categoriesProvider.overrideWith((ref) async => const []),
          posCatalogProvider.overrideWith((ref) async => const PosCatalog(products: [huile])),
        ],
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Huile 5 L').first);
    await t.pumpAndSettle();
    expect(find.textContaining('Huile 5 L'), findsWidgets);
  });

  testWidgets('rapports', (t) async {
    landscape(t);
    final summary = DashboardSummary.fromJson(const {'revenue': 184500, 'sales_count': 23, 'average_basket': 8021});
    final period = DashboardPeriod.custom(DateTime(2026, 10, 3), DateTime(2026, 10, 9));
    await t.pumpWidget(
      scope(
        MaterialApp(theme: AppTheme.light(), home: const ReportsScreen()),
        overrides: [
          reportDataProvider.overrideWith(
            (ref) async => ReportData(
              period: period,
              summary: summary,
              previous: summary,
              series: [
                for (var i = 0; i < 7; i++)
                  SalesPoint(period: DateTime(2026, 10, 3 + i), revenue: 1000 * i, salesCount: i),
              ],
              topProducts: const [TopProduct(productId: 'p', name: 'Riz', quantity: 2, revenue: 9000)],
            ),
          ),
        ],
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Rapports'), findsOneWidget);
  });
}
