import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/async/parallel.dart';
import '../../../core/pagination/paged.dart';
import '../../business/application/workspace_controller.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../dashboard/domain/dashboard_models.dart';
import '../data/reports_repository.dart';
import '../domain/report_models.dart';

final reportSelectionProvider = NotifierProvider.autoDispose<ReportSelectionNotifier, ReportSelection>(
  ReportSelectionNotifier.new,
);

class ReportSelectionNotifier extends Notifier<ReportSelection> {
  DateTime get _today => reportToday(ref.read(activeBusinessProvider)?.timezone);

  @override
  ReportSelection build() => ReportSelection(ReportRange.last30, ReportRange.last30.resolve(_today));

  void select(ReportRange range) => state = ReportSelection(range, range.resolve(_today));

  void custom(DateTime from, DateTime to) =>
      state = ReportSelection(ReportRange.custom, DashboardPeriod.custom(from, to));
}

final reportMetricProvider = NotifierProvider.autoDispose<ReportMetricNotifier, ReportMetric>(ReportMetricNotifier.new);

class ReportMetricNotifier extends Notifier<ReportMetric> {
  @override
  ReportMetric build() => ReportMetric.revenue;

  void set(ReportMetric m) => state = m;
}

final reportDataProvider = FutureProvider.autoDispose<ReportData>((ref) async {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  final period = ref.watch(reportSelectionProvider.select((s) => s.period));
  if (businessId == null) throw StateError('Aucun commerce actif');
  final repo = ref.watch(dashboardRepositoryProvider);
  final (summary, previous, series, top) = await parallel4(
    repo.fetchSummary(businessId, period),
    repo.fetchSummary(businessId, period.previous),
    repo.fetchSeries(businessId, period),
    repo.fetchTopProducts(businessId, period, limit: 10),
  );
  return ReportData(period: period, summary: summary, previous: previous, series: series, topProducts: top);
});

// ------------------------------------------------------------------ Audit

final auditDomainProvider = NotifierProvider.autoDispose<AuditDomainNotifier, AuditDomain>(AuditDomainNotifier.new);

class AuditDomainNotifier extends Notifier<AuditDomain> {
  @override
  AuditDomain build() => AuditDomain.all;

  void set(AuditDomain d) => state = d;
}

final auditLogProvider = AsyncNotifierProvider.autoDispose<AuditLogController, Paged<AuditEntry>>(
  AuditLogController.new,
);

class AuditLogController extends AsyncNotifier<Paged<AuditEntry>> {
  static const pageSize = 50;

  @override
  Future<Paged<AuditEntry>> build() async {
    final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    final domain = ref.watch(auditDomainProvider);
    if (businessId == null) return const Paged(items: [], hasMore: false);
    final items = await ref
        .read(reportsRepositoryProvider)
        .fetchAudit(businessId, action: domain.prefix, limit: pageSize);
    return Paged(items: items, hasMore: items.length == pageSize);
  }

  /// Pagination par curseur (pas d'offset : le journal grossit en continu).
  Future<void> loadMore() async {
    final current = state.value;
    final businessId = ref.read(activeBusinessProvider)?.businessId;
    if (current == null || businessId == null || !current.hasMore || current.loadingMore || state.isLoading) return;
    if (current.items.isEmpty) return;
    state = AsyncData(current.copyWith(loadingMore: true, loadMoreError: () => null));
    try {
      final next = await ref
          .read(reportsRepositoryProvider)
          .fetchAudit(
            businessId,
            after: current.items.last,
            action: ref.read(auditDomainProvider).prefix,
            limit: pageSize,
          );
      if (ref.mounted) state = AsyncData(current.append(next, pageSize: pageSize, keyOf: (e) => e.id));
    } catch (e) {
      if (ref.mounted) state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: () => e));
    }
  }
}
