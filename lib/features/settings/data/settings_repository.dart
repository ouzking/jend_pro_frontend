import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/supabase/guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/settings_models.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(supabaseClientProvider)),
);

/// Paramètres du commerce, emplacements, formules et profil utilisateur.
/// Chaque mise à jour vérifie qu'une ligne a bien été modifiée : une RLS
/// refusée ne lève pas d'erreur, elle ne modifie rien.
class SettingsRepository {
  SettingsRepository(this._client);

  final SupabaseClient _client;

  static const businessColumns = {
    ...BusinessSettings.textColumns,
    'timezone',
    'allow_negative_stock',
    'large_sale_threshold',
  };

  static const _denied = AppFailure(
    FailureKind.permission,
    'Vous n’avez pas l’autorisation de modifier ces paramètres.',
    code: 'PERMISSION_DENIED',
  );

  Future<BusinessSettings> fetchBusiness(String businessId) => guardSupabase(() async {
    final row = await _client.from('businesses').select(BusinessSettings.columns).eq('id', businessId).single();
    return BusinessSettings.fromRow(row);
  });

  Future<BusinessSettings> updateBusiness(String businessId, Map<String, Object?> changes) => guardSupabase(() async {
    assert(changes.keys.every(businessColumns.contains));
    final rows = await _client.from('businesses').update(changes).eq('id', businessId).select(BusinessSettings.columns);
    if (rows.isEmpty) throw _denied;
    return BusinessSettings.fromRow(rows.first);
  });

  // ------------------------------------------------------------ Emplacements

  Future<List<LocationDetail>> fetchLocations(String businessId) => guardSupabase(() async {
    final rows = await _client
        .from('locations')
        .select(LocationDetail.columns)
        .eq('business_id', businessId)
        .order('is_default', ascending: false)
        .order('name', ascending: true);
    return rows.map(LocationDetail.fromRow).toList();
  });

  Future<LocationDetail> createLocation(
    String businessId, {
    required String name,
    required LocationKind kind,
    String? address,
  }) => guardSupabase(() async {
    final row = await _client
        .from('locations')
        .insert({
          'business_id': businessId,
          'name': name.trim(),
          'type': kind.code,
          'address': (address?.trim().isEmpty ?? true) ? null : address!.trim(),
        })
        .select(LocationDetail.columns)
        .single();
    return LocationDetail.fromRow(row);
  });

  Future<LocationDetail> updateLocation(
    String id, {
    required String name,
    required LocationKind kind,
    String? address,
  }) => _updateLocation(id, {
    'name': name.trim(),
    'type': kind.code,
    'address': (address?.trim().isEmpty ?? true) ? null : address!.trim(),
  });

  /// Archivage refusé par la base si l'emplacement contient du stock
  /// (`LOCATION_HAS_STOCK`) ou s'il est l'emplacement par défaut.
  Future<LocationDetail> setLocationArchived(String id, {required bool archived}) =>
      _updateLocation(id, {'status': archived ? 'ARCHIVED' : 'ACTIVE'});

  Future<LocationDetail> _updateLocation(String id, Map<String, Object?> changes) => guardSupabase(() async {
    final rows = await _client.from('locations').update(changes).eq('id', id).select(LocationDetail.columns);
    if (rows.isEmpty) throw _denied;
    return LocationDetail.fromRow(rows.first);
  });

  // ----------------------------------------------------------- Abonnement

  /// Formules publiques, dans l'ordre d'affichage.
  Future<List<SubscriptionPlan>> fetchPlans() => guardSupabase(() async {
    final rows = await _client
        .from('subscription_plans')
        .select(SubscriptionPlan.columns)
        .eq('is_public', true)
        .order('sort_order', ascending: true);
    return rows.map(SubscriptionPlan.fromRow).toList();
  });

  // ------------------------------------------------------------- Profil

  Future<void> updateMyProfile({required String fullName, String? phone}) => guardSupabase(() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AppFailure(FailureKind.auth, 'Votre session a expiré. Reconnectez-vous.');
    final rows = await _client
        .from('profiles')
        .update({'full_name': fullName.trim(), 'phone': (phone?.trim().isEmpty ?? true) ? null : phone!.trim()})
        .eq('id', userId)
        .select('id');
    if (rows.isEmpty) throw _denied;
  });
}
