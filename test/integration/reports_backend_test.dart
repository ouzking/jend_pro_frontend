// Test d'intégration rapports + journal d'audit contre un Supabase réel.
//   flutter test test/integration -j 1 --dart-define-from-file=env/dev.json
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jend_pro_mobile/core/config/env.dart';
import 'package:jend_pro_mobile/core/domain/payment_method.dart';
import 'package:jend_pro_mobile/core/formatting/business_time.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/business/data/business_repository.dart';
import 'package:jend_pro_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:jend_pro_mobile/features/documents/data/document_builder.dart';
import 'package:jend_pro_mobile/features/documents/domain/document_issuer.dart';
import 'package:jend_pro_mobile/features/inventory/data/inventory_repository.dart';
import 'package:jend_pro_mobile/features/products/data/products_repository.dart';
import 'package:jend_pro_mobile/features/products/domain/catalog_models.dart';
import 'package:jend_pro_mobile/features/reports/data/reports_repository.dart';
import 'package:jend_pro_mobile/features/reports/domain/report_models.dart';
import 'package:jend_pro_mobile/features/sales/data/sales_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support.dart';

void main() {
  final skip = Env.isConfigured ? false : 'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY non fournis';

  test(
    'rapports : indicateurs, marge par produit, export PDF, journal d’audit paginé et filtré',
    () async {
      await initializeDateFormatting('fr');
      final client = SupabaseClient(
        Env.supabaseUrl,
        Env.supabasePublishableKey,
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      );
      await signUpForTest(
        AuthRepository(client),
        fullName: 'Test Rapports',
        email: 'reports-${DateTime.now().millisecondsSinceEpoch}@test.jendpro.local',
        password: 'motdepasse-test',
      );
      final business = BusinessRepository(client);
      final bid = await business.createBusiness(name: 'Boutique Rapports');
      final loc = await business.fetchDefaultLocationId(bid);
      final products = ProductsRepository(client);
      final sucre = await products.createProduct(
        bid,
        const NewProduct(name: 'Sucre 1 kg', salePrice: 1000, costPrice: 700),
      );
      await InventoryRepository(
        client,
      ).setInitialStock(businessId: bid, productId: sucre.id, locationId: loc, quantity: 50);

      final sales = SalesRepository(client);
      Future<String> sell(int qty) => sales.createSale(
        SaleRequest(
          businessId: bid,
          clientReference: const Uuid().v4(),
          locationId: loc,
          items: [
            {'product_id': sucre.id, 'quantity': qty},
          ],
          payments: [
            {'method': PaymentMethod.cash.code, 'amount': 1000 * qty},
          ],
        ),
      );
      await sell(3);
      final cancelled = await sell(2);
      await sales.cancelSale(cancelled, reason: 'Erreur de caisse');
      await products.updateProduct(sucre.id, {'sale_price': 1100});

      // Indicateurs de la plage « 7 jours » (aujourd'hui inclus).
      final today = BusinessTime.today('Africa/Dakar');
      final period = ReportRange.last7.resolve(today);
      expect(period.days, 7);
      final dashboard = DashboardRepository(client);
      final summary = await dashboard.fetchSummary(bid, period);
      expect((summary.revenue, summary.salesCount, summary.cancelledCount), (3000, 1, 1));
      expect(summary.estimatedMargin, 900, reason: '3 × (1 000 − 700)');
      final top = await dashboard.fetchTopProducts(bid, period, limit: 10);
      expect((top.single.revenue, top.single.estimatedMargin), (3000, 900));
      final series = await dashboard.fetchSeries(bid, period);
      expect(series.length, 7);
      expect(series.fold<int>(0, (s, p) => s + p.revenue), 3000);

      // Export PDF du rapport.
      final previous = await dashboard.fetchSummary(bid, period.previous);
      final data = ReportData(period: period, summary: summary, previous: previous, series: series, topProducts: top);
      final pdf = await DocumentBuilder.report(data, const DocumentIssuer(name: 'Boutique Rapports'), '7 jours');
      expect(pdf.length, greaterThan(1000));

      // Journal d'audit : plus récent d'abord, filtres par domaine, curseur.
      final reports = ReportsRepository(client);
      final all = await reports.fetchAudit(bid);
      final actions = all.map((e) => e.action).toList();
      expect(actions, containsAll(['product.price_change', 'sale.cancel', 'inventory.adjust', 'business.create']));
      expect(actions.first, 'product.price_change');
      final price = all.first;
      expect(price.label, 'Prix de vente modifié');
      expect(price.details, contains('→'));
      expect(price.actorLabel, 'Test Rapports');

      final onlySales = await reports.fetchAudit(bid, action: AuditDomain.sale.prefix);
      expect(onlySales.map((e) => e.action).toSet(), {'sale.cancel'});
      expect(onlySales.single.details, contains('Erreur de caisse'));

      final page1 = await reports.fetchAudit(bid, limit: 2);
      final page2 = await reports.fetchAudit(bid, after: page1.last, limit: 2);
      expect(page2.first.id, all[2].id, reason: 'pagination par curseur sans trou ni doublon');

      await client.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
