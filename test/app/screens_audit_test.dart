// Audit d'affichage : chaque écran sur un PETIT téléphone (360 × 740 points),
// police agrandie au maximum autorisé par l'app (130 %), barre de navigation
// Android, données réalistes (noms longs). L'écran est défilé jusqu'en bas ;
// tout débordement (bande jaune et noire) fait échouer le test.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/domain/payment_method.dart';
import 'package:jend_pro_mobile/core/pagination/paged.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/core/storage/preferences.dart';
import 'package:jend_pro_mobile/features/auth/application/auth_session.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/auth/domain/user_profile.dart';
import 'package:jend_pro_mobile/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:jend_pro_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:jend_pro_mobile/features/auth/presentation/screens/register_screen.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/business/domain/workspace.dart';
import 'package:jend_pro_mobile/features/customers/application/customer_providers.dart';
import 'package:jend_pro_mobile/features/customers/domain/customer_models.dart';
import 'package:jend_pro_mobile/features/customers/presentation/customer_detail_screen.dart';
import 'package:jend_pro_mobile/features/customers/presentation/customer_form_screen.dart';
import 'package:jend_pro_mobile/features/customers/presentation/customers_screen.dart';
import 'package:jend_pro_mobile/features/dashboard/application/dashboard_controller.dart';
import 'package:jend_pro_mobile/features/dashboard/domain/dashboard_models.dart';
import 'package:jend_pro_mobile/features/dashboard/presentation/home_screen.dart';
import 'package:jend_pro_mobile/features/expenses/application/expense_providers.dart';
import 'package:jend_pro_mobile/features/expenses/domain/expense_models.dart';
import 'package:jend_pro_mobile/features/expenses/presentation/expense_detail_screen.dart';
import 'package:jend_pro_mobile/features/expenses/presentation/expense_form_screen.dart';
import 'package:jend_pro_mobile/features/expenses/presentation/expenses_screen.dart';
import 'package:jend_pro_mobile/features/inventory/application/inventory_providers.dart';
import 'package:jend_pro_mobile/features/inventory/domain/inventory_models.dart';
import 'package:jend_pro_mobile/features/notifications/application/notification_providers.dart';
import 'package:jend_pro_mobile/features/notifications/domain/notification_models.dart';
import 'package:jend_pro_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:jend_pro_mobile/features/products/application/catalog_providers.dart';
import 'package:jend_pro_mobile/features/products/domain/catalog_models.dart';
import 'package:jend_pro_mobile/features/products/presentation/catalog_screen.dart';
import 'package:jend_pro_mobile/features/products/presentation/product_detail_screen.dart';
import 'package:jend_pro_mobile/features/products/presentation/product_form_screen.dart';
import 'package:jend_pro_mobile/features/products/presentation/product_import_screen.dart';
import 'package:jend_pro_mobile/features/inventory/presentation/product_stock_screen.dart';
import 'package:jend_pro_mobile/features/purchases/application/purchase_providers.dart';
import 'package:jend_pro_mobile/features/purchases/domain/purchase_models.dart';
import 'package:jend_pro_mobile/features/purchases/presentation/purchase_detail_screen.dart';
import 'package:jend_pro_mobile/features/purchases/presentation/purchase_editor_screen.dart';
import 'package:jend_pro_mobile/features/purchases/presentation/purchases_screen.dart';
import 'package:jend_pro_mobile/features/reports/application/report_providers.dart';
import 'package:jend_pro_mobile/features/reports/domain/report_models.dart';
import 'package:jend_pro_mobile/features/reports/presentation/audit_log_screen.dart';
import 'package:jend_pro_mobile/features/reports/presentation/reports_screen.dart';
import 'package:jend_pro_mobile/features/sales/application/pos_providers.dart';
import 'package:jend_pro_mobile/features/sales/domain/sale_models.dart';
import 'package:jend_pro_mobile/features/sales/presentation/checkout_panel.dart';
import 'package:jend_pro_mobile/features/sales/presentation/pos_screen.dart';
import 'package:jend_pro_mobile/features/sales/presentation/sale_detail_screen.dart';
import 'package:jend_pro_mobile/features/sales/presentation/sales_history_screen.dart';
import 'package:jend_pro_mobile/features/settings/application/settings_providers.dart';
import 'package:jend_pro_mobile/features/settings/domain/settings_models.dart';
import 'package:jend_pro_mobile/features/settings/presentation/business_settings_screen.dart';
import 'package:jend_pro_mobile/features/settings/presentation/change_password_screen.dart';
import 'package:jend_pro_mobile/features/settings/presentation/locations_screen.dart';
import 'package:jend_pro_mobile/features/settings/presentation/more_screen.dart';
import 'package:jend_pro_mobile/features/settings/presentation/profile_screen.dart';
import 'package:jend_pro_mobile/features/settings/presentation/subscription_screen.dart';
import 'package:jend_pro_mobile/features/notifications/presentation/large_sale_threshold_sheet.dart';
import 'package:jend_pro_mobile/features/documents/application/document_providers.dart';
import 'package:jend_pro_mobile/features/documents/domain/document_issuer.dart';
import 'package:jend_pro_mobile/features/products/data/products_repository.dart';
import 'package:jend_pro_mobile/features/sales/data/sales_repository.dart';
import 'package:jend_pro_mobile/features/support/data/support_repository.dart';
import 'package:jend_pro_mobile/features/support/domain/support_models.dart';
import 'package:jend_pro_mobile/features/support/presentation/new_ticket_screen.dart';
import 'package:jend_pro_mobile/features/support/presentation/support_screen.dart';
import 'package:jend_pro_mobile/features/support/presentation/ticket_screen.dart';
import 'package:jend_pro_mobile/features/suppliers/application/supplier_providers.dart';
import 'package:jend_pro_mobile/features/suppliers/domain/supplier_models.dart';
import 'package:jend_pro_mobile/features/suppliers/presentation/supplier_detail_screen.dart';
import 'package:jend_pro_mobile/features/suppliers/presentation/supplier_form_screen.dart';
import 'package:jend_pro_mobile/features/suppliers/presentation/suppliers_screen.dart';
import 'package:jend_pro_mobile/features/team/application/team_providers.dart';
import 'package:jend_pro_mobile/features/team/domain/team_models.dart';
import 'package:jend_pro_mobile/features/team/presentation/employee_detail_screen.dart';
import 'package:jend_pro_mobile/features/team/presentation/employee_form_screen.dart';
import 'package:jend_pro_mobile/features/team/presentation/employees_screen.dart';
import 'package:jend_pro_mobile/features/team/presentation/team_screen.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends Mock implements AuthRepository {}

