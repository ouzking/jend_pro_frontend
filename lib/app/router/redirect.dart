import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_session.dart';
import '../../features/business/domain/workspace.dart';
import 'routes.dart';

/// Règles de navigation globales, sous forme de fonction pure (testée).
///
/// Ordre : connexion → récupération de mot de passe → chargement du contexte
/// → création / choix d'entreprise → assistant de configuration →
/// permissions de l'écran.
String? resolveRedirect({
  required String path,
  required AuthSession auth,
  required AsyncValue<Workspace?> workspace,
  bool setupPending = false,
}) {
  if (!auth.isSignedIn) {
    return Routes.isAuth(path) && path != Routes.resetPassword ? null : Routes.login;
  }

  if (auth.passwordRecovery) {
    return path == Routes.resetPassword ? null : Routes.resetPassword;
  }

  final ws = workspace.value;
  if (ws == null) {
    // Chargement ou erreur : l'écran d'accueil affiche la progression / l'erreur.
    return path == Routes.splash ? null : Routes.splash;
  }

  if (!ws.isReady) {
    final target = ws.hasBusiness ? Routes.selectBusiness : Routes.onboarding;
    return path == target ? null : target;
  }

  if (setupPending) return path == Routes.setup ? null : Routes.setup;

  if (Routes.isAuth(path) || Routes.isPreWorkspace(path)) return Routes.home;

  final required = Routes.requiredPermissions(path);
  if (required != null && !ws.permissions.canAny(required)) return Routes.home;

  return null;
}
