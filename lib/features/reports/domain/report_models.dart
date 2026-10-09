import '../../../core/formatting/business_time.dart';
import '../../../core/formatting/formatters.dart';
import '../../dashboard/domain/dashboard_models.dart';

/// Plages proposées dans les rapports (toujours ≤ 366 jours, limite serveur).
enum ReportRange {
  last7('7 jours'),
  last30('30 jours'),
  thisMonth('Ce mois'),
  lastMonth('Mois dernier'),
  thisYear('Cette année'),
  custom('Personnalisé');

  const ReportRange(this.label);

  final String label;

  DashboardPeriod resolve(DateTime today) => switch (this) {
    ReportRange.last7 => DashboardPeriod.custom(today.subtract(const Duration(days: 6)), today),
    ReportRange.last30 => DashboardPeriod.custom(today.subtract(const Duration(days: 29)), today),
    ReportRange.thisMonth => DashboardPeriod.custom(DateTime(today.year, today.month), today),
    ReportRange.lastMonth => DashboardPeriod.custom(
      DateTime(today.year, today.month - 1),
      DateTime(today.year, today.month, 0),
    ),
    ReportRange.thisYear => DashboardPeriod.custom(DateTime(today.year), today),
    ReportRange.custom => DashboardPeriod.custom(today, today),
  };
}

/// Plage choisie + période effective.
class ReportSelection {
  const ReportSelection(this.range, this.period);

  final ReportRange range;
  final DashboardPeriod period;

  String get label => range == ReportRange.custom || range == ReportRange.lastMonth || range == ReportRange.thisMonth
      ? periodLabel(period)
      : '${range.label} · ${periodLabel(period)}';

  static String periodLabel(DashboardPeriod p) =>
      p.from == p.to ? Formatters.date(p.from) : '${Formatters.date(p.from)} – ${Formatters.date(p.to)}';

  @override
  bool operator ==(Object other) => other is ReportSelection && other.range == range && other.period == period;

  @override
  int get hashCode => Object.hash(range, period);
}

/// Indicateur affiché sur le graphique.
enum ReportMetric {
  revenue('Chiffre d’affaires'),
  margin('Marge'),
  count('Ventes');

  const ReportMetric(this.label);

  final String label;
}

/// Données d'un rapport (toutes calculées par le serveur).
class ReportData {
  const ReportData({
    required this.period,
    required this.summary,
    required this.previous,
    required this.series,
    required this.topProducts,
  });

  final DashboardPeriod period;
  final DashboardSummary summary;
  final DashboardSummary previous;
  final List<SalesPoint> series;
  final List<TopProduct> topProducts;

  bool get hasMargin => summary.estimatedMargin != null;

  /// Taux de marge sur le CA (affichage uniquement).
  double? get marginRate =>
      summary.estimatedMargin == null || summary.revenue == 0 ? null : summary.estimatedMargin! / summary.revenue;

  /// Évolution relative ; `null` si la période précédente est vide.
  static double? delta(num now, num before) => before == 0 ? null : (now - before) / before;
}

// ------------------------------------------------------------------ Audit

/// Domaines filtrables (préfixe d'action côté serveur : `sale` → `sale.*`).
enum AuditDomain {
  all(null, 'Tout'),
  sale('sale', 'Ventes'),
  product('product', 'Produits'),
  inventory('inventory', 'Stock'),
  customer('customer', 'Clients'),
  purchase('purchase', 'Achats'),
  expense('expense', 'Dépenses'),
  member('member', 'Équipe'),
  business('business', 'Commerce');

  const AuditDomain(this.prefix, this.label);

  final String? prefix;
  final String label;
}

