import 'package:flutter/material.dart';

/// Typographie JËND PRO — Plus Jakarta Sans (police variable embarquée).
///
/// La police est variable : on règle l'axe `wght` en plus de `fontWeight`
/// pour un rendu identique sur toutes les plateformes.
abstract final class JpTypography {
  static const family = 'PlusJakartaSans';

  /// Police du wordmark uniquement (géométrique, proche de la signalétique).
  static const brandFamily = 'Jost';

  static TextStyle _style(double size, double lineHeight, FontWeight weight, {double tracking = 0}) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    fontVariations: [FontVariation.weight(weight.value.toDouble())],
    letterSpacing: tracking,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Grands montants (CA du jour, total du panier).
  static final display = _style(34, 40, FontWeight.w800, tracking: -1.0);
  static final headline = _style(26, 32, FontWeight.w700, tracking: -0.6);
  static final title = _style(20, 26, FontWeight.w700, tracking: -0.3);
  static final titleSmall = _style(16, 22, FontWeight.w600, tracking: -0.1);
  static final body = _style(15, 22, FontWeight.w400);
  static final bodyStrong = _style(15, 22, FontWeight.w600);
  static final bodySmall = _style(13, 18, FontWeight.w400);
  static final label = _style(14, 18, FontWeight.w600);
  static final caption = _style(12, 16, FontWeight.w500);
  static final overline = _style(11, 14, FontWeight.w700, tracking: 0.8);

  /// Logotype « JËND PRO ».
  static final wordmark = TextStyle(
    fontFamily: brandFamily,
    fontSize: 20,
    height: 1,
    fontWeight: FontWeight.w500,
    fontVariations: const [FontVariation.weight(500)],
    letterSpacing: 0.4,
    decoration: TextDecoration.none,
  );

  /// Chiffres alignés pour montants et quantités.
  static TextStyle numeric(TextStyle base) => base.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextTheme textTheme(Color primary, Color secondary) => TextTheme(
    displayLarge: display.copyWith(color: primary),
    displayMedium: display.copyWith(color: primary, fontSize: 30),
    displaySmall: headline.copyWith(color: primary, fontSize: 28),
    headlineLarge: headline.copyWith(color: primary),
    headlineMedium: headline.copyWith(color: primary, fontSize: 24),
    headlineSmall: title.copyWith(color: primary, fontSize: 22),
    titleLarge: title.copyWith(color: primary),
    titleMedium: titleSmall.copyWith(color: primary),
    titleSmall: label.copyWith(color: primary),
    bodyLarge: body.copyWith(color: primary),
    bodyMedium: body.copyWith(color: primary),
    bodySmall: bodySmall.copyWith(color: secondary),
    labelLarge: label.copyWith(color: primary),
    labelMedium: caption.copyWith(color: secondary),
    labelSmall: overline.copyWith(color: secondary),
  );
}
