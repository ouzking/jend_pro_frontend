import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../tokens/jp_metrics.dart';
import '../tokens/jp_palette.dart';
import '../tokens/jp_typography.dart';
import 'jp_button.dart';

/// Feuilles du bas, dialogues et messages éphémères — API unique.
abstract final class JpOverlays {
  /// Feuille modale avec titre, défilable et compatible clavier.
  static Future<T?> sheet<T>(
    BuildContext context, {
    required Widget child,
    String? title,
    String? subtitle,
    bool scrollable = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: JpSpacing.maxContentWidth),
      builder: (context) {
        final p = context.palette;
        final body = Padding(
          padding: EdgeInsets.fromLTRB(
            JpSpacing.gutter,
            0,
            JpSpacing.gutter,
            JpSpacing.xxl + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Text(title, style: JpTypography.title.copyWith(color: p.textPrimary)),
                if (subtitle != null) ...[
                  const SizedBox(height: JpSpacing.xs),
                  Text(subtitle, style: JpTypography.body.copyWith(color: p.textSecondary)),
                ],
                const SizedBox(height: JpSpacing.xl),
              ],
              child,
            ],
          ),
        );
        return scrollable ? SingleChildScrollView(child: body) : body;
      },
    );
  }

  /// Confirmation explicite. Renvoie `true` si l'utilisateur confirme.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirmer',
    String cancelLabel = 'Annuler',
    bool destructive = false,
    IconData? icon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        final p = context.palette;
        final tone = p.tone(destructive ? JpTone.danger : JpTone.brand);
        return Dialog(
          insetPadding: const EdgeInsets.all(JpSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(JpSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: tone.background, borderRadius: JpRadius.all(JpRadius.md)),
                    child: Icon(
                      icon ?? (destructive ? Icons.warning_amber_rounded : Icons.help_outline_rounded),
                      color: tone.foreground,
                    ),
                  ),
                  const SizedBox(height: JpSpacing.lg),
                  Text(title, style: JpTypography.title.copyWith(color: p.textPrimary)),
                  const SizedBox(height: JpSpacing.sm),
                  Text(message, style: JpTypography.body.copyWith(color: p.textSecondary)),
                  const SizedBox(height: JpSpacing.xxl),
                  Row(
                    children: [
                      Expanded(
                        child: JpButton.outline(
                          label: cancelLabel,
                          size: JpButtonSize.medium,
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                      ),
                      const SizedBox(width: JpSpacing.md),
                      Expanded(
                        child: JpButton(
                          label: confirmLabel,
                          size: JpButtonSize.medium,
                          variant: destructive ? JpButtonVariant.danger : JpButtonVariant.primary,
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  /// Message éphémère en bas d'écran.
  static void toast(BuildContext context, String message, {JpTone tone = JpTone.neutral, IconData? icon}) {
    final p = context.palette;
    // Le fond des messages est inversé (foncé en thème clair, clair en thème
    // sombre) : les couleurs viennent du thème des SnackBar pour rester lisibles.
    final snack = Theme.of(context).snackBarTheme;
    final onSnack = snackBarForeground(context);
    final color = switch (tone) {
      JpTone.success || JpTone.brand => snack.actionTextColor ?? onSnack,
      JpTone.danger => p.danger,
      JpTone.warning => p.warning,
      _ => null,
    };
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null || color != null) ...[
              Icon(
                icon ??
                    switch (tone) {
                      JpTone.danger => Icons.error_outline_rounded,
                      JpTone.warning => Icons.warning_amber_rounded,
                      _ => Icons.check_circle_rounded,
                    },
                color: color ?? onSnack,
                size: JpSize.iconMd,
              ),
              const SizedBox(width: JpSpacing.md),
            ],
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  /// Couleur du texte des SnackBar selon le thème courant.
  static Color snackBarForeground(BuildContext context) =>
      Theme.of(context).snackBarTheme.contentTextStyle?.color ?? Colors.white;
}
