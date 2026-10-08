/// Catégorie (`categories`, deux niveaux maximum).
class Category {
  const Category({required this.id, required this.name, this.parentId});

  factory Category.fromRow(Map<String, dynamic> row) =>
      Category(id: row['id'] as String, name: row['name'] as String, parentId: row['parent_id'] as String?);

  final String id;
  final String name;
  final String? parentId;
}

/// Données de création d'un produit. `track_stock` n'est plus modifiable
/// ensuite (règle backend) : le choix est fait ici, une fois pour toutes.
class NewProduct {
  const NewProduct({
    required this.name,
    required this.salePrice,
    this.unit = 'pièce',
    this.categoryId,
    this.trackStock = true,
    this.allowsFractionalQuantity = false,
    this.costPrice,
    this.sku,
    this.barcode,
    this.minStockLevel,
    this.description,
  });

  final String name;
  final String? description;

  /// Entier en FCFA.
  final int salePrice;
  final String unit;
  final String? categoryId;
  final bool trackStock;
  final bool allowsFractionalQuantity;

  /// Coût d'achat (n'est envoyé que si l'utilisateur a `products.read_cost`).
  final int? costPrice;
  final String? sku;
  final String? barcode;
  final num? minStockLevel;
}

/// Produit tel que renvoyé après création (sous-ensemble utile aux listes).
class ProductSummary {
  const ProductSummary({
    required this.id,
    required this.name,
    required this.salePrice,
    required this.unit,
    required this.trackStock,
    required this.allowsFractionalQuantity,
    this.categoryId,
  });

  factory ProductSummary.fromRow(Map<String, dynamic> row) => ProductSummary(
    id: row['id'] as String,
    name: row['name'] as String,
    salePrice: (row['sale_price'] as num).toInt(),
    unit: row['unit'] as String,
    trackStock: row['track_stock'] as bool,
    allowsFractionalQuantity: row['allows_fractional_quantity'] as bool,
    categoryId: row['category_id'] as String?,
  );

  final String id;
  final String name;
  final int salePrice;
  final String unit;
  final bool trackStock;
  final bool allowsFractionalQuantity;
  final String? categoryId;
}

/// État de stock affiché sur les listes et fiches.
enum StockLevel { notTracked, unknown, out, low, ok }

/// Fiche produit complète (liste et détail).
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.unit,
    required this.salePrice,
    required this.trackStock,
    required this.allowsFractionalQuantity,
    required this.minStockLevel,
    required this.archived,
    this.description,
    this.sku,
    this.barcode,
    this.imagePath,
    this.categoryId,
    this.categoryName,
    this.stockQuantity,
    this.costPrice,
  });

  /// Colonnes lues : catégorie et stock (somme des emplacements) embarqués ;
  /// le coût n'est renvoyé qu'avec `products.read_cost` (RLS), sinon `null`.
  static const columns =
      'id, name, description, sku, barcode, unit, sale_price, track_stock, allows_fractional_quantity, '
      'min_stock_level, image_path, status, category_id, category:categories(name), '
      'inventory(quantity), cost:product_costs(cost_price)';

  factory Product.fromRow(Map<String, dynamic> r) {
    final inventory = (r['inventory'] as List?)?.cast<Map<String, dynamic>>();
    final cost = r['cost'];
    final costRow = cost is List
        ? (cost.isEmpty ? null : cost.first as Map<String, dynamic>)
        : cost as Map<String, dynamic>?;
    return Product(
      id: r['id'] as String,
      name: r['name'] as String,
      description: r['description'] as String?,
      sku: r['sku'] as String?,
      barcode: r['barcode'] as String?,
      unit: r['unit'] as String,
      salePrice: (r['sale_price'] as num).toInt(),
      trackStock: r['track_stock'] as bool,
      allowsFractionalQuantity: r['allows_fractional_quantity'] as bool,
      minStockLevel: num.parse('${r['min_stock_level']}'),
      imagePath: r['image_path'] as String?,
      archived: r['status'] == 'ARCHIVED',
      categoryId: r['category_id'] as String?,
      categoryName: (r['category'] as Map<String, dynamic>?)?['name'] as String?,
      // Aucune ligne d'inventaire visible : stock inconnu (droits) ou jamais saisi.
      stockQuantity: inventory == null || inventory.isEmpty
          ? null
          : inventory.fold<num>(0, (sum, row) => sum + num.parse('${row['quantity']}')),
      costPrice: costRow == null ? null : (costRow['cost_price'] as num).toInt(),
    );
  }

  final String id;
  final String name;
  final String? description;
  final String? sku;
  final String? barcode;
  final String unit;
  final int salePrice;
  final bool trackStock;
  final bool allowsFractionalQuantity;
  final num minStockLevel;
  final String? imagePath;
  final bool archived;
  final String? categoryId;
  final String? categoryName;

  /// Somme des emplacements visibles ; `null` si non suivi ou jamais saisi.
  final num? stockQuantity;

  /// `null` sans `products.read_cost`.
  final int? costPrice;

  StockLevel get stockLevel {
    if (!trackStock) return StockLevel.notTracked;
    final q = stockQuantity;
    if (q == null) return StockLevel.unknown;
    if (q <= 0) return StockLevel.out;
    if (minStockLevel > 0 && q <= minStockLevel) return StockLevel.low;
    return StockLevel.ok;
  }

  /// Marge unitaire (prix − coût) si le coût est connu et renseigné.
  int? get unitMargin => costPrice == null || costPrice == 0 ? null : salePrice - costPrice!;
}

enum ProductStatusFilter { active, archived }

/// Filtres de la liste du catalogue.
class ProductFilter {
  const ProductFilter({this.query = '', this.categoryId, this.status = ProductStatusFilter.active});

  final String query;
  final String? categoryId;
  final ProductStatusFilter status;

  ProductFilter copyWith({String? query, String? Function()? categoryId, ProductStatusFilter? status}) => ProductFilter(
    query: query ?? this.query,
    categoryId: categoryId != null ? categoryId() : this.categoryId,
    status: status ?? this.status,
  );

  bool get isDefault => query.isEmpty && categoryId == null && status == ProductStatusFilter.active;

  @override
  bool operator ==(Object other) =>
      other is ProductFilter && other.query == query && other.categoryId == categoryId && other.status == status;

  @override
  int get hashCode => Object.hash(query, categoryId, status);
}
