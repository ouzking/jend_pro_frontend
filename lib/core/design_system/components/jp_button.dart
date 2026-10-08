import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../tokens/jp_metrics.dart';
import '../tokens/jp_typography.dart';

enum JpButtonVariant { primary, secondary, outline, ghost, danger }

enum JpButtonSize { small, medium, large }

/// Bouton JËND PRO : variantes, tailles, état de chargement et léger retour
/// tactile à la pression. Désactivé si [onPressed] est `null`.
class JpButton extends StatefulWidget {
  const JpButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = JpButtonVariant.primary,
    this.size = JpButtonSize.large,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = true,
  });

  const JpButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = JpButtonSize.large,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = true,
  }) : variant = JpButtonVariant.secondary;

  const JpButton.outline({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = JpButtonSize.large,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = true,
  }) : variant = JpButtonVariant.outline;

  const JpButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = JpButtonSize.medium,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = false,
  }) : variant = JpButtonVariant.ghost;

  final String label;
  final VoidCallback? onPressed;
  final JpButtonVariant variant;
  final JpButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool isLoading;
  final bool expand;

  @override
  State<JpButton> createState() => _JpButtonState();
}

class _JpButtonState extends State<JpButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg, border) = switch (widget.variant) {
      JpButtonVariant.primary => (p.brand, p.textOnBrand, null),
      JpButtonVariant.secondary => (p.brandSoft, p.brandStrong, null),
      JpButtonVariant.outline => (p.surface, p.textPrimary, p.borderStrong),
      JpButtonVariant.ghost => (Colors.transparent, p.brand, null),
      JpButtonVariant.danger => (p.danger, Colors.white, null),
    };
    final height = switch (widget.size) {
      JpButtonSize.small => JpSize.buttonSm,
      JpButtonSize.medium => JpSize.buttonMd,
      JpButtonSize.large => JpSize.buttonLg,
    };
    final textStyle = widget.size == JpButtonSize.small
        ? JpTypography.label.copyWith(fontSize: 13)
        : JpTypography.label.copyWith(fontSize: widget.size == JpButtonSize.large ? 16 : 15);
    final hPadding = widget.size == JpButtonSize.small ? JpSpacing.md : JpSpacing.xl;
    final effectiveBg = _enabled ? bg : (widget.variant == JpButtonVariant.ghost ? bg : p.surfaceMuted);
    final effectiveFg = _enabled || widget.isLoading ? fg : p.textMuted;

    Widget content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: JpSize.iconSm + 2, color: effectiveFg),
          const SizedBox(width: JpSpacing.sm),
        ],
        Flexible(
          child: Text(
            widget.label,
            style: textStyle.copyWith(color: effectiveFg),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        if (widget.trailingIcon != null) ...[
          const SizedBox(width: JpSpacing.sm),
          Icon(widget.trailingIcon, size: JpSize.iconSm + 2, color: effectiveFg),
        ],
      ],
    );

    if (widget.isLoading) {
      content = Stack(
        alignment: Alignment.center,
        children: [
          Opacity(opacity: 0, child: content),
          SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg)),
        ],
      );
    }

    final radius = JpRadius.all(widget.size == JpButtonSize.small ? JpRadius.sm : JpRadius.md);

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.isLoading ? '${widget.label}, chargement' : null,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: JpMotion.fast,
        curve: JpMotion.emphasized,
        child: Material(
          color: effectiveBg,
          clipBehavior: Clip.antiAlias,
          // Une seule forme (Material refuse `shape` + `borderRadius`).
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: border == null ? BorderSide.none : BorderSide(color: border),
          ),
          child: InkWell(
            onTap: _enabled
                ? () {
                    if (widget.variant == JpButtonVariant.primary) HapticFeedback.lightImpact();
                    widget.onPressed!();
                  }
                : null,
            onHighlightChanged: _enabled ? _setPressed : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height, minWidth: height),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hPadding),
                child: Center(widthFactor: widget.expand ? null : 1, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
