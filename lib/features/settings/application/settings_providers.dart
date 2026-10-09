import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/preferences.dart';
import '../../auth/application/auth_session.dart';
import '../../business/application/workspace_controller.dart';
import '../../documents/application/document_providers.dart';
import '../../inventory/application/inventory_providers.dart';
import '../data/settings_repository.dart';
import '../domain/settings_models.dart';

final businessSettingsProvider = FutureProvider.autoDispose<BusinessSettings>((ref) {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  if (businessId == null) throw StateError('Aucun commerce actif');
  return ref.watch(settingsRepositoryProvider).fetchBusiness(businessId);
});

final locationDetailsProvider = FutureProvider.autoDispose<List<LocationDetail>>((ref) {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  if (businessId == null) return Future.value(const []);
  return ref.watch(settingsRepositoryProvider).fetchLocations(businessId);
});

final subscriptionPlansProvider = FutureProvider.autoDispose<List<SubscriptionPlan>>(
  (ref) => ref.watch(settingsRepositoryProvider).fetchPlans(),
);

final settingsActionsProvider = Provider<SettingsActions>(SettingsActions.new);

class SettingsActions {
  SettingsActions(this._ref);

  final Ref _ref;

  SettingsRepository get _repo => _ref.read(settingsRepositoryProvider);

  String get _businessId => _ref.read(activeBusinessProvider)!.businessId;

  /// Met à jour le commerce puis recharge le contexte (nom, fuseau affichés
  /// partout) et l'en-tête des documents.
  Future<BusinessSettings> updateBusiness(Map<String, Object?> changes) async {
    final s = await _repo.updateBusiness(_businessId, changes);
    _ref
      ..invalidate(businessSettingsProvider)
      ..invalidate(documentIssuerProvider);
    await _ref.read(workspaceProvider.notifier).refreshContext();
    return s;
  }

  void _locations() {
    _ref
      ..invalidate(locationDetailsProvider)
      ..invalidate(locationsProvider);
    // L'utilisation du plan (emplacements) change.
    _ref.read(workspaceProvider.notifier).refreshContext();
  }

  Future<void> createLocation({required String name, required LocationKind kind, String? address}) async {
    await _repo.createLocation(_businessId, name: name, kind: kind, address: address);
    _locations();
  }

  Future<void> updateLocation(String id, {required String name, required LocationKind kind, String? address}) async {
    await _repo.updateLocation(id, name: name, kind: kind, address: address);
    _locations();
  }

  Future<void> setLocationArchived(String id, {required bool archived}) async {
    await _repo.setLocationArchived(id, archived: archived);
    _locations();
  }

  Future<void> updateMyProfile({required String fullName, String? phone}) async {
    await _repo.updateMyProfile(fullName: fullName, phone: phone);
    _ref.invalidate(userProfileProvider);
  }
}

/// Apparence (réglage propre à l'appareil).
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    final stored = ref.read(sharedPreferencesProvider).getString(_key);
    return ThemeMode.values.firstWhere((m) => m.name == stored, orElse: () => ThemeMode.system);
  }

  void set(ThemeMode mode) {
    state = mode;
    ref.read(sharedPreferencesProvider).setString(_key, mode.name);
  }
}