class _SalesRepo extends Mock implements SalesRepository {}

class _ProductsRepo extends Mock implements ProductsRepository {}

class _SupportRepo extends Mock implements SupportRepository {}

class _Session extends AuthSessionNotifier {
  @override
  AuthSession build() => const AuthSession(userId: 'me', email: 'awa.ndiaye.boutique@exemple.sn');
}

class _Workspace extends WorkspaceController {
  @override
  Future<Workspace?> build() async => Workspace(
    memberships: const [_business],
    invitations: const [],
    active: _business,
    permissions: _all,
    subscription: SubscriptionStatus(
      planCode: 'PRO',
      planName: 'Pro',
      status: 'TRIALING',
      isRestricted: false,
      trialEndsAt: DateTime.now().add(const Duration(days: 9)),
      limits: const PlanQuota(members: 10, products: 5000, locations: 3),
      usage: const PlanQuota(members: 4, products: 812, locations: 3),
    ),
  );
}

class _Unread extends UnreadNotificationsNotifier {
  @override
  int build() => 12;
}

class _Location extends PosLocationNotifier {
  @override
  String? build() => 'shop';
}

class _Paged<T> {
  static Paged<T> of<T>(List<T> items) => Paged(items: items, hasMore: false);
}

class _Products extends ProductListController {
  @override
  Future<ProductPage> build() async => _Paged.of(_products);
}

class _Stock extends StockListController {
  @override
  Future<Paged<StockRow>> build() async => _Paged.of([
    for (final p in _products)
      StockRow(
        productId: p.id,
        productName: p.name,
        unit: p.unit,
        locationId: 'shop',
        locationName: 'Boutique principale Marché Sandaga',
        quantity: 3,
        minLevel: 10,
        allowsFractional: false,
      ),
  ]);
}

class _Movements extends MovementsController {
  _Movements() : super('p1');

  @override
  Future<Paged<StockMovement>> build() async => _Paged.of([
    StockMovement(
      id: 'm1',
      type: MovementType.sale,
      quantity: -2,
      quantityAfter: 38,
      createdAt: DateTime(2026, 10, 14, 17, 45),
      locationId: 'shop',
      locationName: 'Boutique principale Marché Sandaga',
      reason: 'Vente V-000123',
    ),
  ]);
}

class _Customers extends CustomerListController {
  @override
  Future<Paged<Customer>> build() async => _Paged.of([_customer, _customer, _customer]);
}

class _Statement extends CustomerStatementController {
  _Statement() : super('c1');

  @override
  Future<Paged<CustomerTransaction>> build() async => _Paged.of([
    CustomerTransaction(
      id: 't1',
      type: CustomerTransactionType.creditSale,
      amount: 125000,
      balanceAfter: 1250000,
      createdAt: DateTime(2026, 10, 12),
      saleNumber: 'V-000123',
      note: 'Livraison au domicile du client, quartier Parcelles Assainies',
    ),
  ]);
}

class _Suppliers extends SupplierListController {
  @override
  Future<Paged<Supplier>> build() async => _Paged.of([_supplier, _supplier]);
}

class _Purchases extends PurchaseListController {
  @override
  Future<Paged<PurchaseSummary>> build() async => _Paged.of([_purchaseSummary, _purchaseSummary]);
}

class _History extends SalesHistoryController {
  @override
  Future<Paged<Sale>> build() async => _Paged.of([_sale, _sale]);
}

class _Expenses extends ExpenseListController {
  @override
  Future<Paged<Expense>> build() async => _Paged.of([_expense, _expense]);
}

class _NotificationList extends NotificationListController {
  @override
  Future<Paged<AppNotification>> build() async => _Paged.of([
    for (final k in NotificationKind.values)
      AppNotification(
        id: k.code,
        kind: k,
        title: 'Stock faible : Riz parfumé brisé importé de Thaïlande 25 kg',
        body: 'Il reste 3 sacs à Boutique principale Marché Sandaga (seuil : 10).',
        businessId: 'b1',
        createdAt: DateTime.now(),
      ),
  ]);
}

