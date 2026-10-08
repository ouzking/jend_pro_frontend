import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/jp_metrics.dart';
import '../tokens/jp_typography.dart';

/// Une barre : valeur + libellés (court sous l'axe, détaillé au toucher).
class JpBarDatum {
  const JpBarDatum({required this.value, required this.label, required this.detail});

  final num value;

  /// Libellé court (ex. « L », « 12 »), affiché sous la barre si la place le
  /// permet.
  final String label;

  /// Texte affiché au toucher (ex. « Lun. 6 oct. · 125 000 FCFA »).
  final String detail;
}

/// Histogramme sobre (maquette « Ventes du jour ») : barres arrondies,
/// dernière barre (ou barre touchée) mise en évidence, animation d'entrée.
class JpBarChart extends StatefulWidget {
  const JpBarChart({
    super.key,
    required this.data,
    required this.barColor,
    required this.highlightColor,
    required this.labelColor,
    this.height = 96,
    this.semanticsLabel,
    this.showLabels = true,
  });

  final List<JpBarDatum> data;
  final Color barColor;
  final Color highlightColor;
  final Color labelColor;
  final double height;
  final String? semanticsLabel;
  final bool showLabels;

  @override
  State<JpBarChart> createState() => _JpBarChartState();
}

class _JpBarChartState extends State<JpBarChart> {
  int? _selected;

  int get _highlight => _selected ?? widget.data.length - 1;

  @override
  void didUpdateWidget(JpBarChart old) {
    super.didUpdateWidget(old);
    if (old.data.length != widget.data.length) _selected = null;
  }

  void _select(Offset local, double width) {
    if (widget.data.isEmpty) return;
    final index = (local.dx / width * widget.data.length).floor().clamp(0, widget.data.length - 1);
    if (index != _selected) {
      HapticFeedback.selectionClick();
      setState(() => _selected = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final showLabels = widget.showLabels && data.length <= 14;
    final detail = data.isEmpty ? null : data[_highlight].detail;

    return Semantics(
      label: widget.semanticsLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 18,
            child: AnimatedSwitcher(
              duration: JpMotion.fast,
              child: Text(
                detail ?? '',
                key: ValueKey(detail),
                textAlign: TextAlign.right,
                style: JpTypography.numeric(JpTypography.caption).copyWith(color: widget.labelColor),
              ),
            ),
          ),
          const SizedBox(height: JpSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _select(d.localPosition, constraints.maxWidth),
              onHorizontalDragUpdate: (d) => _select(d.localPosition, constraints.maxWidth),
              child: TweenAnimationBuilder<double>(
                key: ValueKey(data.length),
                tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => CustomPaint(
                  size: Size(constraints.maxWidth, widget.height),
                  painter: _BarsPainter(
                    values: [for (final d in data) d.value.toDouble()],
                    highlight: _highlight,
                    progress: t,
                    barColor: widget.barColor,
                    highlightColor: widget.highlightColor,
                  ),
                ),
              ),
            ),
          ),
          if (showLabels) ...[
            const SizedBox(height: JpSpacing.xs + 2),
            Row(
              children: [
                for (var i = 0; i < data.length; i++)
                  Expanded(
                    child: Text(
                      data[i].label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: JpTypography.caption.copyWith(
                        fontSize: 10,
                        color: i == _highlight ? widget.highlightColor : widget.labelColor,
                        fontWeight: i == _highlight ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.highlight,
    required this.progress,
    required this.barColor,
    required this.highlightColor,
  });

  final List<double> values;
  final int highlight;
  final double progress;
  final Color barColor;
  final Color highlightColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = values.fold<double>(0, math.max);
    final slot = size.width / values.length;
    final gap = math.min(slot * 0.28, 10.0);
    final barWidth = math.max(slot - gap, 2.0);
    const minBar = 4.0;

    for (var i = 0; i < values.length; i++) {
      final ratio = maxValue <= 0 ? 0.0 : values[i] / maxValue;
      final h = math.max(minBar, ratio * size.height) * progress;
      final left = i * slot + (slot - barWidth) / 2;
      final rect = Rect.fromLTWH(left, size.height - h, barWidth, h);
      final radius = Radius.circular(math.min(barWidth / 2, 6));
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: radius,
          topRight: radius,
          bottomLeft: const Radius.circular(2),
          bottomRight: const Radius.circular(2),
        ),
        Paint()..color = i == highlight ? highlightColor : barColor,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.progress != progress ||
      old.highlight != highlight ||
      old.barColor != barColor ||
      old.highlightColor != highlightColor ||
      !_listEquals(old.values, values);

  static bool _listEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
