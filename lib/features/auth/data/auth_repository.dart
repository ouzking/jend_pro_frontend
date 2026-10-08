import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/user_profile.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(supabaseClientProvider)));

/// Seul point d'accès à Supabase Auth et à la table `profiles`.
/// Toute exception est convertie en [AppFailure].
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  Stream<AuthState> authStateChanges() => _auth.onAuthStateChange;

  User? get currentUser => _auth.currentUser;

  Future<void> signIn({required String email, required String password}) =>
      _guard(() => _auth.signInWithPassword(email: email.trim(), password: password));

  /// Renvoie `true` si une confirmation par e-mail est nécessaire avant la
  /// première connexion (selon la configuration du projet Supabase).
  Future<bool> signUp({required String fullName, required String email, required String password}) => _guard(() async {
    final response = await _auth.signUp(
      email: email.trim(),
      password: password,
      // Copié dans `profiles.full_name` par le trigger backend.
      data: {'full_name': fullName.trim()},
      emailRedirectTo: Env.authRedirectUrl,
    );
    return response.session == null;
  });

  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.resetPasswordForEmail(email.trim(), redirectTo: Env.authRedirectUrl));

  /// Définit un nouveau mot de passe (session de récupération ou connectée).
  Future<void> updatePassword(String newPassword) =>
      _guard(() => _auth.updateUser(UserAttributes(password: newPassword)));

  /// Changement depuis les paramètres : le mot de passe actuel est revérifié
  /// avant toute modification.
  Future<void> changePassword({required String currentPassword, required String newPassword}) => _guard(() async {
    final email = currentUser?.email;
    if (email == null) throw const AppFailure(FailureKind.auth, 'Votre session a expiré. Reconnectez-vous.');
    try {
      await _auth.signInWithPassword(email: email, password: currentPassword);
    } on AuthException catch (e) {
      if (e.code == 'invalid_credentials') {
        throw const AppFailure(FailureKind.validation, 'Le mot de passe actuel est incorrect.', code: 'WRONG_PASSWORD');
      }
      rethrow;
    }
    await _auth.updateUser(UserAttributes(password: newPassword));
  });

  Future<void> signOut() => _guard(() => _auth.signOut());

  /// Profil de l'utilisateur connecté (la RLS ne renvoie que le sien).
  Future<UserProfile?> fetchProfile() => _guard(() async {
    final user = currentUser;
    if (user == null) return null;
    final row = await _client.from('profiles').select('id, full_name, phone, locale').eq('id', user.id).maybeSingle();
    return UserProfile(
      id: user.id,
      email: user.email ?? '',
      fullName: (row?['full_name'] as String?) ?? (user.userMetadata?['full_name'] as String?),
      phone: row?['phone'] as String?,
      locale: (row?['locale'] as String?) ?? 'fr',
    );
  });

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}
