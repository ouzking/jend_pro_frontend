import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';

/// Mise en page des écrans d'authentification et d'accueil :
/// bandeau émeraude de marque + feuille de contenu qui monte doucement.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.showBack = false,
    this.compactHero = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final bool showBack;

  /// Bandeau réduit pour les écrans secondaires.
  final bool compactHero;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = JpBreakpoints.isTablet(context);
    final heroHeight = compactHero ? 168.0 : 236.0;

    final sheet = _EntranceAnimation(
      child: Container(
        decoration: BoxDecoration(
          color: p.background,
          borderRadius: isTablet
              ? JpRadius.all(JpRadius.xxl)
              : const BorderRadius.vertical(top: Radius.circular(JpRadius.xxl)),
          boxShadow: isTablet ? JpShadows.lg(p.shadow) : null,
        ),
        padding: const EdgeInsets.fromLTRB(JpSpacing.xxl, JpSpacing.xxxl, JpSpacing.xxl, JpSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: JpTypography.headline.copyWith(color: p.textPrimary)),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: JpSpacing.sm),
              Text(subtitle!, style: JpTypography.body.copyWith(color: p.textSecondary)),
            ],
            const SizedBox(height: JpSpacing.xxl),
            child,
            if (footer != null) ...[const SizedBox(height: JpSpacing.xxl), footer!],
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: p.heroEnd,
      body: Stack(
        children: [
          Positioned.fill(child: _HeroBackground(height: heroHeight)),
          SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: heroHeight - MediaQuery.paddingOf(context).top,
                        child: _HeroContent(showBack: showBack, compact: compactHero),
                      ),
                      if (isTablet)
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: JpSpacing.maxFormWidth + 48),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: JpSpacing.huge),
                              child: sheet,
                            ),
                          ),
                        )
                      else ...[
                        // Les coins arrondis de la feuille laissent voir le
                        // dégradé ; le fond sable continue en dessous.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight - heroHeight + MediaQuery.paddingOf(context).top,
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: p.background,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(JpRadius.xxl)),
                            ),
                            child: Padding(
                              padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
                              child: sheet,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBackground extends StatelessWidget {
  const _HeroBackground({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      children: [
        Container(
          height: height + JpRadius.xxl,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [p.heroStart, p.heroEnd],
            ),
          ),
          child: const _DotsMotif(),
        ),
        Expanded(child: ColoredBox(color: JpBreakpoints.isTablet(context) ? p.heroEnd : p.background)),
      ],
    );
  }
}

/// Motif signature : le monogramme en très grand et très discret, et les
/// deux carrés du tréma — dont le point Menthe Signal.
class _DotsMotif extends StatelessWidget {
  const _DotsMotif();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -70,
            top: -40,
            child: Opacity(
              opacity: 0.07,
              child: JpMonogram(size: 300, color: Colors.white, signalColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({required this.showBack, required this.compact});

  final bool showBack;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(JpSpacing.xxl, JpSpacing.md, JpSpacing.xxl, JpSpacing.xxxl + JpSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showBack)
            IconButton(
              tooltip: 'Retour',
              onPressed: () => Navigator.of(context).maybePop(),
              style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.12)),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            )
          else
            const SizedBox(height: JpSize.touchTarget),
          // Le bloc se réduit au lieu de déborder (petits écrans, grande
          // taille de texte système).
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const JpLogo(size: 44, onDark: true),
                  if (!compact) ...[
                    const SizedBox(height: JpSpacing.md),
                    Text(
                      'La plateforme intelligente\npour piloter son commerce.',
                      style: JpTypography.titleSmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntranceAnimation extends StatelessWidget {
  const _EntranceAnimation({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: JpMotion.slow,
      curve: JpMotion.emphasized,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
      ),
    );
  }
}
