import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../application/setup_wizard_controller.dart';
import 'steps/done_step.dart';
import 'steps/info_step.dart';
import 'steps/logo_step.dart';
import 'steps/products_step.dart';
import 'steps/stock_step.dart';
import 'steps/type_step.dart';

/// Assistant de configuration : type → informations → logo → produits →
/// stock initial → c'est prêt. Chaque étape peut être passée.
class SetupWizardScreen extends ConsumerWidget {
  const SetupWizardScreen({super.key});

  static const _countedSteps = 5;

  Future<void> _finishLater(BuildContext context, WidgetRef ref) async {
    final confirmed = await JpOverlays.confirm(
      context,
      title: 'Terminer plus tard ?',
      message: 'Ce que vous avez déjà enregistré est conservé. Vous pourrez compléter votre catalogue à tout moment.',
      confirmLabel: 'Aller à l’accueil',
      icon: Icons.schedule_rounded,
    );
    if (!confirmed) return;
    await ref.read(setupWizardProvider.notifier).finish();
    if (context.mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final step = ref.watch(setupWizardProvider.select((s) => s.step));
    final controller = ref.read(setupWizardProvider.notifier);
    final isDone = step == SetupStep.done;

    final body = switch (step) {
      SetupStep.type => const TypeStep(),
      SetupStep.info => const InfoStep(),
      SetupStep.logo => const LogoStep(),
      SetupStep.products => const ProductsStep(),
      SetupStep.stock => const StockStep(),
      SetupStep.done => const DoneStep(),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && step.index > 0 && !isDone) controller.back();
      },
      child: Scaffold(
        body: SafeArea(
          child: JpConstrained(
            maxWidth: JpSpacing.maxFormWidth + 80,
            child: Column(
              children: [
                if (!isDone)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(JpSpacing.sm, JpSpacing.sm, JpSpacing.sm, 0),
                    child: Row(
                      children: [
                        if (step.index > 0)
                          IconButton(
                            tooltip: 'Étape précédente',
                            icon: const Icon(Icons.arrow_back_rounded),
                            onPressed: controller.back,
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.only(left: JpSpacing.md),
                            child: JpLogoMark(size: 32),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _finishLater(context, ref),
                          child: const Text('Terminer plus tard'),
                        ),
                      ],
                    ),
                  ),
                if (!isDone)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, 0),
                    child: Semantics(
                      label: 'Étape ${step.index + 1} sur $_countedSteps',
                      child: Row(
                        children: [
                          for (var i = 0; i < _countedSteps; i++) ...[
                            if (i > 0) const SizedBox(width: JpSpacing.xs + 2),
                            Expanded(
                              child: AnimatedContainer(
                                duration: JpMotion.slow,
                                curve: JpMotion.emphasized,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: i <= step.index ? p.brand : p.border,
                                  borderRadius: JpRadius.all(JpRadius.pill),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: JpMotion.base,
                    switchInCurve: JpMotion.emphasized,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(key: ValueKey(step), child: body),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mise en page commune d'une étape : en-tête, contenu défilant, actions
/// fixées en bas (toujours à portée de pouce, au-dessus du clavier).
class SetupStepLayout extends StatelessWidget {
  const SetupStepLayout({
    super.key,
    required this.stepLabel,
    required this.title,
    required this.child,
    this.subtitle,
    this.primary,
    this.secondary,
  });

  final String stepLabel;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.xxl, JpSpacing.gutter, JpSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(stepLabel.toUpperCase(), style: JpTypography.overline.copyWith(color: p.brand)),
                const SizedBox(height: JpSpacing.sm),
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
              ],
            ),
          ),
        ),
        if (primary != null || secondary != null)
          DecoratedBox(
            decoration: BoxDecoration(
              color: p.background,
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.md, JpSpacing.gutter, JpSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?primary,
                  if (secondary != null) ...[const SizedBox(height: JpSpacing.sm), secondary!],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
