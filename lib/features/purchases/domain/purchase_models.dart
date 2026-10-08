import '../../../core/domain/payment_method.dart';
import '../../suppliers/domain/supplier_models.dart';

int _int(Object? v) => v is num ? v.toInt() : int.parse('$v');
num _num(Object? v) => v is num ? v : num.parse('$v');

enum PurchaseStatus {
  draft('DRAFT', 'Brouillon'),
  ordered('ORDERED', 'Commandé'),
  received('RECEIVED', 'Reçu'),
  cancelled('CANCELLED', 'Annulé');

  const PurchaseStatus(this.code, this.label);

  final String code;
  final String label;

  static PurchaseStatus fromCode(String code) => values.firstWhere((s) => s.code == code, orElse: () => draft);

  /// Les lignes ne se modifient qu'avant réception.
  bool get editable => this == draft || this == ordered;
}

class PurchaseLine {
  const PurchaseLine({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    required this.lineTotal,
    required this.allowsFractional,
  });

  factory PurchaseLine.fromRow(Map<String, dynamic> r) {
    final product = r['product'] as Map<String, dynamic>?;
    return PurchaseLine(
      productId: r['product_id'] as String,
      productName: (product?['name'] as String?) ?? 'Produit',
      unit: (product?['unit'] as String?) ?? '',
      allowsFractional: (product?['allows_fractional_quantity'] as bool?) ?? false,
      quantity: _num(r['quantity']),
      unitCost: _int(r['unit_cost']),
      lineTotal: _int(r['line_total']),
    );
  }

  final String productId;
  final String productName;
  final String unit;
  final num quantity;
  final int unitCost;
  final int lineTotal;
  final bool allowsFractional;
}

class PurchasePayment {
  const PurchasePayment({required this.method, required this.amount, required this.paidAt, this.note});

  factory PurchasePayment.fromRow(Map<String, dynamic> r) => PurchasePayment(
    method: PaymentMethod.fromCode(r['method'] as String) ?? PaymentMethod.other,
    amount: _int(r['amount']),
    paidAt: DateTime.parse(r['paid_at'] as String),
    note: r['note'] as String?,
  );

  final PaymentMethod method;
  final int amount;
  final DateTime paidAt;
  final String? note;
}

/// Achat complet (`purchases` + lignes + paiements sortants).
class Purchase {
  const Purchase({
    required this.id,
    required this.number,
    required this.status,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.amountPaid,
    required this.locationId,
    required this.createdAt,
    this.supplierId,
    this.supplierName,
    this.supplierReference,
    this.notes,
    this.orderedAt,
    this.receivedAt,
    this.cancelledAt,
    this.cancelReason,
    this.lines = const [],
    this.payments = const [],
  });

  static const columns =
      'id, number, status, subtotal_amount, discount_amount, total_amount, amount_paid, location_id, created_at, '
      'supplier_id, supplier_reference, notes, ordered_at, received_at, cancelled_at, cancel_reason, '
      'supplier:suppliers(name), '
      'purchase_items(product_id, quantity, unit_cost, line_total, product:products(name, unit, allows_fractional_quantity)), '
      'payments(method, amount, paid_at, note)';

  factory Purchase.fromRow(Map<String, dynamic> r) => Purchase(
    id: r['id'] as String,
    number: r['number'] as String,
    status: PurchaseStatus.fromCode(r['status'] as String),
    subtotal: _int(r['subtotal_amount']),
    discount: _int(r['discount_amount']),
    total: _int(r['total_amount']),
    amountPaid: _int(r['amount_paid']),
    locationId: r['location_id'] as String,
    createdAt: DateTime.parse(r['created_at'] as String),
    supplierId: r['supplier_id'] as String?,
    supplierName: (r['supplier'] as Map<String, dynamic>?)?['name'] as String?,
    supplierReference: r['supplier_reference'] as String?,
    notes: r['notes'] as String?,
    orderedAt: _date(r['ordered_at']),
    receivedAt: _date(r['received_at']),
    cancelledAt: _date(r['cancelled_at']),
    cancelReason: r['cancel_reason'] as String?,
    lines: ((r['purchase_items'] as List?) ?? const []).cast<Map<String, dynamic>>().map(PurchaseLine.fromRow).toList(),
    payments: ((r['payments'] as List?) ?? const []).cast<Map<String, dynamic>>().map(PurchasePayment.fromRow).toList()
      ..sort((a, b) => a.paidAt.compareTo(b.paidAt)),
  );

