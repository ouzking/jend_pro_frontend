import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/formatting/input_formatters.dart';

String _plain(String s) => s.replaceAll(RegExp(r'[  ]'), ' ');

TextEditingValue _type(TextInputFormatter f, String old, String next) =>
    f.formatEditUpdate(TextEditingValue(text: old), TextEditingValue(text: next));

void main() {
  group('AmountInputFormatter', () {
    final f = AmountInputFormatter();

    test('groupe les milliers pendant la saisie', () {
      expect(_plain(_type(f, '15 000', '150000').text), '150 000');
    });

    test('ignore les caractères non numériques et les zéros de tête', () {
      expect(_type(f, '', '00a12').text, '12');
      expect(_type(f, '1', '').text, '');
    });

    test('refuse les montants absurdes', () {
      expect(_type(f, '1', '1234567890123').text, '1');
    });

    test('parse renvoie un entier (jamais de double)', () {
      expect(AmountInputFormatter.parse('1 500'), 1500);
      expect(AmountInputFormatter.parse(''), isNull);
    });
  });

  group('QuantityInputFormatter', () {
    test('entiers seulement par défaut', () {
      final f = QuantityInputFormatter(allowDecimals: false);
      expect(_type(f, '2', '2,5').text, '2');
      expect(_type(f, '2', '25').text, '25');
    });

    test('3 décimales maximum pour la vente au détail', () {
      final f = QuantityInputFormatter(allowDecimals: true);
      expect(_type(f, '2', '2,5').text, '2,5');
      expect(_type(f, '2,125', '2,1255').text, '2,125');
      expect(QuantityInputFormatter.parse('2,5'), 2.5);
    });
  });
}
