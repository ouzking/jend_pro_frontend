import 'package:flutter/material.dart';

int _int(Object? v) => v is num ? v.toInt() : int.parse('$v');

/// Fiche client (`customers`). `balance` = ce que le client **doit**.
class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.balance,
    required this.archived,
    required this.createdAt,
    this.creditLimit,
    this.phone,
    this.email,
    this.address,
    this.notes,
  });

  static const columns = 'id, name, phone, email, address, notes, balance, credit_limit, status, created_at';

  factory Customer.fromRow(Map<String, dynamic> r) => Customer(
    id: r['id'] as String,
    name: r['name'] as String,
    phone: r['phone'] as String?,
    email: r['email'] as String?,
    address: r['address'] as String?,
    notes: r['notes'] as String?,
    balance: _int(r['balance']),
    creditLimit: r['credit_limit'] == null ? null : _int(r['credit_limit']),
    archived: r['status'] == 'ARCHIVED',
    createdAt: DateTime.parse(r['created_at'] as String),
  );

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final int balance;

  /// `0` = pas de crédit ; `null` = sans plafond ; `> 0` = plafond.
  final int? creditLimit;
  final bool archived;
  final DateTime createdAt;

  bool get owes => balance > 0;

  bool get unlimitedCredit => creditLimit == null;

  bool get creditAllowed => creditLimit == null || creditLimit! > 0;

  /// Crédit encore disponible ; `null` = illimité.
  int? get creditAvailable => creditLimit == null ? null : (creditLimit! - balance).clamp(0, creditLimit!);

  /// Part du plafond déjà utilisée (0 → 1), `null` sans plafond.
  double? get creditUsage =>
      creditLimit == null || creditLimit == 0 ? null : (balance / creditLimit!).clamp(0, 1).toDouble();
}

/// Type d'écriture du compte client (`customer_transaction_type`).
enum CustomerTransactionType {
  creditSale('CREDIT_SALE', 'Achat à crédit', Icons.shopping_bag_outlined),
  payment('PAYMENT', 'Règlement', Icons.payments_outlined),
  adjustment('ADJUSTMENT', 'Ajustement', Icons.tune_rounded),
  saleCancellation('SALE_CANCELLATION', 'Vente annulée', Icons.undo_rounded);

  const CustomerTransactionType(this.code, this.label, this.icon);

  final String code;
  final String label;
  final IconData icon;

  static CustomerTransactionType fromCode(String code) =>
      values.firstWhere((t) => t.code == code, orElse: () => adjustment);
}

/// Ligne du relevé de compte (grand livre, en ajout seul).
class CustomerTransaction {
  const CustomerTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.createdAt,
    this.note,
    this.saleId,
    this.saleNumber,
  });

  static const columns = 'id, type, amount, balance_after, note, created_at, sale_id, sale:sales(number)';

  factory CustomerTransaction.fromRow(Map<String, dynamic> r) => CustomerTransaction(
    id: r['id'] as String,
    type: CustomerTransactionType.fromCode(r['type'] as String),
    amount: _int(r['amount']),
    balanceAfter: _int(r['balance_after']),
    note: r['note'] as String?,
    createdAt: DateTime.parse(r['created_at'] as String),
    saleId: r['sale_id'] as String?,
    saleNumber: (r['sale'] as Map<String, dynamic>?)?['number'] as String?,
  );

  final String id;
  final CustomerTransactionType type;

  /// Signé : + la dette augmente, − elle diminue.
  final int amount;
  final int balanceAfter;
  final DateTime createdAt;
  final String? note;
  final String? saleId;
  final String? saleNumber;
}

enum CustomerSegment { all, debtors, archived }

class CustomerFilter {
  const CustomerFilter({this.query = '', this.segment = CustomerSegment.all});

  final String query;
  final CustomerSegment segment;

  @override
  bool operator ==(Object other) => other is CustomerFilter && other.query == query && other.segment == segment;

  @override
  int get hashCode => Object.hash(query, segment);
}
