import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/products/application/catalog_providers.dart';
import 'package:jend_pro_mobile/features/products/domain/catalog_models.dart';
import 'package:jend_pro_mobile/features/products/presentation/catalog_screen.dart';
import 'package:jend_pro_mobile/features/products/presentation/product_form_screen.dart';
import 'package:mocktail/mocktail.dart';

class _Actions extends Mock implements ProductActions {}

class _List extends ProductListController {
  _List(this.page);
  final ProductPage page;
  @override
  Future<ProductPage> build() async => page;
}

const _bissap = Product(
  id: 'p1',
  name: 'Bissap 1 L',
  unit: 'bouteille',
  salePrice: 1500,
  trackStock: true,
  allowsFractionalQuantity: false,
  minStockLevel: 10,
  archived: false,
  stockQuantity: 6,
  costPrice: 900,
  categoryName: 'Boissons',
);

const _owner = PermissionSet({
  Permission.productsRead,
  Permission.productsCreate,
  Permission.productsUpdate,
  Permission.productsReadCost,
  Permission.inventoryAdjust,
  Permission.categoriesManage,
});

Widget _app(Widget child, List overrides) => ProviderScope(
  overrides: [
    permissionsProvider.overrideWithValue(_owner),
    activeBusinessProvider.overrideWithValue(null),
    categoriesProvider.overrideWith((ref) async => const []),
    ...overrides.cast(),
  ],
  child: MaterialApp(theme: AppTheme.light(), home: child),
);

Future<void> _phone(WidgetTester t) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(() {
    registerFallbackValue(_bissap);
    registerFallbackValue(const NewProduct(name: 'x', salePrice: 0));
    registerFallbackValue(<String, Object?>{});
  });

  group('Product', () {
    test('niveaux de stock', () {
      expect(_bissap.stockLevel, StockLevel.low);
      Product with_({num? qty, bool track = true, num min = 10}) => Product(
        id: 'x',
        name: 'x',
        unit: 'pièce',
        salePrice: 1,
        trackStock: track,
        allowsFractionalQuantity: false,
        minStockLevel: min,
        archived: false,
        stockQuantity: qty,
      );
      expect(with_(qty: 0).stockLevel, StockLevel.out);
      expect(with_(qty: 50).stockLevel, StockLevel.ok);
      expect(with_(qty: 5, min: 0).stockLevel, StockLevel.ok, reason: 'seuil 0 = pas d’alerte');
      expect(with_().stockLevel, StockLevel.unknown);
      expect(with_(track: false).stockLevel, StockLevel.notTracked);
    });

    test('marge unitaire seulement si le coût est connu', () {
      expect(_bissap.unitMargin, 600);
    });
  });

  group('Catalogue', () {
    testWidgets('catalogue vide : invitation à ajouter un produit', (t) async {
      await _phone(t);
      await t.pumpWidget(
        _app(const CatalogScreen(), [
          productListProvider.overrideWith(() => _List(const ProductPage(items: [], hasMore: false))),
        ]),
      );
      await t.pumpAndSettle();
      expect(find.text('Votre catalogue est vide'), findsOneWidget);
      expect(find.text('Ajouter un produit'), findsOneWidget);
    });

    testWidgets('liste : nom, catégorie, prix et stock', (t) async {
      await _phone(t);
      await t.pumpWidget(
        _app(const CatalogScreen(), [
          productListProvider.overrideWith(() => _List(const ProductPage(items: [_bissap], hasMore: false))),
        ]),
      );
      await t.pumpAndSettle();
      expect(find.text('Bissap 1 L'), findsOneWidget);
      expect(find.text('Boissons · par bouteille'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'1.500 FCFA')), findsOneWidget);
      expect(find.text('1 produit'), findsOneWidget);
    });
  });

  group('Formulaire produit', () {
    testWidgets('création : nom et prix obligatoires', (t) async {
      await _phone(t);
      final actions = _Actions();
      await t.pumpWidget(_app(const ProductFormScreen(), [productActionsProvider.overrideWithValue(actions)]));
      await t.pumpAndSettle();

      final save = find.text('Ajouter au catalogue');
      await t.tap(save);
      await t.pumpAndSettle();
      expect(find.text('Donnez un nom au produit.'), findsOneWidget);
      expect(find.text('Indiquez un prix.'), findsOneWidget);
      verifyNever(
        () => actions.create(
          any(),
          initialStock: any(named: 'initialStock'),
          image: any(named: 'image'),
          imageMime: any(named: 'imageMime'),
        ),
      );
    });

    testWidgets('modification : seuls les champs changés sont envoyés', (t) async {
      await _phone(t);
      final actions = _Actions();
      when(() => actions.update(any(), any(), costPrice: any(named: 'costPrice'))).thenAnswer((_) async => _bissap);
      await t.pumpWidget(
        _app(const ProductFormScreen(productId: 'p1'), [
          productActionsProvider.overrideWithValue(actions),
          productDetailProvider('p1').overrideWith((ref) async => _bissap),
        ]),
      );
      await t.pumpAndSettle();

      // Le champ prix est le premier champ numérique après le nom.
      final priceField = find.widgetWithText(TextFormField, '1 500');
      expect(priceField, findsOneWidget);
      await t.enterText(priceField, '1750');
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();

      final captured = verify(
        () => actions.update(captureAny(), captureAny(), costPrice: captureAny(named: 'costPrice')),
      ).captured;
      expect(captured[1], {'sale_price': 1750});
      expect(captured[2], 900, reason: 'coût inchangé, renvoyé tel quel (ignoré par ProductActions)');
    });
  });
}
