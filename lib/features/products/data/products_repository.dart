import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/supabase/guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/catalog_models.dart';

final productsRepositoryProvider = Provider<ProductsRepository>(
  (ref) => ProductsRepository(ref.watch(supabaseClientProvider)),
);

/// Catalogue : `categories`, `products`, `product_costs`.
class ProductsRepository {
  ProductsRepository(this._client);

  final SupabaseClient _client;

  static const _productColumns = 'id, name, sale_price, unit, track_stock, allows_fractional_quantity, category_id';

  Future<List<Category>> fetchCategories(String businessId) => guardSupabase(() async {
    final rows = await _client
        .from('categories')
        .select('id, name, parent_id')
        .eq('business_id', businessId)
        .eq('status', 'ACTIVE')
        .order('name', ascending: true);
    return rows.map(Category.fromRow).toList();
  });

  /// Crée les catégories absentes (comparaison insensible à la casse, comme
  /// l'index unique) et renvoie l'ensemble demandé.
  Future<List<Category>> ensureCategories(String businessId, List<String> names) => guardSupabase(() async {
    final existing = await fetchCategories(businessId);
    final known = {for (final c in existing.where((c) => c.parentId == null)) c.name.toLowerCase(): c};
    final missing = names.where((n) => !known.containsKey(n.trim().toLowerCase())).toList();
    if (missing.isNotEmpty) {
      final rows = await _client
          .from('categories')
          .insert([
            for (final n in missing) {'business_id': businessId, 'name': n.trim()},
          ])
          .select('id, name, parent_id');
      for (final c in rows.map(Category.fromRow)) {
        known[c.name.toLowerCase()] = c;
      }
    }
    return [for (final n in names) ?known[n.trim().toLowerCase()]];
  });

  Future<ProductSummary> createProduct(String businessId, NewProduct product) => guardSupabase(() async {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    final row = await _client
        .from('products')
        .insert({
          'business_id': businessId,
          'name': product.name.trim(),
          'description': clean(product.description),
          'sale_price': product.salePrice,
          'unit': product.unit.trim(),
          'category_id': product.categoryId,
          'track_stock': product.trackStock,
          'allows_fractional_quantity': product.allowsFractionalQuantity,
          'sku': clean(product.sku),
          'barcode': clean(product.barcode),
          if (product.minStockLevel != null) 'min_stock_level': product.minStockLevel,
        })
        .select(_productColumns)
        .single();
    final created = ProductSummary.fromRow(row);
    // La ligne de coût est créée par le serveur (coût 0) : on la met à jour.
    if (product.costPrice != null && product.costPrice! > 0) {
      await _client.from('product_costs').update({'cost_price': product.costPrice}).eq('product_id', created.id);
    }
    return created;
  });

  /// Page du catalogue : recherche sur nom / SKU / code-barres, filtre
  /// catégorie et statut, tri par nom (index `(business_id, name)`).
  Future<List<Product>> fetchProducts(
    String businessId,
    ProductFilter filter, {
    required int offset,
    required int limit,
  }) => guardSupabase(() async {
    var query = _client
        .from('products')
        .select(Product.columns)
        .eq('business_id', businessId)
        .eq('status', filter.status == ProductStatusFilter.active ? 'ACTIVE' : 'ARCHIVED');
    if (filter.categoryId != null) query = query.eq('category_id', filter.categoryId!);
    final q = sanitizeSearch(filter.query);
    if (q.isNotEmpty) query = query.or('name.ilike.*$q*,sku.ilike.*$q*,barcode.eq.${q.replaceAll(' ', '')}');
    final rows = await query.order('name', ascending: true).range(offset, offset + limit - 1);
    return rows.map(Product.fromRow).toList();
  });

  Future<Product> fetchProduct(String productId) => guardSupabase(() async {
    final row = await _client.from('products').select(Product.columns).eq('id', productId).single();
    return Product.fromRow(row);
  });

