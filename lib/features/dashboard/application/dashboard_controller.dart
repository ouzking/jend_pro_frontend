import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/async/parallel.dart';
import '../../../core/formatting/business_time.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_models.dart';

/// Période sélectionnée sur l'accueil (« Aujourd'hui » par défaut).
final dashboardPeriodProvider = NotifierProvider<DashboardPeriodNotifier, DashboardPeriod>(DashboardPeriodNotifier.new);

class DashboardPeriodNotifier extends Notifier<DashboardPeriod> {
  DateTime get _today => BusinessTime.today(ref.read(activeBusinessProvider)?.timezone ?? 'Africa/Dakar');

  @override
  DashboardPeriod build() {
    // Nouvelle entreprise active → retour à « aujourd'hui ».
    ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    return DashboardPeriod.preset(PeriodKind.today, _today);
  }

  void select(PeriodKind kind) => state = DashboardPeriod.preset(kind, _today);

  void custom(DateTime from, DateTime to) => state = DashboardPeriod.custom(from, to);
}

/// Données de l'accueil, chargées en parallèle et **selon les permissions** :
/// un caissier ne déclenche aucun appel d'analytics qu'il ne peut pas lire.
final dashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) async {
  final business = ref.watch(activeBusinessProvider);
  final permissions = ref.watch(permissionsProvider);
  final period = ref.watch(dashboardPeriodProvider);
  final repository = ref.watch(dashboardRepositoryProvider);
  if (business == null) return DashboardData(period: period);
  final id = business.businessId;

  final canReport = permissions.can(Permission.reportsRead);
  final canStock = permissions.can(Permission.inventoryRead);
  final canSales = permissions.canSeeSales;

  final (summary, previous, series, top, lowStock, recent) = await parallel6(
    canReport ? repository.fetchSummary(id, period) : Future<DashboardSummary?>.value(),
    canReport ? repository.fetchSummary(id, period.previous) : Future<DashboardSummary?>.value(),
    canReport ? repository.fetchSeries(id, period) : Future.value(const <SalesPoint>[]),
    canReport ? repository.fetchTopProducts(id, period) : Future.value(const <TopProduct>[]),
    canStock ? repository.fetchLowStock(id) : Future<List<LowStockItem>?>.value(),
    canSales ? repository.fetchRecentSales(id) : Future.value(const <RecentSale>[]),
  );

  return DashboardData(
    period: period,
    summary: summary,
    previous: previous,
    series: series,
    topProducts: top,
    lowStock: lowStock,
    recentSales: recent,
  );
});
