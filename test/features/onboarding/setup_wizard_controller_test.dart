import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/core/storage/preferences.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/business/data/business_repository.dart';
import 'package:jend_pro_mobile/features/business/domain/business_profile.dart';
import 'package:jend_pro_mobile/features/business/domain/workspace.dart';
import 'package:jend_pro_mobile/features/inventory/data/inventory_repository.dart';
import 'package:jend_pro_mobile/features/onboarding/application/setup_pending.dart';
import 'package:jend_pro_mobile/features/onboarding/application/setup_wizard_controller.dart';
import 'package:jend_pro_mobile/features/onboarding/domain/business_templates.dart';
import 'package:jend_pro_mobile/features/products/data/products_repository.dart';
import 'package:jend_pro_mobile/features/products/domain/catalog_models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Products extends Mock implements ProductsRepository {}

class _Inventory extends Mock implements InventoryRepository {}

class _Business extends Mock implements BusinessRepository {}

class _Ws extends WorkspaceController {
  @override
  Future<Workspace?> build() async => const Workspace(memberships: [_membership], invitations: [], active: _membership);
}

const _membership = BusinessMembership(
  businessId: 'b1',
  businessName: 'Keur Awa',
  roleCode: 'OWNER',
  roleName: 'Propriétaire',
);

ProductSummary _product(String id, {bool trackStock = true}) => ProductSummary(
  id: id,
  name: 'P$id',
  salePrice: 1000,
  unit: 'pièce',
  trackStock: trackStock,
  allowsFractionalQuantity: false,
);

void main() {
  late _Products products;
  late _Inventory inventory;
  late _Business business;
  late ProviderContainer container;

  setUpAll(() => registerFallbackValue(const NewProduct(name: 'x', salePrice: 0)));

  setUp(() async {
    SharedPreferences.setMockInitialValues({'setup_pending:b1': true});
    final prefs = await SharedPreferences.getInstance();
    products = _Products();
    inventory = _Inventory();
    business = _Business();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        workspaceProvider.overrideWith(_Ws.new),
        productsRepositoryProvider.overrideWithValue(products),
        inventoryRepositoryProvider.overrideWithValue(inventory),
        businessRepositoryProvider.overrideWithValue(business),
      ],
    );
    await container.read(workspaceProvider.future);
    container.listen(setupWizardProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  SetupWizardController wizard() => container.read(setupWizardProvider.notifier);

  test('le type crée uniquement les catégories retenues, puis avance', () async {
    when(
      () => products.ensureCategories('b1', ['Boissons']),
    ).thenAnswer((_) async => [const Category(id: 'c1', name: 'Boissons')]);
    final grocery = BusinessTemplate.all.first;

    await wizard().chooseTemplate(grocery, ['Boissons']);

    final state = container.read(setupWizardProvider);
    expect(state.template, grocery);
    expect(state.categories.single.id, 'c1');
    expect(state.step, SetupStep.info);
  });

  test('les informations n’envoient que les champs modifiés (vides → null)', () async {
    when(
      () => business.fetchProfile('b1'),
    ).thenAnswer((_) async => const BusinessProfile(id: 'b1', name: 'Keur Awa', ninea: '123'));
    when(
      () => business.updateProfile('b1', any()),
    ).thenAnswer((_) async => const BusinessProfile(id: 'b1', name: 'Keur Awa'));

    await wizard().saveInfo({'legal_name': ' Keur Awa SARL ', 'ninea': '123', 'rccm': '', 'email': '', 'address': ''});

    verify(() => business.updateProfile('b1', {'legal_name': 'Keur Awa SARL'})).called(1);
  });

  test('aucun produit stocké : l’étape stock est sautée', () async {
    when(() => products.createProduct('b1', any())).thenAnswer((_) async => _product('p1', trackStock: false));
    wizard().goTo(SetupStep.products);
    await wizard().addProduct(const NewProduct(name: 'Livraison', salePrice: 500, trackStock: false));

    wizard().next();
    expect(container.read(setupWizardProvider).step, SetupStep.done);
    wizard().back();
    expect(container.read(setupWizardProvider).step, SetupStep.products);
  });

  test('stock initial : quantités > 0 seulement, à l’emplacement par défaut', () async {
    when(() => products.createProduct('b1', any())).thenAnswer((_) async => _product('p1'));
    when(() => business.fetchDefaultLocationId('b1')).thenAnswer((_) async => 'loc1');
    when(
      () => inventory.setInitialStock(
        businessId: any(named: 'businessId'),
        productId: any(named: 'productId'),
        locationId: any(named: 'locationId'),
        quantity: any(named: 'quantity'),
      ),
    ).thenAnswer((_) async {});
    await wizard().addProduct(const NewProduct(name: 'Riz', salePrice: 500));

    await wizard().saveInitialStock({'p1': 12, 'p2': 0});

    verify(
      () => inventory.setInitialStock(businessId: 'b1', productId: 'p1', locationId: 'loc1', quantity: 12),
    ).called(1);
    verifyNoMoreInteractions(inventory);
    expect(container.read(setupWizardProvider).initialStock, {'p1': 12});
  });

  test('un échec de stock remonte et conserve ce qui a réussi', () async {
    when(() => business.fetchDefaultLocationId('b1')).thenAnswer((_) async => 'loc1');
    when(
      () => inventory.setInitialStock(businessId: 'b1', productId: 'p1', locationId: 'loc1', quantity: 3),
    ).thenAnswer((_) async {});
    when(() => inventory.setInitialStock(businessId: 'b1', productId: 'p2', locationId: 'loc1', quantity: 4)).thenThrow(
      const AppFailure(FailureKind.conflict, 'Le stock initial a déjà été saisi.', code: 'INITIAL_ALREADY_SET'),
    );

    await expectLater(wizard().saveInitialStock({'p1': 3, 'p2': 4}), throwsA(isA<AppFailure>()));
    expect(container.read(setupWizardProvider).initialStock, {'p1': 3});
  });

  test('terminer efface le marqueur local', () async {
    expect(container.read(setupPendingProvider), isTrue);
    await wizard().finish();
    expect(container.read(setupPendingProvider), isFalse);
    expect(container.read(sharedPreferencesProvider).getBool('setup_pending:b1'), isNull);
  });
}
