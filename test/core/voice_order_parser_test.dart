import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/voice/voice_order_parser.dart';

List<(num, String)> parse(String s) => [for (final i in VoiceOrderParser.parse(s)) (i.quantity, i.query)];

const _catalog = [
  VoiceCandidate(id: 'riz', name: 'Riz parfumé 25 kg'),
  VoiceCandidate(id: 'riz5', name: 'Riz brisé 5 kg'),
  VoiceCandidate(id: 'huile5', name: 'Huile Niinal 5 L'),
  VoiceCandidate(id: 'huile1', name: 'Huile Niinal 1 L'),
  VoiceCandidate(id: 'sucre', name: 'Sucre en morceaux'),
  VoiceCandidate(id: 'savon', name: 'Savon Madar'),
  VoiceCandidate(id: 'lait', name: 'Lait en poudre Vitalait 400 g'),
  VoiceCandidate(id: 'oignon', name: 'Oignons'),
  VoiceCandidate(id: 'cafe', name: 'Café Touba'),
  VoiceCandidate(id: 'pain', name: 'Pain'),
];

String? best(String said) => VoiceOrderParser.match(VoiceOrderParser.parse(said).single, _catalog).best?.id;

void main() {
  group('nombres', () {
    num? n(String s) => VoiceOrderParser.readNumber(VoiceOrderParser.normalize(s).split(' '), 0)?.$1;

    test('français', () {
      expect(n('un'), 1);
      expect(n('une'), 1);
      expect(n('dix sept'), 17);
      expect(n('dix-huit'), 18);
      expect(n('vingt et un'), 21);
      expect(n('vingt-deux'), 22);
      expect(n('soixante-dix'), 70);
      expect(n('soixante quinze'), 75);
      expect(n('quatre-vingts'), 80);
      expect(n('quatre vingt dix neuf'), 99);
      expect(n('deux cent cinquante'), 250);
      expect(n('cent'), 100);
      expect(n('trois deux'), 3, reason: 'deux nombres distincts ne fusionnent pas');
    });

    test('chiffres, décimales, demi, douzaine', () {
      expect(n('12'), 12);
      expect(n('2,5'), 2.5);
      expect(n('1.5'), 1.5);
      expect(n('deux et demi'), 2.5);
      expect(n('un demi'), 0.5);
      expect(n('demi'), 0.5);
      expect(n('une douzaine'), 12);
      expect(n('deux douzaines'), 24);
      expect(n('une dizaine'), 10);
    });

    test('wolof (orthographe officielle et transcriptions approchées)', () {
      expect(n('benn'), 1);
      expect(n('ñaar'), 2);
      expect(n('niaar'), 2);
      expect(n('gnaar'), 2);
      expect(n('ñett'), 3);
      expect(n('niet'), 3);
      expect(n('ñeent'), 4);
      expect(n('juróom'), 5);
      expect(n('diouroum'), 5);
      expect(n('juróom benn'), 6);
      expect(n('juróom ñaar'), 7);
      expect(n('fukk'), 10);
      expect(n('fukk ak benn'), 11);
      expect(n('ñaar fukk'), 20);
      expect(n('ñaar fukk ak juróom'), 25);
      expect(n('benn téeméer'), 100);
    });
  });

  group('découpage en lignes', () {
    test('français courant', () {
      expect(parse('deux sacs de riz et une huile'), [(2, 'riz'), (1, 'huile')]);
      expect(parse('3 savons, 2 sucres'), [(3, 'savons'), (2, 'sucres')]);
      expect(parse('mets-moi un riz deux huiles trois savons'), [(1, 'riz'), (2, 'huiles'), (3, 'savons')]);
    });

    test('mesure dans le nom de l’article (« huile 5 litres »)', () {
      expect(parse('une huile 5 litres et un riz 25 kg'), [(1, 'huile 5 litres'), (1, 'riz 25 kg')]);
      expect(parse('deux huiles cinq litres'), [(2, 'huiles 5 litres')]);
    });

    test('quantité au poids et demi', () {
      expect(parse('deux kilos et demi de sucre'), [(2.5, 'kilos sucre')]);
      expect(parse('un kilo et demi d’oignons'), [(1.5, 'kilo oignons')]);
      expect(parse('2,5 kg de sucre'), [(2.5, 'kg sucre')]);
    });

    test('quantité après l’article', () {
      expect(parse('riz deux sacs, huile une'), [(2, 'riz'), (1, 'huile')]);
      expect(parse('sucre 3 savon 2'), [(3, 'sucre'), (2, 'savon')]);
    });

    test('sans quantité : 1 par défaut', () {
      final items = VoiceOrderParser.parse('du pain et du café');
      expect(
        [for (final i in items) (i.quantity, i.query, i.explicitQuantity)],
        [(1, 'pain', false), (1, 'cafe', false)],
      );
    });

    test('wolof et mélange français / wolof', () {
      expect(parse('ñaar riz ak benn huile'), [(2, 'riz'), (1, 'huile')]);
      expect(parse('niaar sac riz ak niet savon'), [(2, 'riz'), (3, 'savon')]);
      expect(parse('jox ma juróom pain ak ñaar sucre'), [(5, 'pain'), (2, 'sucre')]);
      expect(parse('fukk ak benn savon'), [(11, 'savon')]);
      expect(parse('deux riz ak benn café touba'), [(2, 'riz'), (1, 'cafe touba')]);
    });

    test('phrase vide ou sans article', () {
      expect(parse(''), isEmpty);
      expect(parse('euh merci'), isEmpty);
      expect(parse('bon alors euh deux riz'), [(2, 'riz')]);
      expect(parse('deux trois'), isEmpty, reason: 'des nombres sans article ne donnent rien');
    });
  });

  group('rapprochement avec le catalogue', () {
    test('mot simple, pluriel, accents', () {
      expect(best('deux savons'), 'savon');
      expect(best('trois oignon'), 'oignon');
      expect(best('un cafe'), 'cafe');
      expect(best('du sucre'), 'sucre');
    });

    test('la mesure départage les variantes', () {
      expect(best('une huile cinq litres'), 'huile5');
      expect(best('une huile un litre'), 'huile1');
      expect(best('un riz 25 kg'), 'riz');
      expect(best('un riz brisé'), 'riz5');
    });

    test('erreurs de reconnaissance proches', () {
      expect(best('deux savont madar'), 'savon');
      expect(best('un lait vitalé'), 'lait');
    });

    test('rien de proche : pas de proposition', () {
      expect(best('trois ciments'), isNull);
    });

    test('ambiguïté signalée', () {
      final m = VoiceOrderParser.match(VoiceOrderParser.parse('une huile niinal').single, _catalog);
      expect(m.best?.id, startsWith('huile'));
      expect(m.ambiguous, isTrue);
    });
  });
}
