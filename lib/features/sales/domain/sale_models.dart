import '../../../core/domain/payment_method.dart';

num _num(Object? v) => v is num ? v : num.parse('$v');
int _int(Object? v) => v is num ? v.toInt() : int.parse('$v');

/// Article vendable à la caisse (sous-ensemble du produit).
class SellableProduct {
  const SellableProduct({
    required this.id,
    required this.name,
    required this.unit,
    required this.salePrice,
    required this.trackStock,
    required this.allowsFractional,
    this.imagePath,
    this.barcode,
    this.categoryId,
    this.stockQuantity,
  });

  static const columns =
      'id, name, unit, sale_price, track_stock, allows_fractional_quantity, image_path, barcode, category_id, '
      'inventory(quantity)';

  factory SellableProduct.fromRow(Map<String, dynamic> r) {
    final inventory = (r['inventory'] as List?)?.cast<Map<String, dynamic>>();
    return SellableProduct(
      id: r['id'] as String,
      name: r['name'] as String,
      unit: r['unit'] as String,
      salePrice: _int(r['sale_price']),
      trackStock: r['track_stock'] as bool,
      allowsFractional: r['allows_fractional_quantity'] as bool,
      imagePath: r['image_path'] as String?,
      barcode: r['barcode'] as String?,
      categoryId: r['category_id'] as String?,
      stockQuantity: inventory == null || inventory.isEmpty
          ? null
          : inventory.fold<num>(0, (s, row) => s + _num(row['quantity'])),
    );
  }

  /// Cache hors ligne : même format que la ligne PostgREST.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'unit': unit,
    'sale_price': salePrice,
    'track_stock': trackStock,
    'allows_fractional_quantity': allowsFractional,
    'image_path': imagePath,
    'barcode': barcode,
    'category_id': categoryId,
    'inventory': stockQuantity == null
        ? <Object>[]
        : [
            {'quantity': stockQuantity},
          ],
  };

  final String id;
  final String name;
  final String unit;

  /// Prix catalogue (estimation : le serveur applique toujours le sien).
  final int salePrice;
  final bool trackStock;
  final bool allowsFractional;
  final String? imagePath;
  final String? barcode;
  final String? categoryId;
  final num? stockQuantity;
}

/// Client choisi à la caisse.
class SaleCustomer {
  const SaleCustomer({required this.id, required this.name, this.phone, this.balance = 0, this.creditLimit});

  static const columns = 'id, name, phone, balance, credit_limit';

  factory SaleCustomer.fromRow(Map<String, dynamic> r) => SaleCustomer(
    id: r['id'] as String,
    name: r['name'] as String,
    phone: r['phone'] as String?,
    balance: _int(r['balance']),
    creditLimit: r['credit_limit'] == null ? null : _int(r['credit_limit']),
  );

  final String id;
  final String name;
  final String? phone;

  /// Montant déjà dû par le client.
  final int balance;

  /// `0` = pas de crédit, `null` = sans plafond.
  final int? creditLimit;

  bool get creditAllowed => creditLimit == null || creditLimit! > 0;

  /// Crédit encore disponible (`null` = illimité).
  int? get creditAvailable => creditLimit == null ? null : (creditLimit! - balance).clamp(0, creditLimit!);
}

/// Paiement saisi à la caisse (le montant envoyé ne dépasse jamais le dû).
class PaymentEntry {
  const PaymentEntry({required this.method, required this.amount, this.externalReference});

  final PaymentMethod method;
  final int amount;
  final String? externalReference;

  Map<String, dynamic> toJson() => {
    'method': method.code,
    'amount': amount,
    if (externalReference?.trim().isNotEmpty ?? false) 'external_reference': externalReference!.trim(),
  };
}

/// Ligne de reçu (valeurs **figées** par le serveur).
class SaleLine {
  const SaleLine({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.lineTotal,
  });

  factory SaleLine.fromRow(Map<String, dynamic> r) => SaleLine(
    productName: r['product_name'] as String,
    quantity: _num(r['quantity']),
    unitPrice: _int(r['unit_price']),
    discount: _int(r['discount_amount']),
    lineTotal: _int(r['line_total']),
  );

  final String productName;
  final num quantity;
  final int unitPrice;
  final int discount;
  final int lineTotal;
}

class SalePayment {
  const SalePayment({required this.method, required this.amount, required this.incoming, required this.paidAt});

  factory SalePayment.fromRow(Map<String, dynamic> r) => SalePayment(
    method: PaymentMethod.fromCode(r['method'] as String) ?? PaymentMethod.other,
    amount: _int(r['amount']),
    incoming: r['direction'] == 'IN',
    paidAt: DateTime.parse(r['paid_at'] as String),
  );

  final PaymentMethod method;
  final int amount;

  /// `false` : remboursement (annulation).
  final bool incoming;
  final DateTime paidAt;
}

/// Vente telle qu'enregistrée (reçu, historique).
class Sale {
  const Sale({
    required this.id,
    required this.number,
    required this.soldAt,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.amountPaid,
    required this.creditAmount,
    required this.cancelled,
    this.lines = const [],
    this.payments = const [],
    this.customerName,
    this.cancelReason,
    this.cancelledAt,
    this.soldBy,
  });

  static const columns =
      'id, number, sold_at, sold_by, status, subtotal_amount, discount_amount, total_amount, amount_paid, '
      'credit_amount, cancel_reason, cancelled_at, customer:customers(name), '
      'sale_items(product_name, quantity, unit_price, discount_amount, line_total), '
      'payments(method, amount, direction, paid_at)';

  factory Sale.fromRow(Map<String, dynamic> r) => Sale(
    id: r['id'] as String,
    number: r['number'] as String,
    soldAt: DateTime.parse(r['sold_at'] as String),
    soldBy: r['sold_by'] as String?,
    subtotal: _int(r['subtotal_amount']),
    discount: _int(r['discount_amount']),
    total: _int(r['total_amount']),
    amountPaid: _int(r['amount_paid']),
    creditAmount: _int(r['credit_amount']),
    cancelled: r['status'] == 'CANCELLED',
    cancelReason: r['cancel_reason'] as String?,
    cancelledAt: r['cancelled_at'] == null ? null : DateTime.parse(r['cancelled_at'] as String),
    customerName: (r['customer'] as Map<String, dynamic>?)?['name'] as String?,
    lines: ((r['sale_items'] as List?) ?? const []).cast<Map<String, dynamic>>().map(SaleLine.fromRow).toList(),
    payments: ((r['payments'] as List?) ?? const []).cast<Map<String, dynamic>>().map(SalePayment.fromRow).toList()
      ..sort((a, b) => a.paidAt.compareTo(b.paidAt)),
  );

  final String id;
  final String number;
  final DateTime soldAt;
  final String? soldBy;
  final int subtotal;
  final int discount;
  final int total;
  final int amountPaid;
  final int creditAmount;
  final bool cancelled;
  final String? cancelReason;
  final DateTime? cancelledAt;
  final String? customerName;
  final List<SaleLine> lines;
  final List<SalePayment> payments;

  int get lineDiscounts => lines.fold(0, (s, l) => s + l.discount);

  int get itemCount => lines.length;
}
