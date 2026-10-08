import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/formatting/formatters.dart';
import '../../../core/supabase/guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/dashboard_models.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(supabaseClientProvider)),
);

/// Indicateurs calculés **en base** (RPC d'analytics) + dernières ventes.
class DashboardRepository {
  DashboardRepository(this._client);

  final SupabaseClient _client;

  Map<String, dynamic> _range(String businessId, DashboardPeriod p) => {
    'p_business_id': businessId,
    'p_from': Formatters.isoDay(p.from),
    'p_to': Formatters.isoDay(p.to),
  };

  Future<DashboardSummary> fetchSummary(String businessId, DashboardPeriod period) => guardSupabase(() async {
    final json = await _client.rpc<Map<String, dynamic>>('get_dashboard_summary', params: _range(businessId, period));
    return DashboardSummary.fromJson(json);
  });

  Future<List<SalesPoint>> fetchSeries(String businessId, DashboardPeriod period) => guardSupabase(() async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_sales_timeseries',
      params: {..._range(businessId, period.chartWindow), 'p_granularity': period.granularity},
    );
    return rows.cast<Map<String, dynamic>>().map(SalesPoint.fromRow).toList();
  });

  Future<List<TopProduct>> fetchTopProducts(String businessId, DashboardPeriod period, {int limit = 5}) =>
      guardSupabase(() async {
        final rows = await _client.rpc<List<dynamic>>(
          'get_top_products',
          params: {..._range(businessId, period), 'p_limit': limit},
        );
        return rows.cast<Map<String, dynamic>>().map(TopProduct.fromRow).toList();
      });

  Future<List<LowStockItem>> fetchLowStock(String businessId) => guardSupabase(() async {
    final rows = await _client.rpc<List<dynamic>>('list_low_stock', params: {'p_business_id': businessId});
    final items = rows.cast<Map<String, dynamic>>().map(LowStockItem.fromRow).toList()
      ..sort((a, b) => a.quantity.compareTo(b.quantity));
    return items;
  });

  /// Dernières ventes visibles : toutes (`sales.read`) ou les siennes
  /// (`sales.read_own`) — la RLS fait le tri.
  Future<List<RecentSale>> fetchRecentSales(String businessId, {int limit = 5}) => guardSupabase(() async {
    final rows = await _client
        .from('sales')
        .select(
          'id, number, total_amount, credit_amount, status, sold_at, '
          'customer:customers(name), sale_items(product_name, quantity), payments(method, direction)',
        )
        .eq('business_id', businessId)
        .order('sold_at', ascending: false)
        .limit(limit);
    return rows.map(RecentSale.fromRow).toList();
  });
}
