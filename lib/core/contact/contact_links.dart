import 'package:url_launcher/url_launcher.dart';

/// Liens de contact (appel, WhatsApp) à partir d'un numéro saisi librement.
abstract final class ContactLinks {
  /// Indicatif par défaut (numéros locaux à 9 chiffres : Sénégal).
  static const defaultCountryCode = '221';

  /// Numéro international sans « + » : `77 123 45 67` → `221771234567`.
  static String? international(String? phone, {String countryCode = defaultCountryCode}) {
    if (phone == null) return null;
    final trimmed = phone.trim();
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (trimmed.startsWith('+') || trimmed.startsWith('00')) return digits.replaceFirst(RegExp(r'^00'), '');
    if (digits.length == 9) return '$countryCode$digits';
    return digits;
  }

  static Future<bool> call(String phone) => launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(' ', '')));

  /// Ouvre WhatsApp avec un message pré-rempli (l'utilisateur relit et envoie).
  static Future<bool> whatsApp(String phone, {String? message}) {
    final number = international(phone);
    if (number == null) return Future.value(false);
    final uri = Uri.https('wa.me', '/$number', {'text': ?message});
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