class _Audit extends AuditLogController {
  @override
  Future<Paged<AuditEntry>> build() async => _Paged.of([
    AuditEntry(
      id: 'a1',
      action: 'product.price_change',
      createdAt: DateTime(2026, 10, 14, 9, 30),
      cursor: '',
      actorName: 'Mamadou Lamine Diallo Ndiaye',
      metadata: const {'old': 1250000, 'new': 1375000},
    ),
  ]);
}

const _business = BusinessMembership(
  businessId: 'b1',
  businessName: 'Quincaillerie Moderne Serigne Fallou & Frères',
  roleCode: 'OWNER',
  roleName: 'Propriétaire',
  city: 'Dakar',
);

final _all = PermissionSet({
  for (final p in [
    Permission.settingsManage,
    Permission.subscriptionManage,
    Permission.membersRead,
    Permission.membersManage,
    Permission.employeesRead,
    Permission.employeesManage,
    Permission.productsRead,
    Permission.productsCreate,
    Permission.productsUpdate,
    Permission.productsDelete,
    Permission.productsReadCost,
    Permission.categoriesManage,
    Permission.inventoryRead,
    Permission.inventoryAdjust,
    Permission.inventoryTransfer,
    Permission.customersRead,
    Permission.customersCreate,
    Permission.customersManage,
    Permission.customersPayments,
    Permission.suppliersRead,
    Permission.suppliersManage,
    Permission.purchasesRead,
    Permission.purchasesCreate,
    Permission.purchasesReceive,
    Permission.purchasesPayments,
    Permission.purchasesCancel,
    Permission.salesRead,
    Permission.salesReadOwn,
    Permission.salesCreate,
    Permission.salesDiscount,
    Permission.salesCredit,
    Permission.salesCancel,
    Permission.expensesRead,
    Permission.expensesCreate,
    Permission.expensesManage,
    Permission.reportsRead,
    Permission.auditRead,
  ])
    p,
});

const _longName = 'Riz parfumé brisé importé de Thaïlande 25 kg';

final _products = [
  for (var i = 0; i < 4; i++)
    Product(
      id: 'p$i',
      name: i.isEven ? _longName : 'Huile',
      unit: 'sac',
      salePrice: 1375000,
      trackStock: true,
      allowsFractionalQuantity: false,
      minStockLevel: 10,
      archived: false,
      categoryName: 'Céréales et produits de base',
      stockQuantity: i == 1 ? 0 : 1240,
      costPrice: 1190000,
      barcode: '6001234567890',
      sku: 'RIZ-THAI-25',
    ),
];

final _customer = Customer(
  id: 'c1',
  name: 'Mame Diarra Bousso Ndiaye Ép. Fall',
  balance: 1250000,
  creditLimit: 2000000,
  archived: false,
  createdAt: DateTime(2026),
  phone: '+221771234567',
  email: 'mame.diarra.bousso.ndiaye@exemple.sn',
  address: 'Cité Keur Gorgui, Villa 1234, Dakar',
);

const _supplier = Supplier(
  id: 's1',
  name: 'Société Sénégalaise de Distribution Alimentaire',
  archived: false,
  contactName: 'Ousmane Badara Diop',
  phone: '+221338001122',
  email: 'commandes@distribution-alimentaire.sn',
);

final _purchaseSummary = PurchaseSummary(
  id: 'pu1',
  number: 'A-000123',
  status: 'RECEIVED',
  total: 12500000,
  amountPaid: 4000000,
  createdAt: DateTime(2026, 10, 10),
  supplierName: 'Société Sénégalaise de Distribution Alimentaire',
);

final _purchase = Purchase(
  id: 'pu1',
  number: 'A-000123',
  status: PurchaseStatus.ordered,
  subtotal: 12500000,
  discount: 250000,
  total: 12250000,
  amountPaid: 4000000,
  locationId: 'shop',
  createdAt: DateTime(2026, 10, 10),
  supplierName: 'Société Sénégalaise de Distribution Alimentaire',
  lines: const [
    PurchaseLine(
      productId: 'p0',
      productName: _longName,
      unit: 'sac',
      quantity: 100,
      unitCost: 125000,
      lineTotal: 12500000,
      allowsFractional: false,
    ),
  ],
);

final _sale = Sale(
  id: 'sa1',
  number: 'V-000123',
  soldAt: DateTime(2026, 10, 14, 18, 5),
  subtotal: 1500000,
  discount: 25000,
  total: 1475000,
  amountPaid: 1000000,
  creditAmount: 475000,
  cancelled: false,
  customerName: 'Mame Diarra Bousso Ndiaye Ép. Fall',
  customerPhone: '771234567',
  lines: const [
    SaleLine(productName: _longName, quantity: 1, unitPrice: 1375000, discount: 25000, lineTotal: 1350000),
    SaleLine(productName: 'Huile', quantity: 10, unitPrice: 12500, discount: 0, lineTotal: 125000),
  ],
  payments: [
    SalePayment(method: PaymentMethod.orangeMoney, amount: 1000000, incoming: true, paidAt: DateTime(2026, 10, 14)),
  ],
);

final _expense = Expense(
  id: 'e1',
  categoryId: 'c',
  categoryName: 'Électricité et eau (Senelec, Sen’Eau)',
  amount: 1250000,
  spentOn: DateTime(2026, 10, 3),
  method: PaymentMethod.bankTransfer,
  createdAt: DateTime(2026, 10, 3),
  description: 'Facture Senelec septembre, boutique et dépôt de Pikine',
  receiptPath: 'b1/expenses/1.jpg',
);

