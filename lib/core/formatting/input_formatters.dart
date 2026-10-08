import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Saisie de montant entier (FCFA) avec séparateurs de milliers en direct :
/// `150000` s'affiche `150 000`. Lire la valeur avec [AmountInputFormatter.parse].
class AmountInputFormatter extends TextInputFormatter {
  static final _format = NumberFormat('#,##0', 'fr');

  /// Plafond raisonnable (bigint côté base, mais une saisie > 999 milliards
  /// est forcément une erreur de frappe).
  static const maxDigits = 12;

  static int? parse(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : int.parse(digits);
  }

  static String format(int value) => _format.format(value);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > maxDigits) return oldValue;
    digits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final formatted = _format.format(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Saisie de quantité : entière, ou jusqu'à 3 décimales si [allowDecimals]
/// (`numeric(14,3)` en base). Virgule ou point acceptés.
class QuantityInputFormatter extends TextInputFormatter {
  QuantityInputFormatter({required this.allowDecimals});

  final bool allowDecimals;

  static num? parse(String text) {
    final normalized = text.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return num.tryParse(normalized);
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final pattern = allowDecimals ? RegExp(r'^\d{0,9}([.,]\d{0,3})?$') : RegExp(r'^\d{0,9}$');
    return pattern.hasMatch(newValue.text) ? newValue : oldValue;
  }
}
