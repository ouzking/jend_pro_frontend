import 'package:flutter/material.dart';

num _num(Object? v) => v is num ? v : num.parse('$v');

/// Emplacement (boutique / dépôt).
class StockLocation {
  const StockLocation({required this.id, required this.name, required this.isDefault, required this.isWarehouse});

  factory StockLocation.fromRow(Map<String, dynamic> r) => StockLocation(
    id: r['id'] as String,
    name: r['name'] as String,
    isDefault: r['is_default'] as bool,
    isWarehouse: r['type'] == 'WAREHOUSE',
  );

  final String id;
  final String name;
  final bool isDefault;
  final bool isWarehouse;
}

/// Ligne de stock : un produit à un emplacement (`inventory`).
class StockRow {
  const StockRow({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.locationId,
    required this.quantity,
    required this.minLevel,
    required this.allowsFractional,
    this.locationName,
    this.imagePath,
  });

  static const columns =
      'quantity, location_id, location:locations(name), '
      'product:products!inner(id, name, unit, min_stock_level, image_path, allows_fractional_quantity, status)';

  factory StockRow.fromRow(Map<String, dynamic> r) {
    final product = r['product'] as Map<String, dynamic>;
    return StockRow(
      productId: product['id'] as String,
      productName: product['name'] as String,
      unit: product['unit'] as String,
      imagePath: product['image_path'] as String?,
      minLevel: _num(product['min_stock_level']),
      allowsFractional: product['allows_fractional_quantity'] as bool,
      locationId: r['location_id'] as String,
      locationName: (r['location'] as Map<String, dynamic>?)?['name'] as String?,
      quantity: _num(r['quantity']),
    );
  }

  /// Résultat de `list_low_stock` (pas d'image ni d'unité : complétées
  /// par une lecture des produits concernés).
  factory StockRow.fromLowStock(Map<String, dynamic> r, {required Map<String, Map<String, dynamic>> products}) {
    final product = products[r['product_id']] ?? const {};
    return StockRow(
      productId: r['product_id'] as String,
      productName: r['product_name'] as String,
      locationId: r['location_id'] as String,
      locationName: r['location_name'] as String?,
      quantity: _num(r['quantity']),
      minLevel: _num(r['min_stock_level']),
      unit: (product['unit'] as String?) ?? '',
      imagePath: product['image_path'] as String?,
      allowsFractional: (product['allows_fractional_quantity'] as bool?) ?? false,
    );
  }

  final String productId;
  final String productName;
  final String unit;
  final String locationId;
  final String? locationName;
  final num quantity;
  final num minLevel;
  final bool allowsFractional;
  final String? imagePath;

  bool get isOut => quantity <= 0;

  bool get isLow => !isOut && minLevel > 0 && quantity <= minLevel;
}

enum StockFilter { all, low, out }

/// Types de mouvements (`inventory_movement_type`).
enum MovementType {
  initial('INITIAL', 'Stock initial', Icons.flag_outlined),
  purchase('PURCHASE', 'Achat reçu', Icons.local_shipping_outlined),
  sale('SALE', 'Vente', Icons.point_of_sale_rounded),
  saleCancellation('SALE_CANCELLATION', 'Vente annulée', Icons.undo_rounded),
  saleReturn('RETURN', 'Retour client', Icons.keyboard_return_rounded),
  adjustment('ADJUSTMENT', 'Ajustement', Icons.tune_rounded),
  transferOut('TRANSFER_OUT', 'Transfert sortant', Icons.north_east_rounded),
  transferIn('TRANSFER_IN', 'Transfert entrant', Icons.south_west_rounded),
  loss('LOSS', 'Perte / vol', Icons.report_outlined),
  damage('DAMAGE', 'Casse / périmé', Icons.broken_image_outlined);

  const MovementType(this.code, this.label, this.icon);

  final String code;
  final String label;
  final IconData icon;

  static MovementType fromCode(String code) => values.firstWhere((t) => t.code == code, orElse: () => adjustment);
}

/// Mouvement du grand livre (`inventory_movements`, en ajout seul).
class StockMovement {
  const StockMovement({
    required this.id,
    required this.type,
    required this.quantity,
    required this.quantityAfter,
    required this.createdAt,
    required this.locationId,
    this.locationName,
    this.reason,
    this.createdBy,
  });

  static const columns =
      'id, type, quantity, quantity_after, reason, created_at, created_by, location_id, location:locations(name)';

  factory StockMovement.fromRow(Map<String, dynamic> r) => StockMovement(
    id: r['id'] as String,
    type: MovementType.fromCode(r['type'] as String),
    quantity: _num(r['quantity']),
    quantityAfter: _num(r['quantity_after']),
    reason: r['reason'] as String?,
    createdAt: DateTime.parse(r['created_at'] as String),
    createdBy: r['created_by'] as String?,
    locationId: r['location_id'] as String,
    locationName: (r['location'] as Map<String, dynamic>?)?['name'] as String?,
  );

  final String id;
  final MovementType type;

  /// Quantité signée (+ entrée, − sortie).
  final num quantity;
  final num quantityAfter;
  final DateTime createdAt;
  final String locationId;
  final String? locationName;
  final String? reason;
  final String? createdBy;
}

/// Stock d'un produit à un emplacement (écran produit).
class LocationStock {
  const LocationStock({required this.location, this.quantity});

  final StockLocation location;

  /// `null` : aucun mouvement encore (le stock initial peut être saisi).
  final num? quantity;
}
