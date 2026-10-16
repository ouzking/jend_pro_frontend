import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/spreadsheet/xlsx.dart';
import 'package:jend_pro_mobile/features/exports/domain/export_sheets.dart';
import 'package:jend_pro_mobile/features/products/domain/product_import.dart';

void main() {
  test('montants saisis librement', () {
    expect(ProductImport.parseMoney('1500'), 1500);
    expect(ProductImport.parseMoney('1 500'), 1500);
    expect(ProductImport.parseMoney('1.500'), 1500);
    expect(ProductImport.parseMoney('1,500'), 1500);
    expect(ProductImport.parseMoney('1 500 F'), 1500);
    expect(ProductImport.parseMoney('14 500 FCFA'), 14500);
    expect(ProductImport.parseMoney('1500,00'), 1500);
    expect(ProductImport.parseMoney('99.6'), 100);
    expect(ProductImport.parseMoney('abc'), isNull);
    expect(ProductImport.parseMoney('-5'), isNull);
    expect(ProductImport.parseQuantity('2,5'), 2.5);
  });

  test('colonnes reconnues malgré des noms différents', () {
    final map = ProductImport.mapHeaders([
      'Désignation',
      'PV',
      'Unité',
      'Famille',
      'EAN',
      'Réf',
      'Prix d’achat',
      'Qté',
      'Alerte',
    ]);
    expect(map.values.toList(), [
      ImportField.name,
      ImportField.salePrice,
      ImportField.unit,
      ImportField.category,
      ImportField.barcode,
      ImportField.sku,
      ImportField.cost,
      ImportField.stock,
      ImportField.minLevel,
    ]);
  });

  test('aperçu : valides, erreurs, doublons (catalogue et fichier)', () {
    final p = ProductImport.preview(
      [
        ['Nom', 'Prix de vente', 'Unité', 'Code-barres', 'Stock'],
        ['Riz parfumé', '14 500', 'sac', '6001', '20'],
        ['Sucre', '700 F', 'kg', '', '12,5'],
        ['', '500', '', '', ''],
        ['Savon', 'gratuit', '', '', ''],
        ['Huile', '6500', '', '6009', ''],
        ['riz parfumé', '15000', '', '', ''],
        ['Lait', '1200', '', '6001', ''],
      ],
      existingNames: {'Huile'},
    );
    expect(p.error, isNull);
    expect(
      [for (final r in p.rows) (r.line, r.importable, r.duplicate, r.errors.isEmpty)],
      [
        (2, true, false, true),
        (3, true, false, true),
        (4, false, false, false),
        (5, false, false, false),
        (6, false, true, true),
        (7, false, true, true),
        (8, false, true, true),
      ],
    );
    final sucre = p.rows[1];
    expect((sucre.salePrice, sucre.stock, sucre.fractional), (700, 12.5, true));
    expect(p.rows[0].fractional, isFalse);
    expect(p.rows[3].errors.single, contains('Prix illisible'));
    expect((p.importable.length, p.duplicates, p.invalid), (2, 3, 2));
  });

  test('colonnes obligatoires absentes, fichier vide', () {
    expect(ProductImport.preview([]).error, contains('vide'));
    expect(
      ProductImport.preview([
        ['Article', 'Quantité'],
      ]).error,
      contains('Prix de vente'),
    );
  });

  test('le modèle d’import se relit tel quel', () {
    final table = Xlsx.readXlsx(Xlsx.write([ExportSheets.importTemplate()]));
    final p = ProductImport.preview(table);
    expect(p.error, isNull);
    expect(p.importable.map((r) => (r.name, r.salePrice, r.cost, r.stock)), [
      ('Riz parfumé 25 kg', 14500, 12000, 20),
      ('Sucre en poudre', 700, 550, 50),
    ]);
  });
}
