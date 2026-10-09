import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_session.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/business/application/workspace_controller.dart';
import '../../features/business/presentation/select_business_screen.dart';
import '../../features/customers/presentation/customer_detail_screen.dart';
import '../../features/customers/presentation/customer_form_screen.dart';
import '../../features/customers/presentation/customers_screen.dart';
import '../../features/dashboard/presentation/home_screen.dart';
import '../../features/inventory/presentation/product_stock_screen.dart';
import '../../features/onboarding/application/setup_pending.dart';
import '../../features/onboarding/presentation/create_business_screen.dart';
import '../../features/onboarding/presentation/setup_wizard_screen.dart';
import '../../features/expenses/presentation/expense_detail_screen.dart';
import '../../features/expenses/presentation/expense_form_screen.dart';
import '../../features/expenses/presentation/expenses_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/products/presentation/catalog_screen.dart';
import '../../features/reports/presentation/audit_log_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/team/presentation/employee_detail_screen.dart';
import '../../features/team/presentation/employee_form_screen.dart';
import '../../features/team/presentation/employees_screen.dart';
import '../../features/team/presentation/team_screen.dart';
import '../../features/products/presentation/product_detail_screen.dart';
import '../../features/products/presentation/product_form_screen.dart';
import '../../features/purchases/presentation/purchase_detail_screen.dart';
import '../../features/purchases/presentation/purchase_editor_screen.dart';
import '../../features/purchases/presentation/purchases_screen.dart';
import '../../features/sales/presentation/pos_screen.dart';
import '../../features/sales/presentation/sale_detail_screen.dart';
import '../../features/sales/presentation/sales_history_screen.dart';
import '../../features/settings/presentation/change_password_screen.dart';
import '../../features/suppliers/presentation/supplier_detail_screen.dart';
import '../../features/suppliers/presentation/supplier_form_screen.dart';
import '../../features/suppliers/presentation/suppliers_screen.dart';
import '../../features/settings/presentation/more_screen.dart';
import '../shell/app_shell.dart';
import '../splash_screen.dart';
import 'redirect.dart';
import 'routes.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final appRouterProvider = Provider<GoRouter>((ref) {
  // Réévalue les redirections quand la session ou le contexte change, sans
  // recréer le routeur (la pile de navigation est conservée).
  final refresh = ValueNotifier<int>(0);
  ref.listen(authSessionProvider, (_, _) => refresh.value++);
  ref.listen(workspaceProvider, (_, _) => refresh.value++);
  ref.listen(setupPendingProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => resolveRedirect(
      path: state.uri.path,
      auth: ref.read(authSessionProvider),
      workspace: ref.read(workspaceProvider),
      setupPending: ref.read(setupPendingProvider),
    ),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, pageBuilder: (_, s) => _fade(s, const LoginScreen())),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(path: Routes.forgotPassword, builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: Routes.resetPassword, pageBuilder: (_, s) => _fade(s, const ResetPasswordScreen())),
      GoRoute(path: Routes.onboarding, pageBuilder: (_, s) => _fade(s, const CreateBusinessScreen())),
      GoRoute(path: Routes.setup, pageBuilder: (_, s) => _fade(s, const SetupWizardScreen())),
      GoRoute(path: Routes.selectBusiness, pageBuilder: (_, s) => _fade(s, const SelectBusinessScreen())),
      GoRoute(path: Routes.sale, parentNavigatorKey: _rootKey, pageBuilder: (_, s) => _slideUp(s, const PosScreen())),
      GoRoute(
        path: '${Routes.products}/new',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _slideUp(s, ProductFormScreen(initialBarcode: s.uri.queryParameters['barcode'])),
      ),
      GoRoute(
        path: '${Routes.products}/:id/edit',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _slideUp(s, ProductFormScreen(productId: s.pathParameters['id'])),
      ),
      GoRoute(
        path: Routes.salesHistory,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const SalesHistoryScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) => SaleDetailScreen(saleId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: Routes.customerNew,
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _slideUp(s, const CustomerFormScreen()),
      ),
      GoRoute(
        path: '/customer-form/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _slideUp(s, CustomerFormScreen(customerId: s.pathParameters['id'])),
      ),
      GoRoute(
        path: Routes.suppliers,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const SuppliersScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) => SupplierDetailScreen(supplierId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: Routes.supplierNew,
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _slideUp(s, const SupplierFormScreen()),
      ),
      GoRoute(
        path: '/supplier-form/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _slideUp(s, SupplierFormScreen(supplierId: s.pathParameters['id'])),
      ),
      GoRoute(
        path: Routes.purchases,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const PurchasesScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) => PurchaseDetailScreen(purchaseId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/purchase-form/new',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _slideUp(s, PurchaseEditorScreen(supplierId: s.uri.queryParameters['supplier'])),
      ),
      GoRoute(
        path: '/purchase-form/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _slideUp(s, PurchaseEditorScreen(purchaseId: s.pathParameters['id'])),
      ),
      GoRoute(
        path: Routes.expenses,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ExpensesScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) => ExpenseDetailScreen(expenseId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: Routes.expenseNew,
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _slideUp(s, const ExpenseFormScreen()),
      ),
      GoRoute(
        path: '/expense-form/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _slideUp(s, ExpenseFormScreen(expenseId: s.pathParameters['id'])),
      ),
      GoRoute(path: Routes.notifications, parentNavigatorKey: _rootKey, builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: Routes.reports, parentNavigatorKey: _rootKey, builder: (_, _) => const ReportsScreen()),
      GoRoute(path: Routes.audit, parentNavigatorKey: _rootKey, builder: (_, _) => const AuditLogScreen()),
      GoRoute(path: Routes.team, parentNavigatorKey: _rootKey, builder: (_, _) => const TeamScreen()),
      GoRoute(
        path: Routes.employees,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const EmployeesScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) => EmployeeDetailScreen(employeeId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: Routes.employeeNew,
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _slideUp(s, const EmployeeFormScreen()),
      ),
      GoRoute(
        path: '/employee-form/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _slideUp(s, EmployeeFormScreen(employeeId: s.pathParameters['id'])),
      ),
      GoRoute(
        path: Routes.changePassword,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ChangePasswordScreen(),
      ),
      StatefulShellRoute.indexedStack(
        pageBuilder: (_, s, shell) => _fade(s, AppShell(navigationShell: shell)),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.catalog,
                builder: (_, _) => const CatalogScreen(),
                routes: [
                  GoRoute(
                    path: 'product/:id',
                    builder: (_, s) => ProductDetailScreen(productId: s.pathParameters['id']!),
                    routes: [
                      GoRoute(
                        path: 'stock',
                        builder: (_, s) => ProductStockScreen(productId: s.pathParameters['id']!),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.customers,
                builder: (_, _) => const CustomersScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, s) => CustomerDetailScreen(customerId: s.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.more, builder: (_, _) => const MoreScreen())],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

/// Index des branches du shell (doit suivre l'ordre ci-dessus).
abstract final class ShellBranch {
  static const home = 0;
  static const catalog = 1;
  static const customers = 2;
  static const more = 3;
}

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 260),
  transitionsBuilder: (_, animation, _, child) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
    child: child,
  ),
);

CustomTransitionPage<void> _slideUp(GoRouterState state, Widget child) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 320),
  reverseTransitionDuration: const Duration(milliseconds: 240),
  transitionsBuilder: (_, animation, _, child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return SlideTransition(
      position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(curved),
      child: FadeTransition(opacity: curved, child: child),
    );
  },
);
