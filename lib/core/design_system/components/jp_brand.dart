import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../tokens/jp_colors.dart';
import '../tokens/jp_metrics.dart';
import '../tokens/jp_typography.dart';

/// Monogramme JËND PRO : un « J » couronné de deux carrés — le tréma du
/// « Ë » — dont l'un est le point lumineux « Menthe Signal ».
class JpMonogram extends StatelessWidget {
  const JpMonogram({super.key, this.size = 48, this.color, this.signalColor});

  final double size;

  /// Couleur du « J » et du carré supérieur (par défaut : texte principal).
  final Color? color;
  final Color? signalColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CustomPaint(
      size: Size.square(size),
      painter: _MonogramPainter(color: color ?? p.textPrimary, signal: signalColor ?? p.signal),
    );
  }
}

class _MonogramPainter extends CustomPainter {
  const _MonogramPainter({required this.color, required this.signal});

  final Color color;
  final Color signal;

  @override
  void paint(Canvas canvas, Size size) {
    // Dessin sur une grille de 100 × 100.
    final s = size.width / 100;
    canvas.save();
    canvas.scale(s);

    final fill = Paint()..color = color;
    const stroke = 15.0;

    // Fût + crochet du J.
    final hook = Path()
      ..moveTo(66, 38)
      ..lineTo(66, 63)
      ..arcToPoint(const Offset(30, 63), radius: const Radius.circular(18))
      ..lineTo(30, 58);
    canvas.drawPath(
      hook,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.miter,
    );

    // Carré supérieur (point du j) et carré Menthe Signal.
    const r = Radius.circular(2.2);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(58.5, 13, 15, 15), r), fill);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(31, 22, 15, 15), r), Paint()..color = signal);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MonogramPainter old) => old.color != color || old.signal != signal;
}

/// Monogramme sur tuile émaillée vert forêt (icône d'application, avatars
/// de marque).
class JpLogoMark extends StatelessWidget {
  const JpLogoMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'JËND PRO',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: JpRadius.all(size * 0.28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [JpColors.forest500, JpColors.forest800],
          ),
        ),
        alignment: Alignment.center,
        child: JpMonogram(size: size * 0.78, color: JpColors.neutral50, signalColor: JpColors.mint300),
      ),
    );
  }
}

/// Wordmark « JËND PRO » (Jost, géométrique) précédé du monogramme.
class JpLogo extends StatelessWidget {
  const JpLogo({super.key, this.size = 40, this.onDark = false, this.tile = false});

  /// Hauteur de référence du monogramme.
  final double size;

  /// Sur fond sombre (bandeaux, signalétique) : blanc + Menthe Signal.
  final bool onDark;

  /// Monogramme sur tuile (icône) plutôt que « nu ».
  final bool tile;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = onDark ? JpColors.neutral50 : p.textPrimary;
    return Semantics(
      label: 'JËND PRO',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tile)
              JpLogoMark(size: size)
            else
              JpMonogram(size: size, color: color, signalColor: onDark ? JpColors.mint300 : p.signal),
            SizedBox(width: size * (tile ? 0.3 : 0.12)),
            Text(
              'JËND PRO',
              style: JpTypography.wordmark.copyWith(color: color, fontSize: size * 0.52),
            ),
          ],
        ),
      ),
    );
  }
}
