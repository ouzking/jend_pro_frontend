import '../../business/domain/workspace.dart';

/// Paramètres modifiables du commerce (`businesses`, colonnes autorisées en
/// écriture avec `settings.manage`).
class BusinessSettings {
  const BusinessSettings({
    required this.id,
    required this.name,
    required this.timezone,
    required this.currencyCode,
    required this.allowNegativeStock,
    this.legalName,
    this.ninea,
    this.rccm,
    this.phone,
    this.email,
    this.address,
    this.city,
    this.logoPath,
    this.largeSaleThreshold,
  });

  static const columns =
      'id, name, legal_name, ninea, rccm, phone, email, address, city, logo_path, timezone, currency_code, '
      'allow_negative_stock, large_sale_threshold';

  /// Colonnes texte éditées par le formulaire.
  static const textColumns = ['name', 'legal_name', 'ninea', 'rccm', 'phone', 'email', 'address', 'city'];

  factory BusinessSettings.fromRow(Map<String, dynamic> r) => BusinessSettings(
    id: r['id'] as String,
    name: r['name'] as String,
    legalName: r['legal_name'] as String?,
    ninea: r['ninea'] as String?,
    rccm: r['rccm'] as String?,
    phone: r['phone'] as String?,
    email: r['email'] as String?,
    address: r['address'] as String?,
    city: r['city'] as String?,
    logoPath: r['logo_path'] as String?,
    timezone: r['timezone'] as String,
    currencyCode: r['currency_code'] as String,
    allowNegativeStock: r['allow_negative_stock'] as bool,
    largeSaleThreshold: r['large_sale_threshold'] == null ? null : (r['large_sale_threshold'] as num).toInt(),
  );

  final String id;
  final String name;
  final String? legalName;
  final String? ninea;
  final String? rccm;
  final String? phone;
  final String? email;
  final String? address;
  final String? city;
  final String? logoPath;
  final String timezone;

  /// Fixée à la création (non modifiable par le client).
  final String currencyCode;
  final bool allowNegativeStock;
  final int? largeSaleThreshold;

  String? text(String column) => switch (column) {
    'name' => name,
    'legal_name' => legalName,
    'ninea' => ninea,
    'rccm' => rccm,
    'phone' => phone,
    'email' => email,
    'address' => address,
    'city' => city,
    _ => null,
  };
}

/// Fuseaux proposés (Afrique de l'Ouest). La base vérifie tout fuseau IANA.
const westAfricanTimezones = {
  'Africa/Dakar': 'Dakar (Sénégal)',
  'Africa/Abidjan': 'Abidjan (Côte d’Ivoire)',
  'Africa/Bamako': 'Bamako (Mali)',
  'Africa/Conakry': 'Conakry (Guinée)',
  'Africa/Nouakchott': 'Nouakchott (Mauritanie)',
  'Africa/Ouagadougou': 'Ouagadougou (Burkina Faso)',
  'Africa/Lome': 'Lomé (Togo)',
  'Africa/Banjul': 'Banjul (Gambie)',
  'Africa/Bissau': 'Bissau (Guinée-Bissau)',
  'Africa/Niamey': 'Niamey (Niger)',
  'Africa/Porto-Novo': 'Porto-Novo (Bénin)',
};

enum LocationKind {
  store('STORE', 'Boutique'),
  warehouse('WAREHOUSE', 'Dépôt');

  const LocationKind(this.code, this.label);

  final String code;
  final String label;

  static LocationKind parse(String? code) => code == 'WAREHOUSE' ? warehouse : store;
}

/// Emplacement complet (gestion), archivés compris.
class LocationDetail {
  const LocationDetail({
    required this.id,
    required this.name,
    required this.kind,
    required this.isDefault,
    required this.archived,
    this.address,
  });

  static const columns = 'id, name, type, address, is_default, status';

  factory LocationDetail.fromRow(Map<String, dynamic> r) => LocationDetail(
    id: r['id'] as String,
    name: r['name'] as String,
    kind: LocationKind.parse(r['type'] as String?),
    address: r['address'] as String?,
    isDefault: r['is_default'] as bool,
    archived: r['status'] == 'ARCHIVED',
  );

  final String id;
  final String name;
  final LocationKind kind;
  final String? address;

  /// L'emplacement par défaut ne peut pas être archivé (contrainte en base).
  final bool isDefault;
  final bool archived;
}

/// Formule publique (`subscription_plans`).
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.code,
    required this.name,
    required this.price,
    required this.currencyCode,
    required this.billingPeriod,
    required this.limits,
    this.description,
  });

  static const columns = 'code, name, description, price_amount, currency_code, billing_period, limits, sort_order';

  factory SubscriptionPlan.fromRow(Map<String, dynamic> r) => SubscriptionPlan(
    code: r['code'] as String,
    name: r['name'] as String,
    description: r['description'] as String?,
    price: (r['price_amount'] as num).toInt(),
    currencyCode: r['currency_code'] as String,
    billingPeriod: r['billing_period'] as String,
    limits: PlanQuota.fromLimits(r['limits']),
  );

  final String code;
  final String name;
  final String? description;
  final int price;
  final String currencyCode;

  /// `MONTHLY` / `YEARLY`.
  final String billingPeriod;
  final PlanQuota limits;

  String get periodLabel => billingPeriod == 'YEARLY' ? '/ an' : '/ mois';
}
