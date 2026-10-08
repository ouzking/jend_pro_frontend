import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';
import '../domain/user_profile.dart';

/// État d'authentification minimal utilisé par le routeur.
///
/// L'égalité ne porte que sur l'identifiant : un simple rafraîchissement de
/// jeton ne reconstruit ni le routeur ni les données dépendantes.
class AuthSession {
  const AuthSession({this.userId, this.email, this.passwordRecovery = false});

  final String? userId;
  final String? email;

  /// Session ouverte par un lien « mot de passe oublié » : l'utilisateur doit
  /// d'abord choisir un nouveau mot de passe.
  final bool passwordRecovery;

  bool get isSignedIn => userId != null;

  @override
  bool operator ==(Object other) =>
      other is AuthSession && other.userId == userId && other.passwordRecovery == passwordRecovery;

  @override
  int get hashCode => Object.hash(userId, passwordRecovery);
}

final authSessionProvider = NotifierProvider<AuthSessionNotifier, AuthSession>(AuthSessionNotifier.new);

class AuthSessionNotifier extends Notifier<AuthSession> {
  @override
  AuthSession build() {
    final repository = ref.watch(authRepositoryProvider);
    final subscription = repository.authStateChanges().listen(
      _onAuthState,
      // Lien de récupération expiré ou invalide : on reste sur l'état courant.
      onError: (Object _) {},
    );
    ref.onDispose(subscription.cancel);
    final user = repository.currentUser;
    return AuthSession(userId: user?.id, email: user?.email);
  }

  void _onAuthState(AuthState event) {
    final user = event.session?.user;
    if (user == null) {
      state = const AuthSession();
      return;
    }
    state = AuthSession(
      userId: user.id,
      email: user.email,
      passwordRecovery:
          event.event == AuthChangeEvent.passwordRecovery || (state.passwordRecovery && state.userId == user.id),
    );
  }

  /// À appeler une fois le nouveau mot de passe enregistré.
  void completePasswordRecovery() {
    state = AuthSession(userId: state.userId, email: state.email);
  }

  @override
  bool updateShouldNotify(AuthSession previous, AuthSession next) => previous != next;
}

/// Profil de l'utilisateur connecté, rechargé à chaque changement de compte.
final userProfileProvider = FutureProvider<UserProfile?>((ref) {
  final userId = ref.watch(authSessionProvider.select((s) => s.userId));
  if (userId == null) return Future.value(null);
  return ref.watch(authRepositoryProvider).fetchProfile();
});
