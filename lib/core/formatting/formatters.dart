import 'package:intl/intl.dart';

/// Formatage centralisé. Les montants sont des **entiers** en unités de la
/// devise (XOF : francs, 0 décimale) — jamais de `double` pour de l'argent.
abstract final class Formatters {
  static final _integer = NumberFormat('#,##0', 'fr');
  static final _compact = NumberFormat.compact(locale: 'fr');
  static final _quantity = NumberFormat('#,##0.###', 'fr');
  static final _percent = NumberFormat('+#,##0.0;-#,##0.0', 'fr');

  /// `1500` → `1 500 FCFA`.
  static String money(int amount, {String currency = 'XOF', bool withSymbol = true}) {
    final value = _integer.format(amount);
    return withSymbol ? '$value ${currencySymbol(currency)}' : value;
  }

  /// `1250000` → `1,3 M FCFA` (tuiles du tableau de bord).
  static String moneyCompact(int amount, {String currency = 'XOF'}) {
    if (amount.abs() < 100000) return money(amount, currency: currency);
    return '${_compact.format(amount)} ${currencySymbol(currency)}';
  }

  static String currencySymbol(String currency) => switch (currency) {
    'XOF' || 'XAF' => 'FCFA',
    _ => currency,
  };

  /// Variation signée : `0.124` → `+12,4 %`.
  static String percentDelta(double ratio) => '${_percent.format(ratio * 100)} %';

  /// Quantités `numeric(14,3)` : `2.5` → `2,5`, `3` → `3`.
  static String quantity(num value) => _quantity.format(value);

  static String date(DateTime value) => DateFormat('d MMM y', 'fr').format(value.toLocal());

  static String dateTime(DateTime value) => DateFormat("d MMM y 'à' HH:mm", 'fr').format(value.toLocal());

  static String monthYear(DateTime value) => DateFormat('MMMM y', 'fr').format(value);

  static String time(DateTime value) => DateFormat('HH:mm', 'fr').format(value.toLocal());

  /// Date au format attendu par les RPC (`YYYY-MM-DD`, jour local).
  static String isoDay(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

  /// « il y a 5 min », « hier », « 3 oct. »
  static String relative(DateTime value, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final local = value.toLocal();
    final diff = reference.difference(local);
    if (diff.inSeconds < 60) return 'à l’instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24 && reference.day == local.day) return 'il y a ${diff.inHours} h';
    final yesterday = DateTime(reference.year, reference.month, reference.day - 1);
    if (local.year == yesterday.year && local.month == yesterday.month && local.day == yesterday.day) {
      return 'hier';
    }
    return DateFormat('d MMM', 'fr').format(local);
  }

  /// Téléphone lisible : `771234567` → `77 123 45 67` ; autres formats
  /// rendus tels quels.
  static String phone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 9 && !raw.startsWith('+')) {
      return '${digits.substring(0, 2)} ${digits.substring(2, 5)} ${digits.substring(5, 7)} ${digits.substring(7)}';
    }
    return raw;
  }

  /// Monogramme d'un article (maquette) : première lettre + consonne
  /// suivante du premier mot — « Riz brisé » → `RZ`, « Huile » → `HL`.
  static String productMonogram(String? name) {
    final word = (name ?? '').trim().split(RegExp(r'\s+')).first;
    final letters = word.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
    if (letters.isEmpty) return initials(name);
    if (letters.length == 1) return letters.toUpperCase();
    final rest = letters.substring(1);
    final consonant = RegExp(r'[^aeiouyàâäéèêëîïôöùûüÿAEIOUY]').firstMatch(rest)?.group(0) ?? rest[0];
    return (letters[0] + consonant).toUpperCase();
  }

  /// Initiales pour les avatars : « Awa Ndiaye » → « AN ».
  static String initials(String? name) {
    final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters(2).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

extension on String {
  String characters(int count) => length <= count ? this : substring(0, count);
}
