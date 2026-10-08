import 'package:flutter/material.dart';

import '../../formatting/formatters.dart';
import '../theme/app_theme.dart';
import '../tokens/jp_metrics.dart';
import '../tokens/jp_palette.dart';
import '../tokens/jp_typography.dart';

/// Titre de section avec action facultative (« Voir tout »).
class JpSectionHeader extends StatelessWidget {
  const JpSectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      header: true,
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: JpTypography.titleSmall.copyWith(color: p.textPrimary)),
          ),
          if (actionLabel != null && onAction != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// Avatar à initiales, couleur stable dérivée du nom.
class JpAvatar extends StatelessWidget {
  const JpAvatar({super.key, required this.name, this.size = JpSize.avatarMd});

  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const tones = [JpTone.brand, JpTone.accent, JpTone.info, JpTone.success, JpTone.warning];
    final tone = p.tone(tones[(name ?? '').hashCode.abs() % tones.length]);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tone.background, shape: BoxShape.circle),
        child: Text(
          Formatters.initials(name),
          style: JpTypography.label.copyWith(color: tone.foreground, fontSize: size * 0.36),
        ),
      ),
    );
  }
}

/// Montant formaté, chiffres tabulaires, avec la devise en plus discret.
class JpAmount extends StatelessWidget {
  const JpAmount(this.amount, {super.key, this.currency = 'XOF', this.style, this.color, this.compact = false});

  final int amount;
  final String currency;
  final TextStyle? style;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final base = JpTypography.numeric(style ?? JpTypography.bodyStrong);
    final effectiveColor = color ?? base.color ?? context.palette.textPrimary;
    final full = compact
        ? Formatters.moneyCompact(amount, currency: currency)
        : Formatters.money(amount, currency: currency);
    final symbol = Formatters.currencySymbol(currency);
    final value = full.endsWith(symbol) ? full.substring(0, full.length - symbol.length).trimRight() : full;
    return Semantics(
      label: full,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: value),
            TextSpan(
              text: ' $symbol',
              style: TextStyle(
                fontSize: (base.fontSize ?? 15) * 0.55,
                fontWeight: FontWeight.w600,
                color: effectiveColor.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
        style: base.copyWith(color: effectiveColor),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Bannière d'information contextuelle (mode restreint, hors ligne…).
class JpBanner extends StatelessWidget {
  const JpBanner({
    super.key,
    required this.message,
    this.tone = JpTone.info,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final JpTone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette.tone(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.md),
      decoration: BoxDecoration(color: colors.background, borderRadius: JpRadius.all(JpRadius.md)),
      child: Row(
        children: [
          Icon(icon ?? Icons.info_outline_rounded, color: colors.foreground, size: JpSize.iconMd),
          const SizedBox(width: JpSpacing.md),
          Expanded(
            child: Text(
              message,
              style: JpTypography.bodySmall.copyWith(color: colors.foreground, fontWeight: FontWeight.w500),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: colors.foreground),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Centre et limite la largeur du contenu sur tablette.
class JpConstrained extends StatelessWidget {
  const JpConstrained({super.key, required this.child, this.maxWidth = JpSpacing.maxContentWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
