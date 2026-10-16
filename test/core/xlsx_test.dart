import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/spreadsheet/xlsx.dart';

void main() {
  test('écriture puis relecture d’un classeur', () {
    final bytes = Xlsx.write([
      XlsxSheet(
        name: 'Produits',
        headers: const ['Nom', 'Prix', 'Stock', 'Date'],
        rows: [
          ['Riz parfumé « 25 kg » & co', 14500, 2.5, DateTime(2026, 10, 15, 9, 30)],
          ['Huile <Niinal>', 6500, null, null],
          ['ñaar ŋ', 0, 1, null],
        ],
      ),
      const XlsxSheet(name: 'Produits', headers: ['A'], rows: []),
    ]);
    final out = Platform.environment['XLSX_DUMP'];
    if (out != null) File(out).writeAsBytesSync(bytes);
    final rows = Xlsx.readXlsx(bytes);
    expect(rows.first, ['Nom', 'Prix', 'Stock', 'Date']);
    expect(rows[1].take(3), ['Riz parfumé « 25 kg » & co', '14500', '2.5']);
    expect(rows[2].take(2), ['Huile <Niinal>', '6500']);
    expect(rows[3].take(3), ['ñaar ŋ', '0', '1']);
  });

  test('colonnes : A, Z, AA, AZ', () {
    expect([Xlsx.column(0), Xlsx.column(25), Xlsx.column(26), Xlsx.column(51)], ['A', 'Z', 'AA', 'AZ']);
  });

  test('CSV : séparateur détecté, guillemets, BOM, lignes vides', () {
    final csv = utf8.encode('\uFEFFNom;Prix;Note\r\n"Riz; parfumé";"1 500";"dit ""bon"""\r\n\r\nHuile;6500;\n');
    expect(Xlsx.readCsv(csv), [
      ['Nom', 'Prix', 'Note'],
      ['Riz; parfumé', '1 500', 'dit "bon"'],
      ['Huile', '6500', ''],
    ]);
    expect(Xlsx.readCsv(utf8.encode('a,b\n1,2')), [
      ['a', 'b'],
      ['1', '2'],
    ]);
  });

  test('format non pris en charge', () {
    expect(() => Xlsx.readTable(utf8.encode('x'), fileName: 'photo.jpg'), throwsFormatException);
    expect(() => Xlsx.readXlsx(utf8.encode('pas un zip')), throwsFormatException);
  });
}
