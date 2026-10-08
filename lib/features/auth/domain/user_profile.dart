/// Profil applicatif (`profiles`) enrichi de l'e-mail du compte Auth.
class UserProfile {
  const UserProfile({required this.id, required this.email, this.fullName, this.phone, this.locale = 'fr'});

  final String id;
  final String email;
  final String? fullName;
  final String? phone;
  final String locale;

  /// Nom affichable, jamais vide.
  String get displayName => (fullName?.trim().isNotEmpty ?? false) ? fullName!.trim() : email.split('@').first;

  String get firstName => displayName.split(' ').first;
}
