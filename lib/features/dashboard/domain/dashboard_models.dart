import '../../../core/domain/payment_method.dart';
import '../../../core/formatting/business_time.dart';

enum PeriodKind { today, week, month, custom }

/// Période analysée : bornes **incluses**, en jours locaux de l'entreprise
/// (366 jours maximum côté serveur).
class DashboardPeriod {
  const DashboardPeriod._(this.kind, this.from, this.to);

  factory DashboardPeriod.preset(PeriodKind kind, DateTime today) => switch (kind) {
    PeriodKind.today => DashboardPeriod._(kind, today, today),
    PeriodKind.week => DashboardPeriod._(kind, today.subtract(const Duration(days: 6)), today),
    PeriodKind.month => DashboardPeriod._(kind, today.subtract(const Duration(days: 29)), today),
    PeriodKind.custom => DashboardPeriod._(kind, today, today),
  };

  factory DashboardPeriod.custom(DateTime from, DateTime to) {
    final f = dateOnly(from);
    var t = dateOnly(to);
    if (t.difference(f).inDays > maxDays - 1) t = f.add(const Duration(days: maxDays - 1));
    return DashboardPeriod._(PeriodKind.custom, f, t);
  }

  static const maxDays = 366;

  final PeriodKind kind;
  final DateTime from;
  final DateTime to;

  int get days => to.difference(from).inDays + 1;

  /// Période de même durée juste avant (comparaison « vs hier », « vs 7 jours
  /// précédents »…).
  DashboardPeriod get previous {
    final end = from.subtract(const Duration(days: 1));
    return DashboardPeriod._(kind, end.subtract(Duration(days: days - 1)), end);
  }

  /// Fenêtre du graphique : pour « aujourd'hui », les 10 derniers jours
  /// (aujourd'hui mis en évidence), sinon la période elle-même.
  DashboardPeriod get chartWindow =>
      kind == PeriodKind.today ? DashboardPeriod._(kind, to.subtract(const Duration(days: 9)), to) : this;

  /// `day` jusqu'à 2 mois, puis `week`, puis `month` (lisibilité).
  String get granularity {
    final d = chartWindow.days;
    if (d <= 62) return 'day';
    if (d <= 190) return 'week';
    return 'month';
  }

  String get comparisonLabel => switch (kind) {
    PeriodKind.today => 'vs hier',
    PeriodKind.week => 'vs 7 jours précédents',
    PeriodKind.month => 'vs 30 jours précédents',
    PeriodKind.custom => 'vs période précédente',
  };

