import 'package:flutter/material.dart';

import 'jp_colors.dart';

/// Ton sémantique partagé par badges, bannières, indicateurs.
enum JpTone { neutral, brand, accent, success, warning, danger, info }

/// Paire fond / premier plan pour un [JpTone].
@immutable
class JpToneColors {
  const JpToneColors(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

/// Jetons de couleur sémantiques, résolus pour le thème courant.
@immutable
class JpPalette extends ThemeExtension<JpPalette> {
  const JpPalette({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceRaised,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textOnBrand,
    required this.brand,
    required this.brandStrong,
    required this.brandSoft,
    required this.accent,
    required this.accentSoft,
    required this.signal,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.heroStart,
    required this.heroEnd,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.shadow,
    required this.chart,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceRaised;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textOnBrand;
  final Color brand;
  final Color brandStrong;
  final Color brandSoft;
  final Color accent;
  final Color accentSoft;

  /// « Menthe Signal » : point lumineux, valeurs mises en avant, graphiques.
  final Color signal;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;

  /// Dégradé sobre des cartes « héros » (CA du jour, total du panier).
  final Color heroStart;
  final Color heroEnd;
  final Color skeletonBase;
  final Color skeletonHighlight;
  final Color shadow;

  /// Séries de graphiques, dans l'ordre d'usage.
  final List<Color> chart;

  JpToneColors tone(JpTone tone) => switch (tone) {
    JpTone.neutral => JpToneColors(surfaceMuted, textSecondary),
    JpTone.brand => JpToneColors(brandSoft, brandStrong),
    JpTone.accent => JpToneColors(accentSoft, accent),
    JpTone.success => JpToneColors(successSoft, success),
    JpTone.warning => JpToneColors(warningSoft, warning),
    JpTone.danger => JpToneColors(dangerSoft, danger),
    JpTone.info => JpToneColors(infoSoft, info),
  };

  static const light = JpPalette(
    background: JpColors.neutral50,
    surface: JpColors.neutral0,
    surfaceMuted: JpColors.neutral100,
    surfaceRaised: JpColors.neutral0,
    border: JpColors.neutral200,
    borderStrong: JpColors.neutral300,
    textPrimary: JpColors.neutral900,
    textSecondary: JpColors.neutral600,
    textMuted: JpColors.neutral400,
    textOnBrand: Colors.white,
    brand: JpColors.forest700,
    brandStrong: JpColors.forest800,
    brandSoft: JpColors.forest50,
    accent: JpColors.brass500,
    accentSoft: JpColors.brass100,
    signal: JpColors.mint600,
    success: JpColors.mint700,
    successSoft: JpColors.mint100,
    warning: JpColors.amber700,
    warningSoft: JpColors.amber100,
    danger: JpColors.red600,
    dangerSoft: JpColors.red100,
    info: JpColors.blue600,
    infoSoft: JpColors.blue100,
    heroStart: JpColors.forest600,
    heroEnd: JpColors.forest850,
    skeletonBase: JpColors.neutral100,
    skeletonHighlight: JpColors.neutral50,
    shadow: JpColors.forest950,
    chart: [JpColors.forest600, JpColors.mint500, JpColors.brass500, JpColors.blue600, JpColors.neutral400],
  );

  /// Thème sombre — l'apparence de référence de l'application (maquette).
  static const dark = JpPalette(
    background: JpColors.forest975,
    surface: JpColors.forest900,
    surfaceMuted: JpColors.forest850,
    surfaceRaised: JpColors.forest850,
    border: Color(0xFF17291F),
    borderStrong: Color(0xFF223A2E),
    textPrimary: Color(0xFFF1F5F2),
    textSecondary: Color(0xFFB4C1B9),
    textMuted: Color(0xFF7D8C83),
    textOnBrand: JpColors.forest975,
    brand: JpColors.mint500,
    brandStrong: JpColors.mint400,
    brandSoft: Color(0xFF0E2A1F),
    accent: JpColors.brass400,
    accentSoft: Color(0xFF2C2312),
    signal: JpColors.mint400,
    success: JpColors.mint400,
    successSoft: Color(0xFF0E2A1F),
    warning: JpColors.amber400,
    warningSoft: Color(0xFF30230C),
    danger: JpColors.red400,
    dangerSoft: Color(0xFF341812),
    info: JpColors.blue400,
    infoSoft: Color(0xFF14213A),
    heroStart: Color(0xFF145A40),
    heroEnd: JpColors.forest850,
    skeletonBase: JpColors.forest850,
    skeletonHighlight: JpColors.forest800,
    shadow: Colors.black,
    chart: [JpColors.mint500, JpColors.brass400, JpColors.blue400, JpColors.red400, Color(0xFF7D8C83)],
  );

  @override
  JpPalette copyWith() => this;

  @override
  JpPalette lerp(JpPalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return JpPalette(
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textMuted: c(textMuted, other.textMuted),
      textOnBrand: c(textOnBrand, other.textOnBrand),
      brand: c(brand, other.brand),
      brandStrong: c(brandStrong, other.brandStrong),
      brandSoft: c(brandSoft, other.brandSoft),
      accent: c(accent, other.accent),
      accentSoft: c(accentSoft, other.accentSoft),
      signal: c(signal, other.signal),
      success: c(success, other.success),
      successSoft: c(successSoft, other.successSoft),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      info: c(info, other.info),
      infoSoft: c(infoSoft, other.infoSoft),
      heroStart: c(heroStart, other.heroStart),
      heroEnd: c(heroEnd, other.heroEnd),
      skeletonBase: c(skeletonBase, other.skeletonBase),
      skeletonHighlight: c(skeletonHighlight, other.skeletonHighlight),
      shadow: c(shadow, other.shadow),
      chart: [for (var i = 0; i < chart.length; i++) c(chart[i], other.chart[i])],
    );
  }
}
