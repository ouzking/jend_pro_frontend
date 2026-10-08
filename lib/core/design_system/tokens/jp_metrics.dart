import 'package:flutter/material.dart';

/// Espacements — grille de 4 pt.
abstract final class JpSpacing {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 48.0;

  /// Marge latérale des pages (téléphone).
  static const gutter = 20.0;

  /// Largeur maximale du contenu sur tablette / grand écran.
  static const maxContentWidth = 720.0;

  /// Largeur maximale des formulaires (auth, onboarding).
  static const maxFormWidth = 440.0;
}

/// Rayons.
abstract final class JpRadius {
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const pill = 999.0;

  static BorderRadius all(double r) => BorderRadius.all(Radius.circular(r));
}

/// Tailles d'interaction (accessibilité : cible ≥ 48 dp).
abstract final class JpSize {
  static const touchTarget = 48.0;
  static const buttonLg = 56.0;
  static const buttonMd = 48.0;
  static const buttonSm = 36.0;
  static const input = 54.0;
  static const iconSm = 18.0;
  static const iconMd = 22.0;
  static const iconLg = 28.0;
  static const avatarSm = 32.0;
  static const avatarMd = 40.0;
  static const avatarLg = 56.0;
  static const navBar = 72.0;
}

/// Ombres — douces et superposées, jamais « portées » lourdement.
abstract final class JpShadows {
  static List<BoxShadow> sm(Color shadow) => [
    BoxShadow(color: shadow.withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1)),
    BoxShadow(color: shadow.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
  ];

  static List<BoxShadow> md(Color shadow) => [
    BoxShadow(color: shadow.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1)),
    BoxShadow(color: shadow.withValues(alpha: 0.08), blurRadius: 20, spreadRadius: -4, offset: const Offset(0, 8)),
  ];

  static List<BoxShadow> lg(Color shadow) => [
    BoxShadow(color: shadow.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2)),
    BoxShadow(color: shadow.withValues(alpha: 0.16), blurRadius: 36, spreadRadius: -8, offset: const Offset(0, 16)),
  ];

  /// Halo coloré des actions principales (bouton « Vendre »).
  static List<BoxShadow> glow(Color color) => [
    BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: -4, offset: const Offset(0, 8)),
  ];
}

/// Mouvement — les animations servent la compréhension, jamais la décoration.
abstract final class JpMotion {
  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 340);
  static const emphasized = Curves.easeOutCubic;
  static const standard = Curves.easeInOutCubic;
}

/// Points de rupture.
abstract final class JpBreakpoints {
  static const tablet = 600.0;
  static const desktop = 1024.0;

  static bool isTablet(BuildContext context) => MediaQuery.sizeOf(context).width >= tablet;
}
