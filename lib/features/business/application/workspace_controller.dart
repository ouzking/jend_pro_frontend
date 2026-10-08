import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/async/parallel.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/storage/preferences.dart';
import '../../auth/application/auth_session.dart';
import '../data/business_repository.dart';
import '../domain/workspace.dart';

/// Contexte de travail : entreprises de l'utilisateur, entreprise active,
/// permissions effectives et abonnement. `null` hors connexion.
final workspaceProvider = AsyncNotifierProvider<WorkspaceController, Workspace?>(WorkspaceController.new);

/// Permissions de l'entreprise active (vide tant qu'aucune n'est choisie).
final permissionsProvider = Provider<PermissionSet>(
  (ref) => ref.watch(workspaceProvider.select((w) => w.value?.permissions ?? const PermissionSet.empty())),
);

/// Entreprise active ; à n'utiliser que sous le shell (garanti non nul).
final activeBusinessProvider = Provider<BusinessMembership?>(
  (ref) => ref.watch(workspaceProvider.select((w) => w.value?.active)),
);

/// Clé locale « assistant de configuration à terminer » d'un commerce.
String setupPendingKey(String businessId) => 'setup_pending:$businessId';

class WorkspaceController extends AsyncNotifier<Workspace?> {
  static const _activeKeyPrefix = 'active_business_id:';

  BusinessRepository get _repository => ref.read(businessRepositoryProvider);

  @override
  Future<Workspace?> build() async {
    final userId = ref.watch(authSessionProvider.select((s) => s.userId));
    if (userId == null) return null;
    return _load(userId);
  }

  Future<Workspace> _load(String userId, {String? preferBusinessId}) async {
    final (memberships, invitations) = await parallel2(
      _repository.fetchMemberships(userId),
      _repository.fetchInvitations(),
    );

    final storedId = preferBusinessId ?? _prefs.getString('$_activeKeyPrefix$userId');
    BusinessMembership? active;
    for (final m in memberships) {
      if (m.businessId == storedId) active = m;
    }
    if (active == null && memberships.length == 1) active = memberships.single;

    if (active == null) {
      return Workspace(memberships: memberships, invitations: invitations);
    }
    await _prefs.setString('$_activeKeyPrefix$userId', active.businessId);
    return _withContext(Workspace(memberships: memberships, invitations: invitations, active: active));
  }

  /// Charge permissions et abonnement de l'entreprise active. Un échec de
  /// l'abonnement ne bloque pas l'entrée dans l'app (la base reste juge).
  Future<Workspace> _withContext(Workspace base) async {
    final businessId = base.active!.businessId;
    final (permissions, subscription) = await parallel2(
      _repository.fetchPermissions(businessId),
      _repository.fetchSubscription(businessId).then<SubscriptionStatus?>((s) => s, onError: (Object _) => null),
    );
    return Workspace(
      memberships: base.memberships,
      invitations: base.invitations,
      active: base.active,
      permissions: PermissionSet(permissions),
      subscription: subscription,
    );
  }

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  String? get _userId => ref.read(authSessionProvider).userId;

  Future<void> selectBusiness(String businessId) async {
    final userId = _userId;
    if (userId == null) return;
    // L'écran appelant affiche sa propre progression ; en cas d'échec,
    // l'`AppFailure` remonte et l'entreprise courante reste active.
    final next = await _load(userId, preferBusinessId: businessId);
    if (ref.mounted) state = AsyncData(next);
  }

  /// Crée l'entreprise puis l'active. Lève une `AppFailure` en cas d'échec
  /// (l'écran garde la main pour afficher l'erreur).
  Future<void> createBusiness({required String name, String? phone, String? city, String? address}) async {
    final userId = _userId;
    if (userId == null) return;
    final id = await _repository.createBusiness(name: name, phone: phone, city: city, address: address);
    // L'assistant de configuration doit s'ouvrir dès l'activation du commerce.
    await _prefs.setBool(setupPendingKey(id), true);
    state = AsyncData(await _load(userId, preferBusinessId: id));
  }

  Future<void> acceptInvitation(String businessId) async {
    final userId = _userId;
    if (userId == null) return;
    await _repository.acceptInvitation(businessId);
    state = AsyncData(await _load(userId, preferBusinessId: businessId));
  }

  Future<void> declineInvitation(String businessId) async {
    final userId = _userId;
    if (userId == null) return;
    await _repository.declineInvitation(businessId);
    state = AsyncData(await _load(userId));
  }

  /// Au retour au premier plan : un rôle a pu changer, un membre être
  /// suspendu, l'abonnement expirer. Silencieux en cas d'échec réseau.
  Future<void> refreshContext() async {
    final current = state.value;
    final userId = _userId;
    if (current == null || userId == null) return;
    try {
      final next = await _load(userId, preferBusinessId: current.active?.businessId);
      if (ref.mounted) state = AsyncData(next);
    } catch (_) {
      // On conserve l'état courant ; la prochaine action serveur tranchera.
    }
  }

  Future<void> retry() async {
    final userId = _userId;
    if (userId == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(userId));
  }
}