/// Entrée du journal d'audit (`get_audit_log`).
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.createdAt,
    required this.cursor,
    this.actorName,
    this.actorRole,
    this.resourceType,
    this.resourceId,
    this.metadata = const {},
  });

  factory AuditEntry.fromRow(Map<String, dynamic> r) => AuditEntry(
    id: r['id'] as String,
    action: r['action'] as String,
    createdAt: DateTime.parse(r['created_at'] as String),
    cursor: r['created_at'] as String,
    actorName: r['actor_name'] as String?,
    actorRole: r['actor_role'] as String?,
    resourceType: r['resource_type'] as String?,
    resourceId: r['resource_id'] as String?,
    metadata: (r['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
  );

  final String id;
  final String action;
  final DateTime createdAt;
  final String? actorName;
  final String? actorRole;
  final String? resourceType;
  final String? resourceId;
  final Map<String, dynamic> metadata;

  /// `created_at` brut, renvoyé tel quel comme curseur de pagination.
  final String cursor;

  String get label => auditActionLabel(action);

  /// Auteur lisible. `actor_role` est le rôle technique de la requête
  /// (`authenticated`, `service_role`…), pas le rôle dans le commerce.
  String get actorLabel => switch (actorRole) {
    'service_role' => actorName ?? 'Serveur JËND PRO',
    'postgres' || 'supabase_admin' => 'Maintenance',
    _ => actorName ?? 'Utilisateur',
  };

  String? get domain => action.contains('.') ? action.split('.').first : null;

  /// Résumé lisible des métadonnées (avant → après, montant, motif…).
  String? get details {
    final m = metadata;
    String fmt(Object? v) => switch (v) {
      int n
          when _moneyKeys.any((k) => m.containsKey(k)) ||
              action.contains('price') ||
              action.contains('cost') ||
              action.contains('salary') =>
        Formatters.money(n),
      num n => Formatters.quantity(n),
      null => '—',
      _ => '$v',
    };
    final parts = <String>[
      if (m.containsKey('old') || m.containsKey('new')) '${fmt(m['old'])} → ${fmt(m['new'])}',
      if (m.containsKey('from') && m.containsKey('to')) '${_roleOrStatus(m['from'])} → ${_roleOrStatus(m['to'])}',
      if (m['number'] != null) '${m['number']}',
      if (m['amount'] is num) Formatters.money((m['amount'] as num).toInt()),
      if (m['quantity'] is num) 'Qté ${Formatters.quantity(m['quantity'] as num)}',
      if (m['role'] != null && !m.containsKey('from')) _roleOrStatus(m['role']),
      if (m['reason'] is String && (m['reason'] as String).isNotEmpty) '« ${m['reason']} »',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static const _moneyKeys = {'amount', 'total_amount'};

  static String _roleOrStatus(Object? v) => switch (v) {
    'OWNER' => 'Propriétaire',
    'ADMIN' => 'Administrateur',
    'MANAGER' => 'Gérant',
    'CASHIER' => 'Caissier',
    'STOCK_MANAGER' => 'Magasinier',
    'ACTIVE' => 'Actif',
    'SUSPENDED' => 'Suspendu',
    'ARCHIVED' => 'Archivé',
    null => '—',
    _ => '$v',
  };
}

/// Libellés français des actions auditées par le backend.
String auditActionLabel(String action) => switch (action) {
  'business.create' => 'Création du commerce',
  'business.update' => 'Modification du commerce',
  'customer.balance_adjust' => 'Ajustement de dette client',
  'customer.credit_limit_change' => 'Plafond de crédit modifié',
  'customer.payment' => 'Règlement client',
  'employee.salary_change' => 'Salaire modifié',
  'expense.create' => 'Dépense enregistrée',
  'expense.update' => 'Dépense modifiée',
  'expense.delete' => 'Dépense supprimée',
  'inventory.adjust' => 'Ajustement de stock',
  'inventory.count' => 'Inventaire',
  'inventory.transfer' => 'Transfert de stock',
  'member.invite' => 'Invitation envoyée',
  'member.join' => 'Invitation acceptée',
  'member.decline' => 'Invitation refusée',
  'member.leave' => 'Membre parti',
  'member.remove' => 'Membre retiré',
  'member.role_change' => 'Rôle modifié',
  'member.status_change' => 'Accès suspendu / réactivé',
  'product.cost_change' => 'Coût d’achat modifié',
  'product.price_change' => 'Prix de vente modifié',
  'product.status_change' => 'Produit archivé / réactivé',
  'purchase.cancel' => 'Achat annulé',
  'purchase.payment' => 'Paiement fournisseur',
  'purchase.receive' => 'Achat réceptionné',
  'sale.cancel' => 'Vente annulée',
  'sale.discount' => 'Remise accordée',
  'subscription.change' => 'Abonnement modifié',
  _ => _humanize(action),
};

String _humanize(String action) {
  final s = action.replaceAll(RegExp(r'[._]'), ' ').trim();
  return s.isEmpty ? action : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Aujourd'hui dans le fuseau du commerce.
DateTime reportToday(String? timezone) => BusinessTime.today(timezone ?? 'Africa/Dakar');
