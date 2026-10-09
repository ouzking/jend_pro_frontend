// Test d'intégration du tableau de bord contre un Supabase réel.
//   flutter test test/integration --dart-define-from-file=env/dev.json
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/config/env.dart';
import 'package:jend_pro_mobile/core/domain/payment_method.dart';
import 'package:jend_pro_mobile/core/formatting/business_time.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/business/data/business_repository.dart';
import 'package:jend_pro_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:jend_pro_mobile/features/dashboard/domain/dashboard_models.dart';
import 'package:jend_pro_mobile/features/inventory/data/inventory_repository.dart';
import 'package:jend_pro_mobile/features/products/data/products_repository.dart';
import 'package:jend_pro_mobile/features/products/domain/catalog_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support.dart';

void main() {
  final skip = Env.isConfigured ? false : 'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY non fournis';

  test(
    'indicateurs, série, top, stock faible et dernières ventes',
    () async {
      final client = SupabaseClient(
        Env.supabaseUrl,
        Env.supabasePublishableKey,
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      );
      final auth = AuthRepository(client);
      final business = BusinessRepository(client);
      final products = ProductsRepository(client);
      final inventory = InventoryRepository(client);
      final dashboard = DashboardRepository(client);

      await signUpForTest(
        auth,
        fullName: 'Test Dashboard',
        email: 'dashboard-${DateTime.now().millisecondsSinceEpoch}@test.jendpro.local',
        password: 'motdepasse-test',
      );
      final bid = await business.createBusiness(name: 'Boutique Dashboard');
      final loc = await business.fetchDefaultLocationId(bid);

      final huile = await products.createProduct(
        bid,
        const NewProduct(name: 'Huile 5 L', salePrice: 6500, costPrice: 5000, unit: 'bidon', minStockLevel: 5),
      );
      await inventory.setInitialStock(businessId: bid, productId: huile.id, locationId: loc, quantity: 8);
      final customer = await client
          .from('customers')
          .insert({'business_id': bid, 'name': 'Fatou Sow', 'phone': '771234567'})
          .select('id')
          .single();
      await client.rpc<dynamic>(
        'set_customer_credit_limit',
        params: {'p_customer_id': customer['id'], 'p_credit_limit': null},
      );

      // Vente : 4 bidons = 26 000, 20 000 Wave + 6 000 à crédit → stock 4 (≤ seuil 5).
      await client.rpc<dynamic>(
        'create_sale',
        params: {
          'p_business_id': bid,
          'p_client_reference': const Uuid().v4(),
          'p_location_id': loc,
          'p_items': [
            {'product_id': huile.id, 'quantity': 4},
          ],
          'p_payments': [
            {'method': 'WAVE', 'amount': 20000},
          ],
          'p_customer_id': customer['id'],
        },
      );

      final today = BusinessTime.today('Africa/Dakar');
      final period = DashboardPeriod.preset(PeriodKind.today, today);

      final summary = await dashboard.fetchSummary(bid, period);
      expect(summary.revenue, 26000);
      expect(summary.salesCount, 1);
      expect(summary.creditGiven, 6000);
      expect(summary.customersDebt, 6000);
      expect(summary.estimatedMargin, 6000, reason: 'OWNER a products.read_cost');
      expect(summary.lowStockCount, 1);

      final previous = await dashboard.fetchSummary(bid, period.previous);
      expect(previous.revenue, 0);

      final series = await dashboard.fetchSeries(bid, period);
      expect(series, hasLength(10), reason: 'fenêtre de 10 jours pour « aujourd’hui »');
      expect(series.last.revenue, 26000);

      final top = await dashboard.fetchTopProducts(bid, period);
      expect(top.single.name, 'Huile 5 L');
      expect(top.single.quantity, 4);

      final low = await dashboard.fetchLowStock(bid);
      expect(low.single.quantity, 4);
      expect(low.single.minLevel, 5);

      final recent = await dashboard.fetchRecentSales(bid);
      final sale = recent.single;
      expect(sale.total, 26000);
      expect(sale.customerName, 'Fatou Sow');
      expect(sale.firstItemName, 'Huile 5 L');
      expect(sale.paymentMethod, PaymentMethod.wave);
      expect(sale.creditAmount, 6000);
      expect(sale.number, startsWith('V-'));

      await auth.signOut();
      await client.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
