import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/core/storage/preferences.dart';
import 'package:jend_pro_mobile/core/voice/voice_listen_sheet.dart';
import 'package:jend_pro_mobile/core/voice/voice_recognizer.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/business/domain/workspace.dart';
import 'package:jend_pro_mobile/features/sales/application/pos_providers.dart';
import 'package:jend_pro_mobile/features/sales/application/voice_order.dart';
import 'package:jend_pro_mobile/features/sales/data/sales_repository.dart';
import 'package:jend_pro_mobile/features/sales/domain/sale_models.dart';
import 'package:jend_pro_mobile/features/sales/presentation/widgets/voice_order_sheet.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo extends Mock implements SalesRepository {}

/// Micro simulé : « entend » [said], ou échoue.
class _FakeVoice implements VoiceRecognizer {
  _FakeVoice(this.said, {this.failure, this.wolof = false});

  final String said;
  final VoiceFailure? failure;
  final bool wolof;
  String? usedLocale;

  @override
  Future<void> initialize() async {
    if (failure != null) throw failure!;
  }

  @override
  Future<String?> localeFor(VoiceLanguage language) async =>
      language == VoiceLanguage.wolof ? (wolof ? 'wo-SN' : null) : 'fr-SN';

  @override
  Future<void> listen({
    required String? localeId,
    required void Function(String text, bool isFinal) onText,
    required void Function(String message) onError,
    void Function(double level)? onLevel,
  }) async {
    usedLocale = localeId;
    scheduleMicrotask(() {
      onText(said.split(' ').first, false);
      onText(said, true);
    });
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}

const _business = BusinessMembership(businessId: 'b1', businessName: 'Boutique', roleCode: 'OWNER', roleName: 'P');

SellableProduct _p(String id, String name, int price, {bool fractional = false, num? stock = 50}) => SellableProduct(
  id: id,
  name: name,
  unit: 'u',
  salePrice: price,
  trackStock: true,
  allowsFractional: fractional,
  stockQuantity: stock,
);

final _catalog = [
  _p('riz', 'Riz parfumé 25 kg', 14500),
  _p('huile5', 'Huile Niinal 5 L', 6500),
  _p('huile1', 'Huile Niinal 1 L', 1400),
  _p('sucre', 'Sucre au kilo', 700, fractional: true),
  _p('savon', 'Savon Madar', 300, stock: 1),
];

void main() {
  late _Repo repo;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repo = _Repo();
    // Catalogue complet sans recherche ; rien pour une recherche ciblée
    // (sauf réponse dédiée dans un test).
    when(
      () => repo.fetchSellable(
        'b1',
        query: any(named: 'query'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((inv) async => (inv.namedArguments[#query] as String? ?? '').isEmpty ? _catalog : const []);
    when(() => repo.fetchSellable('b1')).thenAnswer((_) async => _catalog);
  });

  ProviderContainer container(VoiceRecognizer voice) {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        activeBusinessProvider.overrideWithValue(_business),
        salesRepositoryProvider.overrideWithValue(repo),
        voiceRecognizerProvider.overrideWithValue(voice),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('VoiceOrderResolver', () {
    test('français : articles et quantités, mesure pour départager', () async {
      final c = container(_FakeVoice(''));
      final lines = await c.read(voiceOrderResolverProvider).resolve('deux sacs de riz et une huile cinq litres');
      expect([for (final l in lines) (l.product?.id, l.quantity)], [('riz', 2), ('huile5', 1)]);
    });

    test('wolof mélangé, article introuvable, arrondi, poids', () async {
      final c = container(_FakeVoice(''));
      final lines = await c
          .read(voiceOrderResolverProvider)
          .resolve('ñaar savon ak ñett ciment ak deux kilos et demi de sucre ak deux et demi huile un litre');
      expect(
        [for (final l in lines) (l.product?.id, l.quantity, l.rounded)],
        [('savon', 2, false), (null, 3, false), ('sucre', 2.5, false), ('huile1', 3, true)],
      );
    });

    test('hors ligne : catalogue gardé par la caisse', () async {
      when(
        () => repo.fetchSellable('b1'),
      ).thenAnswer((_) async => throw const AppFailure(FailureKind.network, 'hors ligne', code: 'NETWORK'));
      await prefs.setString('pos_catalog:b1', jsonEncode([for (final p in _catalog) p.toJson()]));
      final c = container(_FakeVoice(''));
      final lines = await c.read(voiceOrderResolverProvider).resolve('trois savons');
      expect(lines.single.product?.id, 'savon');
      // Un seul appel (le catalogue, en échec) : pas de recherche ciblée hors ligne.
      verify(
        () => repo.fetchSellable(
          any(),
          query: any(named: 'query'),
          categoryId: any(named: 'categoryId'),
          ids: any(named: 'ids'),
          limit: any(named: 'limit'),
        ),
      ).called(1);
    });

    test('article absent des 200 premiers : recherche ciblée sur le serveur', () async {
      when(
        () => repo.fetchSellable('b1', query: 'ciment', limit: 30),
      ).thenAnswer((_) async => [_p('ciment', 'Ciment Sahel 50 kg', 4200)]);
      final c = container(_FakeVoice(''));
      final lines = await c.read(voiceOrderResolverProvider).resolve('deux ciments');
      expect((lines.single.product?.id, lines.single.quantity), ('ciment', 2));
    });
  });

  Future<void> pumpHost(
    WidgetTester t,
    VoiceRecognizer voice,
    ProviderContainer c,
    Widget Function(BuildContext) body,
  ) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: Builder(builder: body)),
        ),
      ),
    );
  }

  testWidgets('dictée d’une vente : vérification puis panier', (t) async {
    final voice = _FakeVoice('deux sacs de riz et une huile cinq litres et trois savons');
    final c = container(voice);
    String? search = 'non appelé';
    await pumpHost(
      t,
      voice,
      c,
      (context) => TextButton(onPressed: () async => search = await dictateSale(context), child: const Text('micro')),
    );
    await t.tap(find.text('micro'));
    await t.pumpAndSettle();

    expect(find.text('Vérifiez avant d’ajouter'), findsOneWidget);
    expect(find.text('Riz parfumé 25 kg'), findsOneWidget);
    expect(find.text('Huile Niinal 5 L'), findsOneWidget);
    expect(find.textContaining('Stock : 1'), findsOneWidget, reason: 'savon : 3 demandés, 1 en stock');
    expect(voice.usedLocale, 'fr-SN');

    // Une huile de plus, le savon retiré.
    await t.tap(find.byTooltip('Plus').at(1));
    await t.pump();
    final removeSavon = find.byTooltip('Moins').at(2);
    for (var i = 0; i < 3; i++) {
      await t.tap(removeSavon);
      await t.pump();
    }
    expect(find.text('Savon Madar'), findsNothing);

    await t.tap(find.text('Ajouter 2 articles au panier'));
    await t.pumpAndSettle();
    final cart = c.read(cartProvider);
    expect([for (final l in cart.lines) (l.product.id, l.quantity)], [('riz', 2), ('huile5', 2)]);
    expect(search, isNull);
    expect(find.text('2 articles ajoutés au panier.'), findsOneWidget);
  });

  testWidgets('article introuvable : « Chercher » renvoie le texte à la recherche', (t) async {
    final voice = _FakeVoice('trois ciments');
    final c = container(voice);
    String? search;
    await pumpHost(
      t,
      voice,
      c,
      (context) => TextButton(onPressed: () async => search = await dictateSale(context), child: const Text('micro')),
    );
    await t.tap(find.text('micro'));
    await t.pumpAndSettle();
    expect(find.text('Article introuvable dans le catalogue'), findsOneWidget);
    await t.tap(find.text('Chercher'));
    await t.pumpAndSettle();
    expect(search, 'ciments');
    expect(c.read(cartProvider).lines, isEmpty);
  });

  testWidgets('micro refusé : message clair et « Réessayer »', (t) async {
    final voice = _FakeVoice('', failure: const VoiceFailure('Autorisez le micro pour JËND PRO.'));
    final c = container(voice);
    await pumpHost(
      t,
      voice,
      c,
      (context) => TextButton(onPressed: () => dictateSale(context), child: const Text('micro')),
    );
    await t.tap(find.text('micro'));
    await t.pumpAndSettle();
    expect(find.text('Autorisez le micro pour JËND PRO.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('wolof proposé si le téléphone le reconnaît, choix mémorisé', (t) async {
    final voice = _FakeVoice('ñaar riz', wolof: true);
    final c = container(voice);
    await pumpHost(
      t,
      voice,
      c,
      (context) => TextButton(
        onPressed: () => listenToVoice(context, title: 'Test', example: 'x'),
        child: const Text('micro'),
      ),
    );
    c.read(voiceLanguageProvider.notifier).set(VoiceLanguage.wolof);
    await t.tap(find.text('micro'));
    await t.pumpAndSettle();
    expect(voice.usedLocale, 'wo-SN');
    expect(prefs.getString('voice_language'), 'wolof');
  });

  testWidgets('recherche vocale : le texte dicté remplit le champ', (t) async {
    final voice = _FakeVoice('Fatou Sow');
    final c = container(voice);
    final controller = TextEditingController();
    final changes = <String>[];
    await pumpHost(t, voice, c, (context) => SearchFieldActions(controller: controller, onChanged: changes.add));
    await t.tap(find.byTooltip('Recherche vocale'));
    await t.pumpAndSettle();
    expect(controller.text, 'Fatou Sow');
    expect(changes, ['Fatou Sow']);
    await t.tap(find.byTooltip('Effacer'));
    await t.pump();
    expect((controller.text, changes.last), ('', ''));
  });
}
