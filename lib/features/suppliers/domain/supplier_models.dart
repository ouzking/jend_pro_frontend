int _int(Object? v) => v is num ? v.toInt() : int.parse('$v');

/// Fiche fournisseur (`suppliers`).
class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    required this.archived,
    this.contactName,
    this.phone,
    this.email,
    this.address,
    this.notes,
  });

  static const columns = 'id, name, contact_name, phone, email, address, notes, status';

  factory Supplier.fromRow(Map<String, dynamic> r) => Supplier(
    id: r['id'] as String,
    name: r['name'] as String,
    contactName: r['contact_name'] as String?,
    phone: r['phone'] as String?,
    email: r['email'] as String?,
    address: r['address'] as String?,
    notes: r['notes'] as String?,
    archived: r['status'] == 'ARCHIVED',
  );

  final String id;
  final String name;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool archived;
}

/// Situation financière (vue `supplier_balances`, calculée en base).
class SupplierBalance {
  const SupplierBalance({this.amountDue = 0, this.advancesPaid = 0, this.unpaidPurchases = 0});

  factory SupplierBalance.fromRow(Map<String, dynamic> r) => SupplierBalance(
    amountDue: r['amount_due'] == null ? 0 : _int(r['amount_due']),
    advancesPaid: r['advances_paid'] == null ? 0 : _int(r['advances_paid']),
    unpaidPurchases: r['unpaid_purchases'] == null ? 0 : _int(r['unpaid_purchases']),
  );

  /// Reste à payer sur les achats **reçus**.
  final int amountDue;

  /// Acomptes versés sur des achats pas encore reçus.
  final int advancesPaid;
  final int unpaidPurchases;

  bool get owed => amountDue > 0;
}

/// Produit fourni par un fournisseur (`supplier_products`).
class SupplierProduct {
  const SupplierProduct({
    required this.productId,
    required this.productName,
    required this.unit,
    this.supplierSku,
    this.lastCost,
    this.imagePath,
    this.allowsFractional = false,
  });

  static const columns =
      'product_id, supplier_sku, last_cost, product:products(name, unit, image_path, allows_fractional_quantity)';

  factory SupplierProduct.fromRow(Map<String, dynamic> r) {
    final product = r['product'] as Map<String, dynamic>;
    return SupplierProduct(
      productId: r['product_id'] as String,
      productName: product['name'] as String,
      unit: product['unit'] as String,
      imagePath: product['image_path'] as String?,
      allowsFractional: (product['allows_fractional_quantity'] as bool?) ?? false,
      supplierSku: r['supplier_sku'] as String?,
      lastCost: r['last_cost'] == null ? null : _int(r['last_cost']),
    );
  }

  final String productId;
  final String productName;
  final String unit;
  final String? imagePath;
  final bool allowsFractional;

  /// Référence de l'article chez le fournisseur.
  final String? supplierSku;

  /// Dernier coût d'achat (mis à jour par les réceptions).
  final int? lastCost;
}

/// Achat (résumé pour les listes) — détail et cycle de vie en phase Achats.
class PurchaseSummary {
  const PurchaseSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.total,
    required this.amountPaid,
    required this.createdAt,
    this.receivedAt,
    this.supplierName,
  });

  static const columns =
      'id, number, status, total_amount, amount_paid, created_at, received_at, supplier:suppliers(name)';

  factory PurchaseSummary.fromRow(Map<String, dynamic> r) => PurchaseSummary(
    id: r['id'] as String,
    number: r['number'] as String,
    status: r['status'] as String,
    total: _int(r['total_amount']),
    amountPaid: _int(r['amount_paid']),
    createdAt: DateTime.parse(r['created_at'] as String),
    receivedAt: r['received_at'] == null ? null : DateTime.parse(r['received_at'] as String),
    supplierName: (r['supplier'] as Map<String, dynamic>?)?['name'] as String?,
  );

  final String id;
  final String number;

  /// `DRAFT`, `ORDERED`, `RECEIVED`, `CANCELLED`.
  final String status;
  final int total;
  final int amountPaid;
  final DateTime createdAt;
  final DateTime? receivedAt;
  final String? supplierName;

  int get remaining => total - amountPaid;
}

enum SupplierSegment { all, toPay, archived }
