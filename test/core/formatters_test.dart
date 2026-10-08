import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/formatting/formatters.dart';
import 'package:jend_pro_mobile/core/validation/validators.dart';

/// Les séparateurs de milliers `fr` sont des espaces insécables : on les
/// normalise pour comparer.
String _plain(String s) => s.replaceAll(RegExp(r'[  ]'), ' ');

void main() {
  group('Formatters', () {
    test('montants entiers en FCFA', () {
      expect(_plain(Formatters.money(1500)), '1 500 FCFA');
      expect(_plain(Formatters.money(0)), '0 FCFA');
      expect(_plain(Formatters.money(1250000, withSymbol: false)), '1 250 000');
    });

    test('quantités décimales (3 décimales max)', () {
      expect(Formatters.quantity(2.5), '2,5');
      expect(Formatters.quantity(3), '3');
      expect(Formatters.quantity(1.2346), '1,235');
    });

    test('jour ISO pour les RPC', () {
      expect(Formatters.isoDay(DateTime(2026, 10, 8, 23, 59)), '2026-10-08');
    });

    test('initiales', () {
      expect(Formatters.initials('Awa Ndiaye'), 'AN');
      expect(Formatters.initials('Moussa'), 'MO');
      expect(Formatters.initials(''), '?');
      expect(Formatters.initials('  Fatou   Bintou  Sow '), 'FS');
    });

    test('monogramme article (maquette)', () {
      expect(Formatters.productMonogram('Riz brisé 25 kg'), 'RZ');
      expect(Formatters.productMonogram('Huile 5 L'), 'HL');
      expect(Formatters.productMonogram('Sucre 1 kg'), 'SC');
      expect(Formatters.productMonogram('Eau'), 'EA');
    });

    test('temps relatif', () {
      final now = DateTime(2026, 10, 8, 12);
      expect(Formatters.relative(now.subtract(const Duration(seconds: 10)), now: now), 'à l’instant');
      expect(Formatters.relative(now.subtract(const Duration(minutes: 5)), now: now), 'il y a 5 min');
      expect(Formatters.relative(now.subtract(const Duration(hours: 3)), now: now), 'il y a 3 h');
      expect(Formatters.relative(DateTime(2026, 10, 7, 18), now: now), 'hier');
    });
  });

  group('Validators', () {
    test('e-mail', () {
      expect(Validators.email('awa@exemple.sn'), isNull);
      expect(Validators.email('awa@'), isNotNull);
      expect(Validators.email(''), isNotNull);
    });

    test('mot de passe : 8 caractères minimum (config Supabase)', () {
      expect(Validators.password('1234567'), isNotNull);
      expect(Validators.password('12345678'), isNull);
    });

    test('téléphone facultatif, normalisé comme en base', () {
      expect(Validators.optionalPhone(''), isNull);
      expect(Validators.optionalPhone('77 123 45 67'), isNull);
      expect(Validators.optionalPhone('+221 77-123-45-67'), isNull);
      expect(Validators.optionalPhone('12'), isNotNull);
      expect(Validators.normalizePhone('77.123.45.67'), '771234567');
    });
  });
}
