import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../errors/app_failure.dart';
import '../theme/app_theme.dart';
import '../tokens/jp_metrics.dart';
import '../tokens/jp_palette.dart';
import '../tokens/jp_typography.dart';
import 'jp_button.dart';
import 'jp_skeleton.dart';

/// Illustration sobre : icône dans un double cercle teinté.
class JpIllustratedIcon extends StatelessWidget {
  const JpIllustratedIcon({super.key, required this.icon, this.tone = JpTone.brand, this.size = 88});

  final IconData icon;
  final JpTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette.tone(tone);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.12),
        decoration: BoxDecoration(color: colors.background.withValues(alpha: 0.5), shape: BoxShape.circle),
        child: Container(
          decoration: BoxDecoration(color: colors.background, shape: BoxShape.circle),
          child: Icon(icon, size: size * 0.38, color: colors.foreground),
        ),
      ),
    );
  }
}

/// État vide : jamais une page blanche sans explication.
class JpEmptyState extends StatelessWidget {
  const JpEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.tone = JpTone.brand,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final JpTone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(JpSpacing.xxxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              JpIllustratedIcon(icon: icon, tone: tone),
              const SizedBox(height: JpSpacing.xxl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: JpTypography.title.copyWith(color: p.textPrimary),
              ),
              if (message != null) ...[
                const SizedBox(height: JpSpacing.sm),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: JpTypography.body.copyWith(color: p.textSecondary),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: JpSpacing.xxl),
                JpButton(label: actionLabel!, onPressed: onAction, expand: false, size: JpButtonSize.medium),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// État d'erreur à partir d'une [AppFailure], avec action « Réessayer ».
class JpErrorState extends StatelessWidget {
  const JpErrorState({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failure = AppFailure.from(error);
    final (icon, title, tone) = switch (failure.kind) {
      FailureKind.network => (Icons.wifi_off_rounded, 'Pas de connexion', JpTone.warning),
      FailureKind.permission => (Icons.lock_outline_rounded, 'Accès restreint', JpTone.neutral),
      FailureKind.notFound => (Icons.search_off_rounded, 'Introuvable', JpTone.neutral),
      _ => (Icons.error_outline_rounded, 'Un problème est survenu', JpTone.danger),
    };
    return JpEmptyState(
      icon: icon,
      tone: tone,
      title: title,
      message: failure.message,
      actionLabel: onRetry != null && failure.kind != FailureKind.permission ? 'Réessayer' : null,
      onAction: onRetry,
    );
  }
}

/// Affiche un `AsyncValue` avec les trois états standard.
///
/// Lors d'un rafraîchissement, l'ancienne donnée reste affichée (pas de
/// clignotement vers le squelette).
class JpAsyncView<T> extends StatelessWidget {
  const JpAsyncView({super.key, required this.value, required this.data, this.loading, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final Widget? loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: JpMotion.base,
      child: value.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        data: (d) => KeyedSubtree(key: const ValueKey('data'), child: data(d)),
        loading: () => KeyedSubtree(key: const ValueKey('loading'), child: loading ?? const JpSkeletonList()),
        error: (e, _) => KeyedSubtree(
          key: const ValueKey('error'),
          child: JpErrorState(error: e, onRetry: onRetry),
        ),
      ),
    );
  }
}