const _employee = Employee(
  id: 'em1',
  fullName: 'Cheikh Ahmadou Bamba Mbacké Diop',
  archived: false,
  position: 'Responsable de dépôt et des livraisons',
  phone: '+221771234567',
  salaryAmount: 1250000,
  notes: 'Avance sur salaire de 50 000 F remboursée en septembre.',
);

ReportData _report() {
  final s = DashboardSummary.fromJson(const {
    'revenue': 128450000,
    'sales_count': 1234,
    'average_basket': 104092,
    'estimated_margin': 22450000,
    'discounts': 1250000,
    'credit_given': 12500000,
    'cancelled_count': 12,
    'active_customers': 345,
    'cash_in': 115000000,
    'cash_out': 45000000,
    'expenses': 12500000,
    'net_cash_flow': 57500000,
    'customers_debt': 34500000,
  });
  return ReportData(
    period: DashboardPeriod.custom(DateTime(2026, 9, 15), DateTime(2026, 10, 14)),
    summary: s,
    previous: s,
    series: [
      for (var i = 0; i < 30; i++)
        SalesPoint(
          period: DateTime(2026, 9, 15 + i),
          revenue: 4000000 + i * 12345,
          salesCount: 40,
          estimatedMargin: 700000,
        ),
    ],
    topProducts: [
      for (var i = 0; i < 10; i++)
        TopProduct(productId: 'p$i', name: _longName, quantity: 1234, revenue: 12500000, estimatedMargin: 2500000),
    ],
  );
}

