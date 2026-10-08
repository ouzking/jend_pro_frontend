import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/business_profile.dart';
import '../domain/workspace.dart';

final businessRepositoryProvider = Provider<BusinessRepository>(
  (ref) => BusinessRepository(ref.watch(supabaseClientProvider)),
);

/// Entreprises, adhésions, invitations, permissions et abonnement.
class BusinessRepository {
  BusinessRepository(this._client);

  final SupabaseClient _client;

  /// Adhésions ACTIVES de l'utilisateur (RLS : « users can select their own memberships »).
  Future<List<BusinessMembership>> fetchMemberships(String userId) => _guard(() async {
    final rows = await _client
        .from('business_members')
        .select('role:roles(code, name), business:businesses(id, name, city, logo_path, currency_code, timezone)')
        .eq('user_id', userId)
        .eq('status', 'ACTIVE');
    final memberships =
        rows.where((r) => r['business'] != null && r['role'] != null).map(BusinessMembership.fromRow).toList()
          ..sort((a, b) => a.businessName.toLowerCase().compareTo(b.businessName.toLowerCase()));
    return memberships;
  });

  Future<List<PendingInvitation>> fetchInvitations() => _guard(() async {
    final rows = await _client.rpc<List<dynamic>>('list_my_invitations');
    return rows.cast<Map<String, dynamic>>().map(PendingInvitation.fromRow).toList();
  });

  /// Ensemble effectif (déjà filtré par le mode restreint côté serveur).
  Future<Set<String>> fetchPermissions(String businessId) => _guard(() async {
    final codes = await _client.rpc<List<dynamic>>('get_my_permissions', params: {'p_business_id': businessId});
    return codes.cast<String>().toSet();
  });

  Future<SubscriptionStatus?> fetchSubscription(String businessId) => _guard(() async {
    final rows = await _client.rpc<List<dynamic>>('get_subscription_status', params: {'p_business_id': businessId});
    if (rows.isEmpty) return null;
    return SubscriptionStatus.fromRow(rows.first as Map<String, dynamic>);
  });

  /// Crée l'entreprise, l'emplacement par défaut et le membre OWNER (atomique).
  Future<String> createBusiness({required String name, String? phone, String? city, String? address}) =>
      _guard(() async {
        String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
        return _client.rpc<String>(
          'create_business',
          params: {'p_name': name.trim(), 'p_phone': clean(phone), 'p_city': clean(city), 'p_address': clean(address)},
        );
      });

  Future<void> acceptInvitation(String businessId) =>
      _guard(() => _client.rpc<void>('accept_invitation', params: {'p_business_id': businessId}));

  Future<void> declineInvitation(String businessId) =>
      _guard(() => _client.rpc<void>('decline_invitation', params: {'p_business_id': businessId}));

  Future<BusinessProfile> fetchProfile(String businessId) => _guard(() async {
    final row = await _client.from('businesses').select(BusinessProfile.columns).eq('id', businessId).single();
    return BusinessProfile.fromRow(row);
  });

  /// Met à jour les informations (`settings.manage`, audité côté serveur).
  /// `.select()` vérifie qu'une ligne a bien été modifiée (une RLS refusée
  /// ne lève pas d'erreur : elle modifie 0 ligne).
  Future<BusinessProfile> updateProfile(String businessId, Map<String, Object?> changes) => _guard(() async {
    final rows = await _client.from('businesses').update(changes).eq('id', businessId).select(BusinessProfile.columns);
    if (rows.isEmpty) {
      throw const AppFailure(FailureKind.permission, 'Vous n’avez pas l’autorisation de modifier ce commerce.');
    }
    return BusinessProfile.fromRow(rows.first);
  });

  /// Envoie le logo dans `business-assets/{business_id}/logo-{uuid}.{ext}`
  /// puis l'associe à l'entreprise. JPEG, PNG ou WebP, 1 Mo maximum.
  Future<BusinessProfile> uploadLogo(String businessId, Uint8List bytes, {required String mimeType}) =>
      _guard(() async {
        final ext = switch (mimeType) {
          'image/png' => 'png',
          'image/webp' => 'webp',
          _ => 'jpg',
        };
        final path = '$businessId/logo-${DateTime.now().microsecondsSinceEpoch}.$ext';
        await _client.storage
            .from('business-assets')
            .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mimeType, upsert: false));
        return updateProfile(businessId, {'logo_path': path});
      });

  String publicLogoUrl(String path) => _client.storage.from('business-assets').getPublicUrl(path);

  /// Emplacement par défaut (« Boutique principale »), créé avec l'entreprise.
  Future<String> fetchDefaultLocationId(String businessId) => _guard(() async {
    final row = await _client
        .from('locations')
        .select('id')
        .eq('business_id', businessId)
        .eq('is_default', true)
        .single();
    return row['id'] as String;
  });

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}
