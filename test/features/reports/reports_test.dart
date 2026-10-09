import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/pagination/paged.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/dashboard/domain/dashboard_models.dart';
import 'package:jend_pro_mobile/features/reports/application/report_providers.dart';
import 'package:jend_pro_mobile/features/reports/domain/report_models.dart';
import 'package:jend_pro_mobile/features/reports/presentation/audit_log_screen.dart';
import 'package:jend_pro_mobile/features/reports/presentation/reports_screen.dart';

DashboardSummary _summary({int revenue = 0, int count = 0, int? margin, int cashIn = 0}) => DashboardSummary(
  revenue: revenue,
  salesCount: count,
  averageBasket: count == 0 ? 0 : revenue ~/ count,
  discounts: 0,
  creditGiven: 0,
  cancelledCount: 0,
  activeCustomers: 0,
  cashIn: cashIn,
  cashOut: 0,
  expenses: 0,
  netCashFlow: cashIn,
  customersDebt: 0,
  lowStockCount: 0,
  estimatedMargin: margin,
);

ReportData _data({int? margin}) {
  final period = DashboardPeriod.custom(DateTime(2026, 10, 3), DateTime(2026, 10, 9));
  return ReportData(
    period: period,
    summary: _summary(revenue: 120000, count: 12, margin: margin, cashIn: 120000),
    previous: _summary(revenue: 100000, count: 10, margin: margin == null ? null : 20000),
    series: [
      for (var i = 0; i < 7; i++)
        SalesPoint(period: DateTime(2026, 10, 3 + i), revenue: 10000 + i * 1000, salesCount: 1 + i % 3),
    ],
    topProducts: [
      TopProduct(productId: 'p1', name: 'Riz 25 kg', quantity: 4, revenue: 60000, estimatedMargin: margin),
      const TopProduct(productId: 'p2', name: 'Huile 5 L', quantity: 3, revenue: 19500),
    ],
  );
}

AuditEntry _entry(String id, String action, Map<String, dynamic> meta) => AuditEntry(
  id: id,
  action: action,
  createdAt: DateTime(2026, 10, 9, 10),
  cursor: '2026-10-09T10:00:00Z',
  actorName: 'Awa',
  actorRole: 'authenticated',
  metadata: meta,
);

class _Audit extends AuditLogController {
  _Audit(this.items);

  final List<AuditEntry> items;

  @override
  Future<Paged<AuditEntry>> build() async {
    final prefix = ref.watch(auditDomainProvider).prefix;
    return Paged(items: items.where((e) => prefix == null || e.action.startsWith(prefix)).toList(), hasMore: false);
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  group('plages de rapport', () {
    final today = DateTime(2026, 3, 15);
    test('mois dernier, ce mois, cette année', () {
      final last = ReportRange.lastMonth.resolve(today);
      expect((last.from, last.to), (DateTime(2026, 2), DateTime(2026, 2, 28)));
      expect(ReportRange.lastMonth.resolve(DateTime(2026, 1, 10)).from, DateTime(2025, 12));
      expect(ReportRange.thisMonth.resolve(today).days, 15);
      expect(ReportRange.thisYear.resolve(today).from, DateTime(2026));
      expect(ReportRange.last30.resolve(today).days, 30);
    });

    test('évolution relative', () {
      expect(ReportData.delta(120, 100), closeTo(0.2, 1e-9));
      expect(ReportData.delta(5, 0), isNull);
      expect(_data(margin: 30000).marginRate, closeTo(0.25, 1e-9));
      expect(_data().marginRate, isNull);
    });
  });

  group('audit', () {
    test('libellés et détails', () {
      expect(auditActionLabel('sale.cancel'), 'Vente annulée');
      expect(auditActionLabel('stock.recount'), 'Stock recount');
      expect(_entry('1', 'product.price_change', {'old': 1000, 'new': 1100}).details, contains('→'));
      expect(_entry('2', 'member.role_change', {'from': 'CASHIER', 'to': 'MANAGER'}).details, 'Caissier → Gérant');
      expect(_entry('3', 'sale.cancel', {'reason': 'Erreur'}).details, '« Erreur »');
      final server = AuditEntry(id: 'x', action: 'a', createdAt: DateTime(2026), cursor: '', actorRole: 'service_role');
      expect(server.actorLabel, 'Serveur JËND PRO');
    });
  });

  Future<void> pump(WidgetTester t, Widget home, List overrides, Set<String> perms) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          permissionsProvider.overrideWithValue(PermissionSet(perms)),
          activeBusinessProvider.overrideWithValue(null),
          ...overrides.cast(),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('rapport sans droit aux coûts : pas de marge', (t) async {
    await pump(
      t,
      const ReportsScreen(),
      [reportDataProvider.overrideWith((ref) async => _data())],
      {Permission.reportsRead},
    );
    expect(find.text('Marge'), findsNothing);
    expect(find.text('Marge estimée'), findsNothing);
    expect(find.text('Riz 25 kg'), findsOneWidget);
    expect(find.text('Trésorerie'), findsOneWidget);
    expect(find.textContaining('+20,0'), findsWidgets);
    expect(find.text('Journal d’audit'), findsNothing);
  });

  testWidgets('rapport avec marges + bascule du graphique', (t) async {
    await pump(
      t,
      const ReportsScreen(),
      [reportDataProvider.overrideWith((ref) async => _data(margin: 30000))],
      {Permission.reportsRead, Permission.auditRead},
    );
    expect(find.text('Marge estimée'), findsOneWidget);
    expect(find.text('25,0 % du CA'), findsOneWidget);
    await t.tap(find.text('Ventes').first);
    await t.pumpAndSettle();
    expect(find.text('12 ventes'), findsOneWidget);
    expect(find.text('Journal d’audit'), findsOneWidget);
  });

  testWidgets('journal : filtre par domaine', (t) async {
    await pump(
      t,
      const AuditLogScreen(),
      [
        auditLogProvider.overrideWith(
          () => _Audit([
            _entry('1', 'sale.cancel', {'reason': 'Erreur'}),
            _entry('2', 'product.price_change', {'old': 1000, 'new': 1100}),
          ]),
        ),
      ],
      {Permission.auditRead},
    );
    expect(find.text('Vente annulée'), findsOneWidget);
    expect(find.text('Prix de vente modifié'), findsOneWidget);
    await t.tap(find.text('Ventes'));
    await t.pumpAndSettle();
    expect(find.text('Prix de vente modifié'), findsNothing);
    expect(find.text('Vente annulée'), findsOneWidget);
  });
}
