/// Import du catalogue depuis un tableur : reconnaissance souple des
/// colonnes, lecture des montants saisis librement, contrôles avant envoi.
/// Code pur (sans Flutter) : entièrement testable.
library;

import 'catalog_models.dart';

/// Champs reconnus dans la ligne d'en-tête.
enum ImportField { name, salePrice, unit, category, barcode, sku, cost, stock, minLevel, description }

/// Ligne du fichier, prête à être importée ou à corriger.
class ImportRow {
  const ImportRow({
    required this.line,
    required this.name,
    required this.errors,
    this.salePrice,
    this.unit = 'pièce',
    this.category,
    this.barcode,
    this.sku,
    this.cost,
    this.stock,
    this.minLevel,
    this.description,
    this.duplicate = false,
  });

  /// Numéro de ligne dans le fichier (pour retrouver l'erreur).
  final int line;
  final String name;
  final int? salePrice;
  final String unit;
  final String? category;
  final String? barcode;
  final String? sku;
  final int? cost;
  final num? stock;
  final num? minLevel;
  final String? description;

  /// Problèmes empêchant l'import de cette ligne.
  final List<String> errors;

  /// Déjà dans le catalogue (même code-barres ou même nom) : ignorée.
  final bool duplicate;

  bool get importable => errors.isEmpty && !duplicate;

  /// Vente au poids / au volume pour les unités de mesure.
  bool get fractional => ProductImport.measureUnits.contains(ProductImport.normalize(unit));

  NewProduct toNewProduct({String? categoryId, bool withCost = true}) => NewProduct(
    name: name,
    salePrice: salePrice!,
    unit: unit,
    categoryId: categoryId,
    allowsFractionalQuantity: fractional,
    costPrice: withCost ? cost : null,
    sku: sku,
    barcode: barcode,
    minStockLevel: minLevel,
    description: description,
  );
}

class ImportPreview {
  const ImportPreview({required this.rows, required this.columns, this.error});

  final List<ImportRow> rows;

  /// Colonnes reconnues.
  final Set<ImportField> columns;

  /// Problème bloquant (fichier vide, colonnes obligatoires absentes).
  final String? error;

  List<ImportRow> get importable => rows.where((r) => r.importable).toList();
  int get duplicates => rows.where((r) => r.duplicate).length;
  int get invalid => rows.where((r) => r.errors.isNotEmpty).length;
}

abstract final class ProductImport {
  static const maxRows = 2000;

  static const measureUnits = {'kg', 'kilo', 'kilogramme', 'g', 'gramme', 'l', 'litre', 'cl', 'ml', 'm', 'metre'};

  static const _synonyms = {
    ImportField.name: ['nom', 'produit', 'article', 'designation', 'libelle', 'nom du produit', 'nom produit'],
    ImportField.salePrice: [
      'prix de vente',
      'prix',
      'pv',
      'prix vente',
      'prix unitaire',
      'tarif',
      'prix de vente (fcfa)',
    ],
    ImportField.unit: ['unite', 'unite de vente', 'conditionnement'],
    ImportField.category: ['categorie', 'famille', 'rayon', 'type'],
    ImportField.barcode: ['code barres', 'code barre', 'codebarre', 'ean', 'gencod', 'code ean'],
    ImportField.sku: ['reference', 'ref', 'sku', 'code article', 'code produit'],
    ImportField.cost: ["cout d achat", 'cout', 'prix d achat', 'pa', 'prix achat', 'cout achat'],
    ImportField.stock: ['stock', 'stock initial', 'quantite', 'qte', 'quantite en stock'],
    ImportField.minLevel: ["seuil d alerte", 'seuil', 'stock minimum', 'stock mini', 'alerte'],
    ImportField.description: ['description', 'details', 'note'],
  };