  static DateTime? _date(Object? v) => v is String ? DateTime.parse(v) : null;

  final String id;
  final String number;
  final PurchaseStatus status;
  final int subtotal;
  final int discount;
  final int total;
  final int amountPaid;
  final String locationId;
  final DateTime createdAt;
  final String? supplierId;
  final String? supplierName;
  final String? supplierReference;
  final String? notes;
  final DateTime? orderedAt;
  final DateTime? receivedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final List<PurchaseLine> lines;
  final List<PurchasePayment> payments;

  int get remaining => total - amountPaid;

  bool get fullyPaid => remaining <= 0;
}

/// Ligne en cours de saisie (brouillon local avant `save_purchase`).
class DraftLine {
  const DraftLine({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.allowsFractional,
    required this.quantity,
    required this.unitCost,
  });

  final String productId;
  final String productName;
  final String unit;
  final bool allowsFractional;
  final num quantity;
  final int unitCost;

  /// Estimation (le serveur recalcule : `round(quantité × coût)`).
  int get total => (quantity * unitCost).round();

  DraftLine copyWith({num? quantity, int? unitCost}) => DraftLine(
    productId: productId,
    productName: productName,
    unit: unit,
    allowsFractional: allowsFractional,
    quantity: quantity ?? this.quantity,
    unitCost: unitCost ?? this.unitCost,
  );

  Map<String, dynamic> toJson() => {'product_id': productId, 'quantity': quantity, 'unit_cost': unitCost};

  factory DraftLine.fromLine(PurchaseLine l) => DraftLine(
    productId: l.productId,
    productName: l.productName,
    unit: l.unit,
    allowsFractional: l.allowsFractional,
    quantity: l.quantity,
    unitCost: l.unitCost,
  );
}

/// Achat en cours de saisie.
class PurchaseDraft {
  const PurchaseDraft({
    this.purchaseId,
    this.supplier,
    this.locationId,
    this.lines = const [],
    this.discount = 0,
    this.supplierReference,
    this.notes,
  });

  final String? purchaseId;
  final Supplier? supplier;
  final String? locationId;
  final List<DraftLine> lines;
  final int discount;
  final String? supplierReference;
  final String? notes;

  int get subtotal => lines.fold(0, (s, l) => s + l.total);

  int get total => (subtotal - discount).clamp(0, subtotal);

  PurchaseDraft copyWith({
    Supplier? Function()? supplier,
    String? locationId,
    List<DraftLine>? lines,
    int? discount,
    String? Function()? supplierReference,
    String? Function()? notes,
  }) => PurchaseDraft(
    purchaseId: purchaseId,
    supplier: supplier != null ? supplier() : this.supplier,
    locationId: locationId ?? this.locationId,
    lines: lines ?? this.lines,
    discount: discount ?? this.discount,
    supplierReference: supplierReference != null ? supplierReference() : this.supplierReference,
    notes: notes != null ? notes() : this.notes,
  );

  /// Ajoute ou remplace (un produit une seule fois par achat).
  PurchaseDraft upsertLine(DraftLine line) {
    final i = lines.indexWhere((l) => l.productId == line.productId);
    final next = [...lines];
    i == -1 ? next.add(line) : next[i] = line;
    return copyWith(lines: next);
  }

  PurchaseDraft removeLine(String productId) => copyWith(lines: lines.where((l) => l.productId != productId).toList());
}

enum PurchaseSegment { all, open, received, unpaid }
