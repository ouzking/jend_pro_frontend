import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system/design_system.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/business/application/workspace_controller.dart';

/// Écran de démarrage : affiché pendant le chargement du contexte de travail,
/// ou en cas d'échec (avec « Réessayer » — jamais un écran blanc).
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final workspace = ref.watch(workspaceProvider);
    final error = workspace.hasError && !workspace.isLoading ? workspace.error : null;

    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: JpMotion.base,
          child: error == null
              ? Center(
                  key: const ValueKey('loading'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const JpLogoMark(size: 72),
                      const SizedBox(height: JpSpacing.xxl),
                      SizedBox(
                        width: 120,
                        child: LinearProgressIndicator(minHeight: 3, borderRadius: JpRadius.all(JpRadius.pill)),
                      ),
                      const SizedBox(height: JpSpacing.lg),
                      Text('Préparation de votre espace…', style: JpTypography.bodySmall.copyWith(color: p.textMuted)),
                    ],
                  ),
                )
              : Column(
                  key: const ValueKey('error'),
                  children: [
                    Expanded(
                      child: JpErrorState(error: error, onRetry: () => ref.read(workspaceProvider.notifier).retry()),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: JpSpacing.xl),
                      child: TextButton(
                        onPressed: () => ref.read(authRepositoryProvider).signOut(),
                        child: const Text('Se déconnecter'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
