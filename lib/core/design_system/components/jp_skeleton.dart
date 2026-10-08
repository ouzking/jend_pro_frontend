import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../tokens/jp_metrics.dart';

/// Fournit une seule animation de brillance à tous les [JpSkeleton] du
/// sous-arbre (un seul ticker, quel que soit le nombre de blocs).
class JpShimmer extends StatefulWidget {
  const JpShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<JpShimmer> createState() => _JpShimmerState();
}

class _JpShimmerState extends State<JpShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) return widget.child;
    return Semantics(
      label: 'Chargement',
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final t = _controller.value;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [p.skeletonBase, p.skeletonHighlight, p.skeletonBase],
              stops: const [0.25, 0.5, 0.75],
              transform: _SlideGradient(t),
            ).createShader(bounds),
            child: child,
          );
        },
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.t);

  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}

/// Bloc gris arrondi : brique de base des écrans de chargement.
class JpSkeleton extends StatelessWidget {
  const JpSkeleton({super.key, this.width, this.height = 14, this.radius = JpRadius.xs});

  const JpSkeleton.circle({super.key, double size = JpSize.avatarMd})
    : width = size,
      height = size,
      radius = JpRadius.pill;

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: context.palette.skeletonBase, borderRadius: JpRadius.all(radius)),
  );
}

/// Liste de lignes fantômes (avatar + deux lignes de texte).
class JpSkeletonList extends StatelessWidget {
  const JpSkeletonList({super.key, this.itemCount = 6, this.padding = const EdgeInsets.all(JpSpacing.gutter)});

  final int itemCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => JpShimmer(
    child: ListView.separated(
      padding: padding,
      // Utilisable seul (page) ou dans une liste défilante (sliver) :
      // la hauteur suit le contenu au lieu d'exiger une contrainte bornée.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: JpSpacing.xl),
      itemBuilder: (_, i) => Row(
        children: [
          const JpSkeleton.circle(),
          const SizedBox(width: JpSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(widthFactor: i.isEven ? 0.7 : 0.5, child: const JpSkeleton()),
                const SizedBox(height: JpSpacing.sm),
                const FractionallySizedBox(widthFactor: 0.35, child: JpSkeleton(height: 10)),
              ],
            ),
          ),
          const SizedBox(width: JpSpacing.md),
          const JpSkeleton(width: 64),
        ],
      ),
    ),
  );
}