  /// Recherche exacte par code-barres (scanner) — index unique dédié.
  Future<Product?> findByBarcode(String businessId, String barcode) => guardSupabase(() async {
    final row = await _client
        .from('products')
        .select(Product.columns)
        .eq('business_id', businessId)
        .eq('barcode', barcode.replaceAll(RegExp(r'\s'), ''))
        .maybeSingle();
    return row == null ? null : Product.fromRow(row);
  });

  /// Colonnes modifiables par les clients (droits par colonne en base) :
  /// toute autre clé ferait échouer la requête entière.
  static const editableColumns = {
    'category_id',
    'name',
    'description',
    'sku',
    'barcode',
    'unit',
    'sale_price',
    'allows_fractional_quantity',
    'min_stock_level',
    'image_path',
  };

  Future<Product> updateProduct(String productId, Map<String, Object?> changes) => guardSupabase(() async {
    assert(changes.keys.every(editableColumns.contains), 'Colonne non modifiable : ${changes.keys}');
    final rows = await _client.from('products').update(changes).eq('id', productId).select(Product.columns);
    if (rows.isEmpty) {
      throw const AppFailure(FailureKind.permission, 'Vous n’avez pas l’autorisation de modifier ce produit.');
    }
    return Product.fromRow(rows.first);
  });

  /// Coût d'achat (`products.read_cost` + `products.update`).
  Future<void> setCost(String productId, int costPrice) => guardSupabase(() async {
    final rows = await _client
        .from('product_costs')
        .update({'cost_price': costPrice})
        .eq('product_id', productId)
        .select('product_id');
    if (rows.isEmpty) {
      throw const AppFailure(FailureKind.permission, 'Vous n’avez pas l’autorisation de modifier le coût.');
    }
  });

  /// Archiver / réactiver (`products.delete`, audité). Pas de suppression :
  /// l'historique reste intact.
  Future<void> setArchived(String productId, {required bool archived}) => guardSupabase(
    () => _client.rpc<void>(
      'set_product_status',
      params: {'p_product_id': productId, 'p_status': archived ? 'ARCHIVED' : 'ACTIVE'},
    ),
  );

  /// Photo : `product-images/{business_id}/{product_id}/{horodatage}.{ext}`
  /// (JPEG / PNG / WebP, 2 Mo), puis association au produit. L'ancienne
  /// image est supprimée au mieux.
  Future<Product> uploadImage(String businessId, Product product, Uint8List bytes, {required String mimeType}) =>
      guardSupabase(() async {
        final ext = switch (mimeType) {
          'image/png' => 'png',
          'image/webp' => 'webp',
          _ => 'jpg',
        };
        final path = '$businessId/${product.id}/${DateTime.now().microsecondsSinceEpoch}.$ext';
        final bucket = _client.storage.from('product-images');
        await bucket.uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mimeType));
        final updated = await updateProduct(product.id, {'image_path': path});
        if (product.imagePath != null) {
          await bucket.remove([product.imagePath!]).then<void>((_) {}, onError: (_) {});
        }
        return updated;
      });

  String publicImageUrl(String path) => _client.storage.from('product-images').getPublicUrl(path);

  Future<Category> createCategory(String businessId, String name, {String? parentId}) => guardSupabase(() async {
    final row = await _client
        .from('categories')
        .insert({'business_id': businessId, 'name': name.trim(), 'parent_id': parentId})
        .select('id, name, parent_id')
        .single();
    return Category.fromRow(row);
  });

  Future<void> renameCategory(String categoryId, String name) =>
      guardSupabase(() => _client.from('categories').update({'name': name.trim()}).eq('id', categoryId));

  /// Une catégorie utilisée ne peut pas être supprimée : on l'archive.
  Future<void> archiveCategory(String categoryId) =>
      guardSupabase(() => _client.from('categories').update({'status': 'ARCHIVED'}).eq('id', categoryId));

  /// Les caractères de syntaxe PostgREST (`,` `(` `)` `*` `%` `\`) cassent un
  /// filtre `or` : on les retire de la saisie.
  static String sanitizeSearch(String input) => input.replaceAll(RegExp(r'[,()*%\\]'), ' ').trim();
}
