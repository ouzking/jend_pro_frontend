import 'package:flutter/material.dart';

/// Moyens de paiement (`payment_method` côté base).
enum PaymentMethod {
  cash('CASH', 'Espèces', Icons.payments_outlined),
  wave('WAVE', 'Wave', Icons.waves_rounded),
  orangeMoney('ORANGE_MONEY', 'Orange Money', Icons.phone_iphone_rounded),
  freeMoney('FREE_MONEY', 'Free Money', Icons.phone_android_rounded),
  card('CARD', 'Carte', Icons.credit_card_rounded),
  bankTransfer('BANK_TRANSFER', 'Virement', Icons.account_balance_outlined),
  cheque('CHEQUE', 'Chèque', Icons.receipt_long_outlined),
  other('OTHER', 'Autre', Icons.more_horiz_rounded);

  const PaymentMethod(this.code, this.label, this.icon);

  final String code;
  final String label;
  final IconData icon;

  static PaymentMethod? fromCode(String? code) {
    for (final m in values) {
      if (m.code == code) return m;
    }
    return null;
  }
}
