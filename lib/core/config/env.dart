/// Configuration injectée à la compilation via `--dart-define-from-file`.
///
/// Seules des valeurs **publiques** transitent ici : l'URL du projet et la clé
/// *publishable* Supabase. Jamais de clé `service_role` / secrète dans l'app.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Lien profond utilisé par les e-mails Supabase (récupération de mot de
  /// passe, invitations). Doit figurer dans les « Redirect URLs » du projet.
  static const authRedirectUrl = String.fromEnvironment(
    'AUTH_REDIRECT_URL',
    defaultValue: 'io.jendpro.app://auth-callback',
  );

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