  @override
  bool operator ==(Object other) =>
      other is DashboardPeriod && other.kind == kind && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(kind, from, to);
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

int? _intOrNull(Object? v) => v == null ? null : _int(v);

num _num(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;

/// Résultat de `get_dashboard_summary` (calculé par le serveur — jamais
/// recalculé côté client).
class DashboardSummary {
  const DashboardSummary({
    required this.revenue,
    required this.salesCount,
    required this.averageBasket,
    required this.discounts,
    required this.creditGiven,
    required this.cancelledCount,
    required this.activeCustomers,
    required this.cashIn,
    required this.cashOut,
    required this.expenses,
    required this.netCashFlow,
    required this.customersDebt,
    required this.lowStockCount,
    this.estimatedMargin,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> j) => DashboardSummary(
    revenue: _int(j['revenue']),
    salesCount: _int(j['sales_count']),
    averageBasket: _int(j['average_basket']),
    discounts: _int(j['discounts']),
    creditGiven: _int(j['credit_given']),
    cancelledCount: _int(j['cancelled_count']),
    activeCustomers: _int(j['active_customers']),
    estimatedMargin: _intOrNull(j['estimated_margin']),
    cashIn: _int(j['cash_in']),
    cashOut: _int(j['cash_out']),
    expenses: _int(j['expenses']),
    netCashFlow: _int(j['net_cash_flow']),
    customersDebt: _int(j['customers_debt']),
    lowStockCount: _int(j['low_stock_count']),
  );

  final int revenue;
  final int salesCount;
  final int averageBasket;
  final int discounts;
  final int creditGiven;
  final int cancelledCount;
  final int activeCustomers;

  /// `null` sans la permission `products.read_cost`.
  final int? estimatedMargin;
  final int cashIn;
  final int cashOut;
  final int expenses;
  final int netCashFlow;
  final int customersDebt;
  final int lowStockCount;
}

class SalesPoint {
  const SalesPoint({required this.period, required this.revenue, required this.salesCount, this.estimatedMargin});

  factory SalesPoint.fromRow(Map<String, dynamic> r) => SalesPoint(
    period: DateTime.parse(r['period'] as String),
    revenue: _int(r['revenue']),
    salesCount: _int(r['sales_count']),
    estimatedMargin: _intOrNull(r['estimated_margin']),
  );

  final DateTime period;
  final int revenue;
  final int salesCount;
  final int? estimatedMargin;
}

class TopProduct {
  const TopProduct({required this.productId, required this.name, required this.quantity, required this.revenue});

  factory TopProduct.fromRow(Map<String, dynamic> r) => TopProduct(
    productId: r['product_id'] as String,
    name: r['product_name'] as String,
    quantity: _num(r['quantity']),
    revenue: _int(r['revenue']),
  );

  final String productId;
  final String name;
  final num quantity;
  final int revenue;
}

class LowStockItem {
  const LowStockItem({
    required this.productId,
    required this.name,
    required this.locationName,
    required this.quantity,
    required this.minLevel,
  });

  factory LowStockItem.fromRow(Map<String, dynamic> r) => LowStockItem(
    productId: r['product_id'] as String,
    name: r['product_name'] as String,
    locationName: r['location_name'] as String,
    quantity: _num(r['quantity']),
    minLevel: _num(r['min_stock_level']),
  );

  final String productId;
  final String name;
  final String locationName;
  final num quantity;
  final num minLevel;

  bool get isOut => quantity <= 0;
}

/// Ligne « Dernières ventes ».
class RecentSale {
  const RecentSale({
    required this.id,
    required this.number,
    required this.total,
    required this.soldAt,
    required this.itemCount,
    required this.cancelled,
    required this.creditAmount,
    this.firstItemName,
    this.firstItemQuantity,
    this.customerName,
    this.paymentMethod,
  });

  factory RecentSale.fromRow(Map<String, dynamic> r) {
    final items = (r['sale_items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final payments = (r['payments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final incoming = payments.where((p) => p['direction'] == 'IN').toList();
    return RecentSale(
      id: r['id'] as String,
      number: r['number'] as String,
      total: _int(r['total_amount']),
      soldAt: DateTime.parse(r['sold_at'] as String),
      cancelled: r['status'] == 'CANCELLED',
      creditAmount: _int(r['credit_amount']),
      itemCount: items.length,
      firstItemName: items.isEmpty ? null : items.first['product_name'] as String?,
      firstItemQuantity: items.isEmpty ? null : _num(items.first['quantity']),
      customerName: (r['customer'] as Map<String, dynamic>?)?['name'] as String?,
      paymentMethod: incoming.isEmpty ? null : PaymentMethod.fromCode(incoming.first['method'] as String?),
    );
  }

  final String id;
  final String number;
  final int total;
  final DateTime soldAt;
  final int itemCount;
  final bool cancelled;
  final int creditAmount;
  final String? firstItemName;
  final num? firstItemQuantity;
  final String? customerName;
  final PaymentMethod? paymentMethod;
}

/// Tout ce que l'accueil affiche, selon les permissions de l'utilisateur.
class DashboardData {
  const DashboardData({
    required this.period,
    this.summary,
    this.previous,
    this.series = const [],
    this.topProducts = const [],
    this.lowStock,
    this.recentSales = const [],
  });

  final DashboardPeriod period;

  /// `null` sans `reports.read` (ex. caissier).
  final DashboardSummary? summary;
  final DashboardSummary? previous;
  final List<SalesPoint> series;
  final List<TopProduct> topProducts;

  /// `null` sans `inventory.read`.
  final List<LowStockItem>? lowStock;
  final List<RecentSale> recentSales;

  /// Variation relative du CA vs la période précédente (`null` si non
  /// calculable : pas de base de comparaison).
  double? get revenueDelta {
    final now = summary?.revenue;
    final before = previous?.revenue;
    if (now == null || before == null || before == 0) return null;
    return (now - before) / before;
  }
}