  static String normalize(String s) {
    const accents = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ñ': 'n',
      '’': ' ',
      "'": ' ',
    };
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      b.write(accents[ch] ?? ch);
    }
    return b.toString().replaceAll(RegExp(r'[^a-z0-9()]+'), ' ').trim();
  }

  /// Colonne → champ, d'après la ligne d'en-tête.
  static Map<int, ImportField> mapHeaders(List<String> header) {
    final map = <int, ImportField>{};
    for (final (i, h) in header.indexed) {
      final n = normalize(h);
      for (final e in _synonyms.entries) {
        if (map.containsValue(e.key)) continue;
        if (e.value.contains(n)) {
          map[i] = e.key;
          break;
        }
      }
    }
    return map;
  }

  /// Montant saisi librement : « 1 500 », « 1.500 », « 1 500 F », « 1500 FCFA »,
  /// « 1500,00 » → 1500. `null` si illisible.
  static int? parseMoney(String raw) {
    var s = raw.toLowerCase().replaceAll(RegExp(r'(f\s*cfa|fcfa|cfa|xof|francs?|f)\s*$'), '').trim();
    s = s.replaceAll(RegExp(r'[\s  ]'), '');
    if (s.isEmpty) return null;
    // 1.500 / 1,500 (milliers) vs 1500,00 / 1500.50 (décimales).
    if (RegExp(r'^\d{1,3}([.,]\d{3})+$').hasMatch(s)) s = s.replaceAll(RegExp(r'[.,]'), '');
    s = s.replaceAll(',', '.');
    final v = num.tryParse(s);
    if (v == null || v < 0) return null;
    return v.round();
  }

  static num? parseQuantity(String raw) {
    final s = raw.replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.');
    if (s.isEmpty) return null;
    final v = num.tryParse(s);
    return v == null || v < 0 ? null : v;
  }

  /// Analyse le tableau (première ligne = en-têtes).
  static ImportPreview preview(
    List<List<String>> table, {
    Set<String> existingNames = const {},
    Set<String> existingBarcodes = const {},
  }) {
    if (table.isEmpty) return const ImportPreview(rows: [], columns: {}, error: 'Le fichier est vide.');
    final map = mapHeaders(table.first);
    final columns = map.values.toSet();
    if (!columns.contains(ImportField.name) || !columns.contains(ImportField.salePrice)) {
      return ImportPreview(
        rows: const [],
        columns: columns,
        error:
            'Colonnes obligatoires introuvables : la première ligne doit contenir « Nom » et « Prix de vente ». '
            'Téléchargez le modèle pour voir le format attendu.',
      );
    }
    final dataRows = table.skip(1).take(maxRows).toList();
    final names = {for (final n in existingNames) n.trim().toLowerCase()};
    final barcodes = {...existingBarcodes};
    final seenNames = <String>{};
    final seenBarcodes = <String>{};

    final rows = <ImportRow>[];
    for (final (i, cells) in dataRows.indexed) {
      String? v(ImportField f) {
        final col = map.entries.where((e) => e.value == f).firstOrNull?.key;
        if (col == null || col >= cells.length) return null;
        final t = cells[col].trim();
        return t.isEmpty ? null : t;
      }

      final errors = <String>[];
      final name = v(ImportField.name) ?? '';
      if (name.isEmpty) errors.add('Nom manquant');
      if (name.length > 200) errors.add('Nom trop long');
      final priceText = v(ImportField.salePrice);
      final price = priceText == null ? null : parseMoney(priceText);
      if (priceText == null) {
        errors.add('Prix manquant');
      } else if (price == null) {
        errors.add('Prix illisible « $priceText »');
      }
      final costText = v(ImportField.cost);
      final cost = costText == null ? null : parseMoney(costText);
      if (costText != null && cost == null) errors.add('Coût illisible « $costText »');
      final stockText = v(ImportField.stock);
      final stock = stockText == null ? null : parseQuantity(stockText);
      if (stockText != null && stock == null) errors.add('Stock illisible « $stockText »');
      final minText = v(ImportField.minLevel);
      final minLevel = minText == null ? null : parseQuantity(minText);
      if (minText != null && minLevel == null) errors.add('Seuil illisible « $minText »');
      final barcode = v(ImportField.barcode)?.replaceAll(RegExp(r'\s'), '');

      final key = name.toLowerCase();
      final duplicate =
          errors.isEmpty &&
          (names.contains(key) ||
              seenNames.contains(key) ||
              (barcode != null && (barcodes.contains(barcode) || seenBarcodes.contains(barcode))));
      if (errors.isEmpty && !duplicate) {
        seenNames.add(key);
        if (barcode != null) seenBarcodes.add(barcode);
      }
      rows.add(
        ImportRow(
          line: i + 2,
          name: name,
          salePrice: price,
          unit: v(ImportField.unit) ?? 'pièce',
          category: v(ImportField.category),
          barcode: barcode,
          sku: v(ImportField.sku),
          cost: cost,
          stock: stock,
          minLevel: minLevel,
          description: v(ImportField.description),
          errors: errors,
          duplicate: duplicate,
        ),
      );
    }
    return ImportPreview(rows: rows, columns: columns);
  }
}
