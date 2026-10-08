import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/formatting/business_time.dart';
import 'package:jend_pro_mobile/features/dashboard/domain/dashboard_models.dart';

void main() {
  final today = DateTime(2026, 10, 8);

  group('DashboardPeriod', () {
    test('aujourd’hui : comparaison avec hier, graphique sur 10 jours', () {
      final p = DashboardPeriod.preset(PeriodKind.today, today);
      expect(p.days, 1);
      expect(p.previous.from, DateTime(2026, 10, 7));
      expect(p.previous.to, DateTime(2026, 10, 7));
      expect(p.chartWindow.from, DateTime(2026, 9, 29));
      expect(p.chartWindow.to, today);
      expect(p.granularity, 'day');
      expect(p.comparisonLabel, 'vs hier');
    });

    test('7 et 30 jours incluent aujourd’hui ; la période précédente est contiguë', () {
      final week = DashboardPeriod.preset(PeriodKind.week, today);
      expect(week.days, 7);
      expect(week.from, DateTime(2026, 10, 2));
      expect(week.previous.to, DateTime(2026, 10, 1));
      expect(week.previous.days, 7);

      final month = DashboardPeriod.preset(PeriodKind.month, today);
      expect(month.days, 30);
      expect(month.previous.days, 30);
    });

    test('granularité adaptée à la durée', () {
      expect(DashboardPeriod.custom(DateTime(2026, 8, 8), today).granularity, 'day');
      expect(DashboardPeriod.custom(DateTime(2026, 5, 1), today).granularity, 'week');
      expect(DashboardPeriod.custom(DateTime(2025, 11, 1), today).granularity, 'month');
    });

    test('période personnalisée plafonnée à 366 jours (contrainte serveur)', () {
      final p = DashboardPeriod.custom(DateTime(2024, 1, 1), today);
      expect(p.days, DashboardPeriod.maxDays);
    });
  });

  test('variation du CA vs période précédente', () {
    DashboardSummary s(int revenue) => DashboardSummary(
      revenue: revenue,
      salesCount: 0,
      averageBasket: 0,
      discounts: 0,
      creditGiven: 0,
      cancelledCount: 0,
      activeCustomers: 0,
      cashIn: 0,
      cashOut: 0,
      expenses: 0,
      netCashFlow: 0,
      customersDebt: 0,
      lowStockCount: 0,
    );
    final period = DashboardPeriod.preset(PeriodKind.today, today);
    expect(
      DashboardData(period: period, summary: s(1248500), previous: s(1110700)).revenueDelta,
      closeTo(0.124, 0.001),
    );
    expect(DashboardData(period: period, summary: s(5000), previous: s(0)).revenueDelta, isNull);
  });

  test('jour de l’entreprise : Dakar = UTC, indépendamment du téléphone', () {
    final lateEvening = DateTime.utc(2026, 10, 8, 23, 30);
    expect(BusinessTime.today('Africa/Dakar', clock: lateEvening), DateTime(2026, 10, 8));
  });
}
