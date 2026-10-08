import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../business/application/workspace_controller.dart';
import '../../business/data/business_repository.dart';
import '../../business/domain/business_profile.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/catalog_models.dart';
import '../domain/business_templates.dart';
import 'setup_pending.dart';

/// Étapes de l'assistant, dans l'ordre.
enum SetupStep { type, info, logo, products, stock, done }

class SetupState {
  const SetupState({
    this.step = SetupStep.type,
    this.template,
    this.categories = const [],
    this.products = const [],
    this.initialStock = const {},
    this.profile,
  });

  final SetupStep step;
  final BusinessTemplate? template;
  final List<Category> categories;

  /// Produits créés pendant l'assistant (déjà enregistrés en base).
  final List<ProductSummary> products;

  /// Stock d'ouverture déjà enregistré, par produit.
  final Map<String, num> initialStock;
  final BusinessProfile? profile;

  List<ProductSummary> get stockedProducts => products.where((p) => p.trackStock).toList();

  SetupState copyWith({
    SetupStep? step,
    BusinessTemplate? template,
    List<Category>? categories,
    List<ProductSummary>? products,
    Map<String, num>? initialStock,
    BusinessProfile? profile,
  }) => SetupState(
    step: step ?? this.step,
    template: template ?? this.template,
    categories: categories ?? this.categories,
    products: products ?? this.products,
    initialStock: initialStock ?? this.initialStock,
    profile: profile ?? this.profile,
  );
}

final setupWizardProvider = NotifierProvider.autoDispose<SetupWizardController, SetupState>(SetupWizardController.new);

/// Orchestration de l'assistant. Chaque étape écrit **immédiatement** en base
/// via les repositories (pas de brouillon local) : quitter l'assistant ne
/// perd rien de ce qui a été validé.
class SetupWizardController extends Notifier<SetupState> {
  @override
  SetupState build() => const SetupState();

  String get _businessId => ref.read(activeBusinessProvider)!.businessId;

  void goTo(SetupStep step) => state = state.copyWith(step: step);

  void next() {
    var nextIndex = state.step.index + 1;
    // Pas de produit stocké : l'étape « stock initial » n'a pas d'objet.
    if (SetupStep.values[nextIndex] == SetupStep.stock && state.stockedProducts.isEmpty) nextIndex++;
    goTo(SetupStep.values[nextIndex]);
  }

  void back() {
    if (state.step.index == 0) return;
    var previous = state.step.index - 1;
    if (SetupStep.values[previous] == SetupStep.stock && state.stockedProducts.isEmpty) previous--;
    goTo(SetupStep.values[previous]);
  }

  /// Étape 1 : crée les catégories proposées retenues par l'utilisateur.
  Future<void> chooseTemplate(BusinessTemplate template, List<String> categoryNames) async {
    final categories = categoryNames.isEmpty
        ? const <Category>[]
        : await ref.read(productsRepositoryProvider).ensureCategories(_businessId, categoryNames);
    state = state.copyWith(template: template, categories: categories);
    next();
  }

  Future<BusinessProfile> loadProfile() async {
    final profile = state.profile ?? await ref.read(businessRepositoryProvider).fetchProfile(_businessId);
    state = state.copyWith(profile: profile);
    return profile;
  }

  /// Étape 2 : n'envoie que les champs réellement modifiés.
  Future<void> saveInfo(Map<String, String?> values) async {
    final current = await loadProfile();
    final before = <String, String?>{
      'legal_name': current.legalName,
      'ninea': current.ninea,
      'rccm': current.rccm,
      'email': current.email,
      'address': current.address,
    };
    final changes = <String, Object?>{
      for (final e in values.entries)
        if ((e.value?.trim().isEmpty ?? true ? null : e.value!.trim()) != before[e.key])
          e.key: (e.value?.trim().isEmpty ?? true) ? null : e.value!.trim(),
    };
    if (changes.isNotEmpty) {
      final updated = await ref.read(businessRepositoryProvider).updateProfile(_businessId, changes);
      state = state.copyWith(profile: updated);
    }
    next();
  }

  /// Étape 3 : logo (facultatif).
  Future<void> uploadLogo(Uint8List bytes, String mimeType) async {
    final updated = await ref.read(businessRepositoryProvider).uploadLogo(_businessId, bytes, mimeType: mimeType);
    state = state.copyWith(profile: updated);
    // Le logo apparaît partout (en-têtes, reçus) : on recharge le contexte.
    await ref.read(workspaceProvider.notifier).refreshContext();
  }

  String logoUrl(String path) => ref.read(businessRepositoryProvider).publicLogoUrl(path);

  /// Étape 4 : chaque produit est créé immédiatement.
  Future<ProductSummary> addProduct(NewProduct product) async {
    final created = await ref.read(productsRepositoryProvider).createProduct(_businessId, product);
    state = state.copyWith(products: [...state.products, created]);
    return created;
  }

  /// Étape 5 : stock d'ouverture à l'emplacement par défaut. Les produits déjà
  /// initialisés sont ignorés (`INITIAL` n'est autorisé qu'une fois).
  Future<void> saveInitialStock(Map<String, num> quantities) async {
    final pending = {
      for (final e in quantities.entries)
        if (e.value > 0 && !state.initialStock.containsKey(e.key)) e.key: e.value,
    };
    if (pending.isNotEmpty) {
      final locationId = await ref.read(businessRepositoryProvider).fetchDefaultLocationId(_businessId);
      final inventory = ref.read(inventoryRepositoryProvider);
      final saved = {...state.initialStock};
      // Séquentiel : un échec indique précisément le produit concerné, et ce
      // qui a déjà réussi est conservé.
      for (final e in pending.entries) {
        await inventory.setInitialStock(
          businessId: _businessId,
          productId: e.key,
          locationId: locationId,
          quantity: e.value,
        );
        saved[e.key] = e.value;
        state = state.copyWith(initialStock: saved);
      }
    }
    next();
  }

  Future<void> finish() => ref.read(setupPendingProvider.notifier).complete();
}
