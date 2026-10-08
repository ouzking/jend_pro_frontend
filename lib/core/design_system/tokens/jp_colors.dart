import 'package:flutter/material.dart';

/// Palette brute JËND PRO — charte « Forêt, Menthe Signal, Laiton »
/// (maquettes de marque : signalétique, kit, icône, application).
///
/// Ne pas utiliser directement dans les écrans : passer par [JpPalette]
/// (`context.palette`) ou le `ColorScheme`, qui gèrent clair / sombre.
abstract final class JpColors {
  // Forêt — couleur institutionnelle (t-shirt, cartes, carnet).
  static const forest975 = Color(0xFF040A08);
  static const forest950 = Color(0xFF07110E);
  static const forest900 = Color(0xFF0B1A15);
  static const forest850 = Color(0xFF10231C);
  static const forest800 = Color(0xFF153126);
  static const forest700 = Color(0xFF1D4536);
  static const forest600 = Color(0xFF245A45);
  static const forest500 = Color(0xFF2E7055);
  static const forest100 = Color(0xFFDDEBE4);
  static const forest50 = Color(0xFFEEF5F1);

  // Menthe Signal — le point lumineux du monogramme, accents vivants.
  static const mint700 = Color(0xFF158059);
  static const mint600 = Color(0xFF1FA271);
  static const mint500 = Color(0xFF34C48C);
  static const mint400 = Color(0xFF63D7A8);
  static const mint300 = Color(0xFFA6EACB);
  static const mint100 = Color(0xFFDDF7EA);

  // Laiton — dorure (signalétique, cartes de visite), usage parcimonieux.
  static const brass700 = Color(0xFF7D5620);
  static const brass600 = Color(0xFF9C6D2C);
  static const brass500 = Color(0xFFB98A43);
  static const brass400 = Color(0xFFD2AA68);
  static const brass100 = Color(0xFFF5EBD9);

  // Neutres — légèrement teintés de vert pour rester dans la marque.
  static const neutral0 = Color(0xFFFFFFFF);
  static const neutral50 = Color(0xFFF5F5F1);
  static const neutral100 = Color(0xFFECECE6);
  static const neutral200 = Color(0xFFE0E1DA);
  static const neutral300 = Color(0xFFCBCEC6);
  static const neutral400 = Color(0xFF8D978F);
  static const neutral500 = Color(0xFF66716A);
  static const neutral600 = Color(0xFF465049);
  static const neutral800 = Color(0xFF1C2420);
  static const neutral900 = Color(0xFF111814);

  // Sémantiques.
  static const red600 = Color(0xFFB8402B);
  static const red400 = Color(0xFFEE8A76);
  static const red100 = Color(0xFFF9E1DB);
  static const amber700 = Color(0xFF9A5B00);
  static const amber400 = Color(0xFFF0B85A);
  static const amber100 = Color(0xFFFCEFD4);
  static const blue600 = Color(0xFF2860C2);
  static const blue400 = Color(0xFF79A3EC);
  static const blue100 = Color(0xFFE2EBFA);
}
