import 'package:flutter/material.dart';

import '../../../core/domain/payment_method.dart';

/// Catégorie de dépense (10 par défaut à la création de l'entreprise).
class ExpenseCategory {
  const ExpenseCategory({required this.id, required this.name});

  factory ExpenseCategory.fromRow(Map<String, dynamic> r) =>
      ExpenseCategory(id: r['id'] as String, name: r['name'] as String);

  final String id;
  final String name;

  /// Icône déduite du nom (catégories par défaut + noms courants).
  IconData get icon {
    final n = name.toLowerCase();
    if (n.contains('loyer')) return Icons.home_work_outlined;
    if (n.contains('électric') || n.contains('electric') || n.contains('senelec')) return Icons.bolt_outlined;
    if (n.contains('eau')) return Icons.water_drop_outlined;
    if (n.contains('salaire') || n.contains('personnel')) return Icons.badge_outlined;
    if (n.contains('transport') || n.contains('carburant')) return Icons.local_shipping_outlined;
    if (n.contains('fourniture')) return Icons.inventory_2_outlined;
    if (n.contains('internet') || n.contains('téléphone') || n.contains('telephone')) return Icons.wifi_rounded;
    if (n.contains('impôt') || n.contains('impot') || n.contains('taxe')) return Icons.account_balance_outlined;
    if (n.contains('entretien') || n.contains('réparation')) return Icons.build_outlined;
    return Icons.receipt_long_outlined;
  }
}

/// Dépense (`expenses`) — sortie d'argent hors achats fournisseurs.
class Expense {
  const Expense({
    required this.id,
    required this.categoryId,
    required this.amount,
    required this.spentOn,
    required this.method,
    required this.createdAt,
    this.categoryName,
    this.locationId,
    this.description,
    this.receiptPath,
  });

  static const columns =
      'id, category_id, location_id, amount, description, spent_on, method, receipt_path, created_at, '
      'category:expense_categories(name)';

  factory Expense.fromRow(Map<String, dynamic> r) => Expense(
    id: r['id'] as String,
    categoryId: r['category_id'] as String,
    categoryName: (r['category'] as Map<String, dynamic>?)?['name'] as String?,
    locationId: r['location_id'] as String?,
    amount: (r['amount'] as num).toInt(),
    description: r['description'] as String?,
    spentOn: DateTime.parse(r['spent_on'] as String),
    method: PaymentMethod.fromCode(r['method'] as String) ?? PaymentMethod.other,
    receiptPath: r['receipt_path'] as String?,
    createdAt: DateTime.parse(r['created_at'] as String),
  );

  final String id;
  final String categoryId;
  final String? categoryName;

  /// `null` : dépense générale (pas liée à un emplacement).
  final String? locationId;
  final int amount;
  final String? description;

  /// Jour de la dépense (pas forcément le jour de saisie).
  final DateTime spentOn;
  final PaymentMethod method;
  final String? receiptPath;
  final DateTime createdAt;

  ExpenseCategory get category => ExpenseCategory(id: categoryId, name: categoryName ?? '');
}

/// Données saisies (création / modification).
class ExpenseInput {
  const ExpenseInput({
    required this.categoryId,
    required this.amount,
    required this.spentOn,
    required this.method,
    this.description,
    this.locationId,
    this.receiptPath,
  });

  final String categoryId;
  final int amount;
  final DateTime spentOn;
  final PaymentMethod method;
  final String? description;
  final String? locationId;
  final String? receiptPath;

  Map<String, Object?> toColumns() => {
    'category_id': categoryId,
    'amount': amount,
    'spent_on':
        '${spentOn.year.toString().padLeft(4, '0')}-${spentOn.month.toString().padLeft(2, '0')}-${spentOn.day.toString().padLeft(2, '0')}',
    'method': method.code,
    'description': (description?.trim().isEmpty ?? true) ? null : description!.trim(),
    'location_id': locationId,
    'receipt_path': receiptPath,
  };
}

/// Mois affiché (bornes incluses, jours locaux).
class ExpenseMonth {
  const ExpenseMonth(this.year, this.month);

  factory ExpenseMonth.of(DateTime d) => ExpenseMonth(d.year, d.month);

  final int year;
  final int month;

  DateTime get first => DateTime(year, month);

  DateTime get last => DateTime(year, month + 1, 0);

  ExpenseMonth get previous => ExpenseMonth.of(DateTime(year, month - 1));

  ExpenseMonth get next => ExpenseMonth.of(DateTime(year, month + 1));

  bool isAfter(ExpenseMonth other) => year > other.year || (year == other.year && month > other.month);

  @override
  bool operator ==(Object other) => other is ExpenseMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}
