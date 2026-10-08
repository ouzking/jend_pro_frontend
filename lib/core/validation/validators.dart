/// Validateurs de formulaire alignés sur les contraintes du backend.
abstract final class Validators {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  /// `profiles.phone` / `businesses.phone` : `^\+?[0-9]{6,15}$` après nettoyage.
  static final _phone = RegExp(r'^\+?[0-9]{6,15}$');

  /// Longueur minimale imposée par Supabase Auth (config backend).
  static const minPasswordLength = 8;

  static String? required(String? value, {String message = 'Ce champ est obligatoire.'}) =>
      (value == null || value.trim().isEmpty) ? message : null;

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Saisissez votre adresse e-mail.';
    if (!_email.hasMatch(v)) return 'Adresse e-mail invalide.';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Saisissez un mot de passe.';
    if (v.length < minPasswordLength) return 'Au moins $minPasswordLength caractères.';
    return null;
  }

  static String? fullName(String? value) {
    final v = value?.trim() ?? '';
    if (v.length < 2) return 'Saisissez votre nom complet.';
    if (v.length > 120) return '120 caractères maximum.';
    return null;
  }

  static String? businessName(String? value) {
    final v = value?.trim() ?? '';
    if (v.length < 2) return 'Le nom doit contenir au moins 2 caractères.';
    if (v.length > 120) return '120 caractères maximum.';
    return null;
  }

  /// Téléphone facultatif.
  static String? optionalPhone(String? value) {
    final v = normalizePhone(value);
    if (v.isEmpty) return null;
    if (!_phone.hasMatch(v)) return 'Numéro invalide (ex. 77 123 45 67).';
    return null;
  }

  static String normalizePhone(String? value) => (value ?? '').replaceAll(RegExp(r'[\s.\-()]'), '');
}
