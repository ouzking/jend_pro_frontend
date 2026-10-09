// Aides communes aux tests d'intégration.
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';

/// Inscription d'un compte de test, robuste à la limite du Supabase local
/// (`[auth.rate_limit] sign_in_sign_ups = 30` par 5 min et par IP : deux
/// suites complètes enchaînées la dépassent). On patiente puis on réessaie ;
/// au-delà, l'échec indique clairement la cause. Les coupures et erreurs 5xx
/// passagères du serveur local sont aussi réessayées (et journalisées).
/// Renvoie `true` si le serveur exige une confirmation d'e-mail.
Future<bool> signUpForTest(
  AuthRepository auth, {
  required String fullName,
  required String email,
  required String password,
}) async {
  const waits = [Duration(seconds: 20), Duration(seconds: 40), Duration(seconds: 60)];
  for (var attempt = 0; ; attempt++) {
    try {
      return await auth.signUp(fullName: fullName, email: email, password: password);
    } on AppFailure catch (f) {
      final limited = f.code == 'over_request_rate_limit';
      // Coupure ou erreur 5xx passagère du Supabase local (conteneurs Docker).
      final transient = f.kind == FailureKind.network || (f.code?.startsWith('HTTP_5') ?? false);
      if (!limited && !transient) rethrow;
      // ignore: avoid_print
      print('signUpForTest : ${f.code} (${f.message}) — nouvel essai');
      if (attempt >= waits.length) {
        throw StateError(
          limited
              ? 'Limite d’inscriptions du Supabase local atteinte (30 / 5 min / IP). '
                    'Attendez quelques minutes puis relancez les tests d’intégration.'
              : 'Supabase local indisponible après plusieurs essais (${f.code}).',
        );
      }
      await Future<void>.delayed(waits[attempt]);
    }
  }
}