void main() {
  late SharedPreferences prefs;

  setUpAll(() => registerFallbackValue(const ProductFilter()));

  setUpAll(() => initializeDateFormatting('fr'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  final common = <Object>[
    authRepositoryProvider.overrideWithValue(_Auth()),
    authSessionProvider.overrideWith(_Session.new),
    activeBusinessProvider.overrideWithValue(_business),
    permissionsProvider.overrideWithValue(_all),
    workspaceProvider.overrideWith(_Workspace.new),
    unreadNotificationsProvider.overrideWith(_Unread.new),
    userProfileProvider.overrideWith(
      (ref) async => const UserProfile(
        id: 'me',
        email: 'awa.ndiaye.boutique@exemple.sn',
        fullName: 'Awa Ndiaye Diop Fall',
        phone: '771234567',
      ),
    ),
    appVersionProvider.overrideWith((ref) async => '1.0.0 (1)'),
  ];

  Future<void> audit(WidgetTester t, Widget screen, [List<Object> overrides = const [], bool scroll = true]) async {
    // Petit téléphone : 360 × 740 points, barre de navigation à 3 boutons.
    t.view.physicalSize = const Size(1080, 2220);
    t.view.devicePixelRatio = 3;
    t.view.padding = const FakeViewPadding(top: 24 * 3, bottom: 48 * 3);
    t.view.viewPadding = const FakeViewPadding(top: 24 * 3, bottom: 48 * 3);
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs), ...common.cast(), ...overrides.cast()],
        child: MaterialApp(
          theme: AppTheme.light(),
          // Même plafond que l'app (app.dart) : police système agrandie à 130 %.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: screen,
        ),
      ),
    );
    await t.pumpAndSettle();
    if (!scroll) return;
    // Défile chaque zone verticale jusqu'en bas pour construire tout le contenu.
    for (var pass = 0; pass < 6; pass++) {
      final scrollables = find.byWidgetPredicate(
        (w) => w is Scrollable && (w.axisDirection == AxisDirection.down || w.axisDirection == AxisDirection.up),
      );
      if (scrollables.evaluate().isEmpty) break;
      await t.drag(scrollables.first, const Offset(0, -500), warnIfMissed: false);
      await t.pumpAndSettle();
    }
  }

  group('authentification', () {
    testWidgets('connexion', (t) => audit(t, const LoginScreen()));
    testWidgets('inscription', (t) => audit(t, const RegisterScreen()));
    testWidgets('mot de passe oublié', (t) => audit(t, const ForgotPasswordScreen()));
  });

  testWidgets('accueil (tableau de bord complet)', (t) async {
    final d = _report();
    await audit(t, const HomeScreen(), [
      dashboardProvider.overrideWith(
        (ref) async => DashboardData(
          period: DashboardPeriod.preset(PeriodKind.today, DateTime(2026, 10, 14)),
          summary: d.summary,
          previous: d.summary,
          series: d.series.take(10).toList(),
          topProducts: d.topProducts.take(5).toList(),
          lowStock: [
            for (var i = 0; i < 3; i++)
              LowStockItem(
                productId: 'p$i',
                name: _longName,
                locationName: 'Boutique principale Marché Sandaga',
                quantity: 3,
                minLevel: 10,
              ),
          ],
          recentSales: [
            for (var i = 0; i < 5; i++)
              RecentSale(
                id: 'r$i',
                number: 'V-00012$i',
                total: 1475000,
                soldAt: DateTime(2026, 10, 14, 18, 5),
                itemCount: 12,
                cancelled: i == 2,
                creditAmount: i == 1 ? 475000 : 0,
                firstItemName: _longName,
                firstItemQuantity: 2,
                customerName: 'Mame Diarra Bousso Ndiaye Ép. Fall',
                paymentMethod: PaymentMethod.orangeMoney,
              ),
          ],
        ),
      ),
    ]);
  });

  group('catalogue et stock', () {
    testWidgets('catalogue', (t) async {
      await audit(t, const CatalogScreen(), [
        productListProvider.overrideWith(_Products.new),
        stockListProvider.overrideWith(_Stock.new),
        categoriesProvider.overrideWith(
          (ref) async => const [
            Category(id: 'c1', name: 'Céréales et produits de base'),
            Category(id: 'c2', name: 'Huiles'),
          ],
        ),
        locationsProvider.overrideWith(
          (ref) async => const [
            StockLocation(id: 'shop', name: 'Boutique principale Marché Sandaga', isDefault: true, isWarehouse: false),
            StockLocation(id: 'dep', name: 'Dépôt de Pikine', isDefault: false, isWarehouse: true),
          ],
        ),
      ]);
      // Onglet Stock (en haut de l'écran : on remonte d'abord), puis défilement.
      for (var i = 0; i < 6; i++) {
        await t.drag(find.byType(Scrollable).first, const Offset(0, 600), warnIfMissed: false);
        await t.pumpAndSettle();
      }
      await t.tap(find.text('Stock').first);
      await t.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await t.drag(find.byType(Scrollable).first, const Offset(0, -500), warnIfMissed: false);
        await t.pumpAndSettle();
      }
    });

    testWidgets('fiche produit', (t) async {
      await audit(t, const ProductDetailScreen(productId: 'p0'), [
        productDetailProvider('p0').overrideWith((ref) async => _products.first),
        productStockProvider('p0').overrideWith(
          (ref) async => const [
            LocationStock(
              location: StockLocation(
                id: 'shop',
                name: 'Boutique principale Marché Sandaga',
                isDefault: true,
                isWarehouse: false,
              ),
              quantity: 1240,
            ),
          ],
        ),
      ]);
    });

    testWidgets('stock d’un produit', (t) async {
      await audit(t, const ProductStockScreen(productId: 'p1'), [
        productDetailProvider('p1').overrideWith((ref) async => _products.first),
        productStockProvider('p1').overrideWith(
          (ref) async => const [
            LocationStock(
              location: StockLocation(
                id: 'shop',
                name: 'Boutique principale Marché Sandaga',
                isDefault: true,
                isWarehouse: false,
              ),
              quantity: 3,
            ),
          ],
        ),
        movementsProvider('p1').overrideWith(_Movements.new),
        locationsProvider.overrideWith(
          (ref) async => const [
            StockLocation(id: 'shop', name: 'Boutique principale Marché Sandaga', isDefault: true, isWarehouse: false),
          ],
        ),
      ]);
    });

    testWidgets('import de produits', (t) => audit(t, const ProductImportScreen()));

    testWidgets('formulaire produit', (t) async {
      await audit(t, const ProductFormScreen(), [
        categoriesProvider.overrideWith((ref) async => const [Category(id: 'c1', name: 'Céréales')]),
      ]);
    });
  });

  group('clients', () {
    testWidgets('liste', (t) async {
      await audit(t, const CustomersScreen(), [
        customerListProvider.overrideWith(_Customers.new),
        customersDebtProvider.overrideWith((ref) async => 34500000),
      ]);
    });

    testWidgets('fiche', (t) async {
      await audit(t, const CustomerDetailScreen(customerId: 'c1'), [
        customerDetailProvider('c1').overrideWith((ref) async => _customer),
        customerSalesProvider('c1').overrideWith((ref) async => [_sale]),
        customerStatementProvider('c1').overrideWith(_Statement.new),
      ]);
    });

    testWidgets('formulaire', (t) => audit(t, const CustomerFormScreen()));
  });

  group('caisse et ventes', () {
    final pos = <Object>[
      posLocationProvider.overrideWith(_Location.new),
      locationsProvider.overrideWith(
        (ref) async => const [
          StockLocation(id: 'shop', name: 'Boutique principale Marché Sandaga', isDefault: true, isWarehouse: false),
          StockLocation(id: 'dep', name: 'Dépôt de Pikine', isDefault: false, isWarehouse: true),
        ],
      ),
      categoriesProvider.overrideWith((ref) async => const [Category(id: 'c1', name: 'Céréales et produits de base')]),
      posCatalogProvider.overrideWith(
        (ref) async => PosCatalog(
          products: [
            for (final p in _products)
              SellableProduct(
                id: p.id,
                name: p.name,
                unit: p.unit,
                salePrice: p.salePrice,
                trackStock: true,
                allowsFractional: false,
                stockQuantity: p.stockQuantity,
              ),
          ],
        ),
      ),
    ];

    testWidgets('caisse avec panier', (t) async {
      await audit(t, const PosScreen(), pos);
      await t.tap(find.text(_longName).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Huile').first);
      await t.pumpAndSettle();
    });

    testWidgets('encaissement', (t) async {
      await audit(t, const PosScreen(), pos);
      await t.tap(find.text(_longName).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Huile').first);
      await t.pumpAndSettle();
      final checkout = find.textContaining('Encaisser');
      await t.tap(checkout.first);
      await t.pumpAndSettle();
      expect(find.byType(CheckoutScreen), findsOneWidget);
    });

    testWidgets('détail de vente', (t) async {
      await audit(t, const SaleDetailScreen(saleId: 'sa1'), [
        saleDetailProvider('sa1').overrideWith((ref) async => _sale),
      ]);
    });

    testWidgets(
      'historique',
      (t) => audit(t, const SalesHistoryScreen(), [salesHistoryProvider.overrideWith(_History.new)]),
    );
  });

  group('fournisseurs et achats', () {
    testWidgets('fournisseurs', (t) async {
      await audit(t, const SuppliersScreen(), [
        supplierListProvider.overrideWith(_Suppliers.new),
        supplierBalancesProvider.overrideWith(
          (ref) async => {'s1': const SupplierBalance(amountDue: 8250000, advancesPaid: 1000000, unpaidPurchases: 3)},
        ),
      ]);
    });

    testWidgets('fiche fournisseur', (t) async {
      await audit(t, const SupplierDetailScreen(supplierId: 's1'), [
        supplierDetailProvider('s1').overrideWith((ref) async => _supplier),
        supplierBalancesProvider.overrideWith(
          (ref) async => {'s1': const SupplierBalance(amountDue: 8250000, advancesPaid: 1000000, unpaidPurchases: 3)},
        ),
        supplierProductsProvider('s1').overrideWith(
          (ref) async => const [
            SupplierProduct(productId: 'p0', productName: _longName, unit: 'sac', lastCost: 1190000),
          ],
        ),
        supplierPurchasesProvider('s1').overrideWith((ref) async => [_purchaseSummary]),
      ]);
    });

    testWidgets('formulaire fournisseur', (t) => audit(t, const SupplierFormScreen()));

    testWidgets(
      'achats',
      (t) => audit(t, const PurchasesScreen(), [purchaseListProvider.overrideWith(_Purchases.new)]),
    );

    testWidgets('détail d’achat', (t) async {
      await audit(t, const PurchaseDetailScreen(purchaseId: 'pu1'), [
        purchaseDetailProvider('pu1').overrideWith((ref) async => _purchase),
      ]);
    });

    testWidgets('saisie d’achat', (t) async {
      await audit(t, const PurchaseEditorScreen(purchaseId: 'pu1'), [
        purchaseDetailProvider('pu1').overrideWith((ref) async => _purchase),
        locationsProvider.overrideWith(
          (ref) async => const [
            StockLocation(id: 'shop', name: 'Boutique principale Marché Sandaga', isDefault: true, isWarehouse: false),
          ],
        ),
      ]);
    });
  });

  group('dépenses', () {
    testWidgets('liste', (t) async {
      await audit(t, const ExpensesScreen(), [
        expenseListProvider.overrideWith(_Expenses.new),
        expenseMonthTotalProvider.overrideWith((ref) async => 128450000),
        expenseCategoriesProvider.overrideWith(
          (ref) async => const [
            ExpenseCategory(id: 'c', name: 'Électricité et eau (Senelec, Sen’Eau)'),
            ExpenseCategory(id: 'l', name: 'Loyer'),
          ],
        ),
      ]);
    });

    testWidgets('saisie', (t) async {
      await audit(t, const ExpenseFormScreen(), [
        expenseCategoriesProvider.overrideWith(
          (ref) async => const [
            ExpenseCategory(id: 'c', name: 'Électricité et eau (Senelec, Sen’Eau)'),
            ExpenseCategory(id: 'l', name: 'Loyer'),
          ],
        ),
      ]);
    });

    testWidgets('détail', (t) async {
      await audit(t, const ExpenseDetailScreen(expenseId: 'e1'), [
        expenseDetailProvider('e1').overrideWith((ref) async => _expense),
        receiptUrlProvider('b1/expenses/1.jpg').overrideWith((ref) async => throw StateError('hors ligne')),
      ]);
    });
  });

  group('équipe', () {
    testWidgets('membres', (t) async {
      await audit(t, const TeamScreen(), [
        teamRolesProvider.overrideWith(
          (ref) async => const [
            TeamRole(id: '1', code: 'OWNER', name: 'Propriétaire', permissions: {}),
            TeamRole(id: '4', code: 'STOCK_MANAGER', name: 'Gestionnaire de stock', permissions: {}),
          ],
        ),
        teamMembersProvider.overrideWith(
          (ref) async => [
            for (final s in MemberStatus.values)
              TeamMember(
                userId: s.code,
                fullName: 'Cheikh Ahmadou Bamba Mbacké Diop',
                email: 'cheikh.ahmadou.bamba.mbacke@exemple.sn',
                roleCode: 'STOCK_MANAGER',
                roleName: 'Gestionnaire de stock',
                status: s,
                joinedAt: s == MemberStatus.invited ? null : DateTime(2026, 9, 1),
              ),
          ],
        ),
      ]);
    });

    testWidgets('employés', (t) async {
      await audit(t, const EmployeesScreen(), [
        employeesProvider.overrideWith((ref) async => const [_employee, _employee]),
      ]);
    });

    testWidgets('fiche employé', (t) async {
      await audit(t, const EmployeeDetailScreen(employeeId: 'em1'), [
        employeeDetailProvider('em1').overrideWith((ref) async => _employee),
        linkableMembersProvider.overrideWith((ref) async => const {}),
      ]);
    });

    testWidgets('formulaire employé', (t) async {
      await audit(t, const EmployeeFormScreen(), [linkableMembersProvider.overrideWith((ref) async => const {})]);
    });
  });

  group('pilotage', () {
    testWidgets(
      'rapports',
      (t) => audit(t, const ReportsScreen(), [reportDataProvider.overrideWith((ref) async => _report())]),
    );

    testWidgets(
      'journal d’audit',
      (t) => audit(t, const AuditLogScreen(), [auditLogProvider.overrideWith(_Audit.new)]),
    );

    testWidgets('notifications', (t) async {
      await audit(t, const NotificationsScreen(), [notificationListProvider.overrideWith(_NotificationList.new)]);
    });
  });

  group('paramètres', () {
    testWidgets('plus', (t) => audit(t, const Scaffold(body: MoreScreen())));

    testWidgets('mon commerce', (t) async {
      await audit(t, const BusinessSettingsScreen(), [
        businessSettingsProvider.overrideWith(
          (ref) async => const BusinessSettings(
            id: 'b1',
            name: 'Quincaillerie Moderne Serigne Fallou & Frères',
            timezone: 'Africa/Dakar',
            currencyCode: 'XOF',
            allowNegativeStock: false,
            legalName: 'SARL Quincaillerie Moderne',
          ),
        ),
        largeSaleThresholdProvider.overrideWith((ref) async => 12500000),
      ]);
    });

    testWidgets('emplacements', (t) async {
      await audit(t, const LocationsScreen(), [
        locationDetailsProvider.overrideWith(
          (ref) async => const [
            LocationDetail(
              id: 'l1',
              name: 'Boutique principale Marché Sandaga',
              kind: LocationKind.store,
              isDefault: true,
              archived: false,
              address: 'Avenue Lamine Guèye x Rue Sandiniéry, Dakar',
            ),
            LocationDetail(
              id: 'l2',
              name: 'Dépôt de Pikine',
              kind: LocationKind.warehouse,
              isDefault: false,
              archived: true,
            ),
          ],
        ),
      ]);
    });

    testWidgets('abonnement', (t) async {
      await audit(t, const SubscriptionScreen(), [
        subscriptionPlansProvider.overrideWith(
          (ref) async => const [
            SubscriptionPlan(
              code: 'BUSINESS',
              name: 'Business',
              price: 25000,
              currencyCode: 'XOF',
              billingPeriod: 'MONTHLY',
              description: 'PME multi-boutiques',
              limits: PlanQuota(members: 30, locations: 10),
            ),
          ],
        ),
      ]);
    });

    testWidgets('mon profil', (t) => audit(t, const ProfileScreen()));

    testWidgets('mot de passe', (t) => audit(t, const ChangePasswordScreen()));
  });

  group('feuilles et fenêtres', () {
    /// Ouvre l'écran, touche [trigger] puis fait défiler la feuille ouverte.
    Future<void> sheet(WidgetTester t, Widget screen, String trigger, [List<Object> overrides = const []]) async {
      await audit(t, screen, overrides, false);
      final target = find.text(trigger).first;
      await t.ensureVisible(target);
      await t.pumpAndSettle();
      await t.tap(target);
      await t.pumpAndSettle();
      final sheetScroll = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable));
      if (sheetScroll.evaluate().isNotEmpty) {
        await t.drag(sheetScroll.last, const Offset(0, -600), warnIfMissed: false);
        await t.pumpAndSettle();
      }
    }

    final roles = teamRolesProvider.overrideWith(
      (ref) async => [
        for (final (code, name) in [
          ('ADMIN', 'Administrateur'),
          ('MANAGER', 'Gérant'),
          ('CASHIER', 'Caissier'),
          ('STOCK_MANAGER', 'Gestionnaire de stock'),
        ])
          TeamRole(id: code, code: code, name: name, permissions: {Permission.salesCreate}),
      ],
    );
    final members = teamMembersProvider.overrideWith(
      (ref) async => [
        TeamMember(
          userId: 'u2',
          fullName: 'Cheikh Ahmadou Bamba Mbacké Diop',
          email: 'cheikh.ahmadou.bamba.mbacke@exemple.sn',
          phone: '+221771234567',
          roleCode: 'STOCK_MANAGER',
          roleName: 'Gestionnaire de stock',
          status: MemberStatus.active,
          joinedAt: DateTime(2026, 9, 1),
        ),
      ],
    );
    const shop = StockLocation(
      id: 'shop',
      name: 'Boutique principale Marché Sandaga',
      isDefault: true,
      isWarehouse: false,
    );
    const depot = StockLocation(id: 'dep', name: 'Dépôt de Pikine', isDefault: false, isWarehouse: true);

    testWidgets('inviter un membre', (t) => sheet(t, const TeamScreen(), 'Inviter', [roles, members]));

    testWidgets(
      'gérer un membre',
      (t) => sheet(t, const TeamScreen(), 'Cheikh Ahmadou Bamba Mbacké Diop', [roles, members]),
    );

    testWidgets('partager un reçu', (t) async {
      await sheet(t, const SaleDetailScreen(saleId: 'sa1'), 'Partager', [
        saleDetailProvider('sa1').overrideWith((ref) async => _sale),
        documentIssuerProvider.overrideWith((ref) async => const DocumentIssuer(name: 'Quincaillerie Moderne')),
      ]);
    });

    testWidgets('règlement client', (t) async {
      await sheet(t, const CustomerDetailScreen(customerId: 'c1'), 'Encaisser un règlement', [
        customerDetailProvider('c1').overrideWith((ref) async => _customer),
        customerSalesProvider('c1').overrideWith((ref) async => [_sale]),
        customerStatementProvider('c1').overrideWith(_Statement.new),
        locationsProvider.overrideWith((ref) async => const [shop]),
      ]);
    });

    testWidgets('mouvement de stock', (t) async {
      await sheet(t, const ProductStockScreen(productId: 'p1'), 'Retirer', [
        productDetailProvider('p1').overrideWith((ref) async => _products.first),
        productStockProvider('p1').overrideWith(
          (ref) async => const [
            LocationStock(location: shop, quantity: 40),
            LocationStock(location: depot, quantity: 12),
          ],
        ),
        movementsProvider('p1').overrideWith(_Movements.new),
        locationsProvider.overrideWith((ref) async => const [shop, depot]),
      ]);
    });

    testWidgets('emplacement', (t) async {
      await sheet(t, const LocationsScreen(), 'Boutique principale Marché Sandaga', [
        locationDetailsProvider.overrideWith(
          (ref) async => const [
            LocationDetail(
              id: 'l1',
              name: 'Boutique principale Marché Sandaga',
              kind: LocationKind.store,
              isDefault: true,
              archived: false,
            ),
          ],
        ),
      ]);
    });

    testWidgets('seuil de vente importante', (t) async {
      await sheet(t, const BusinessSettingsScreen(), 'Alerte « vente importante »', [
        businessSettingsProvider.overrideWith(
          (ref) async => const BusinessSettings(
            id: 'b1',
            name: 'Quincaillerie Moderne',
            timezone: 'Africa/Dakar',
            currencyCode: 'XOF',
            allowNegativeStock: false,
          ),
        ),
        largeSaleThresholdProvider.overrideWith((ref) async => 12500000),
      ]);
    });

    testWidgets('nouvelle catégorie de dépense', (t) async {
      await sheet(t, const ExpenseFormScreen(), 'Nouvelle', [
        expenseCategoriesProvider.overrideWith((ref) async => const [ExpenseCategory(id: 'l', name: 'Loyer')]),
      ]);
    });

    testWidgets('choisir un article (achat)', (t) async {
      final repo = _ProductsRepo();
      when(
        () => repo.fetchProducts(
          any(),
          any(),
          offset: any(named: 'offset'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => _products);
      await sheet(t, const PurchaseEditorScreen(), 'Ajouter', [
        productsRepositoryProvider.overrideWithValue(repo),
        locationsProvider.overrideWith((ref) async => const [shop]),
      ]);
    });

    testWidgets('client à l’encaissement', (t) async {
      final repo = _SalesRepo();
      when(() => repo.searchCustomers(any(), any())).thenAnswer(
        (_) async => [
          for (var i = 0; i < 12; i++)
            SaleCustomer(id: 'c$i', name: 'Mame Diarra Bousso Ndiaye Ép. Fall', phone: '771234567', balance: 1250000),
        ],
      );
      await audit(t, const PosScreen(), [
        salesRepositoryProvider.overrideWithValue(repo),
        posLocationProvider.overrideWith(_Location.new),
        locationsProvider.overrideWith((ref) async => const [shop]),
        categoriesProvider.overrideWith((ref) async => const []),
        posCatalogProvider.overrideWith(
          (ref) async => const PosCatalog(
            products: [
              SellableProduct(
                id: 'h',
                name: 'Huile',
                unit: 'L',
                salePrice: 1500,
                trackStock: false,
                allowsFractional: false,
              ),
            ],
          ),
        ),
      ], false);
      await t.tap(find.text('Huile').first);
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Encaisser').first);
      await t.pumpAndSettle();
      final add = find.text('Ajouter un client');
      await t.ensureVisible(add);
      await t.pumpAndSettle();
      await t.tap(add);
      await t.pumpAndSettle();
      expect(find.text('Mame Diarra Bousso Ndiaye Ép. Fall'), findsWidgets);
    });
  });

  group('support', () {
    _SupportRepo repo() {
      final r = _SupportRepo();
      final ticket = SupportTicket(
        id: 't1',
        number: 1234,
        subject: 'Mon imprimante Bluetooth n’imprime plus les tickets depuis la mise à jour du téléphone',
        status: TicketStatus.waiting,
        urgent: true,
        lastMessageAt: DateTime.now(),
        createdAt: DateTime(2026, 10, 15),
      );
      when(() => r.fetchTickets()).thenAnswer((_) async => [ticket, ticket]);
      when(() => r.fetchTicket('t1')).thenAnswer((_) async => ticket);
      when(() => r.fetchMessages('t1')).thenAnswer(
        (_) async => [
          for (var i = 0; i < 6; i++)
            SupportMessage(
              id: 'm$i',
              body:
                  'Bonjour, depuis hier soir l’imprimante de la Boutique principale Marché Sandaga ne répond plus. '
                  'J’ai redémarré le téléphone et l’imprimante, sans succès.',
              fromStaff: i.isOdd,
              createdAt: DateTime(2026, 10, 14 + i ~/ 3, 9, i),
            ),
        ],
      );
      return r;
    }

    testWidgets(
      'demandes',
      (t) => audit(t, const SupportScreen(), [supportRepositoryProvider.overrideWithValue(repo())]),
    );

    testWidgets('nouvelle demande', (t) => audit(t, const NewTicketScreen()));

    testWidgets(
      'conversation',
      (t) => audit(t, const TicketScreen(ticketId: 't1'), [supportRepositoryProvider.overrideWithValue(repo())]),
    );
  });
}
