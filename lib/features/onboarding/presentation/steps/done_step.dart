import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/design_system/design_system.dart';
import '../../../business/application/workspace_controller.dart';
import '../../application/setup_wizard_controller.dart';

class DoneStep extends ConsumerStatefulWidget {
  const DoneStep({super.key});

  @override
  ConsumerState<DoneStep> createState() => _DoneStepState();
}

class _DoneStepState extends ConsumerState<DoneStep> {
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
  }

  Future<void> _enter() async {
    setState(() => _leaving = true);
    await ref.read(setupWizardProvider.notifier).finish();
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = ref.watch(setupWizardProvider);
    final name = ref.watch(activeBusinessProvider)?.businessName ?? 'Votre commerce';
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Padding(
      padding: const EdgeInsets.all(JpSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: reduceMotion ? 1 : 0.4, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
              child: const JpIllustratedIcon(icon: Icons.check_rounded, tone: JpTone.success, size: 120),
            ),
          ),
          const SizedBox(height: JpSpacing.xxl),
          Text(
            '$name est prêt !',
            textAlign: TextAlign.center,
            style: JpTypography.headline.copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: JpSpacing.sm),
          Text(
            'Vous pouvez enregistrer votre première vente dès maintenant.',
            textAlign: TextAlign.center,
            style: JpTypography.body.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: JpSpacing.xxl),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: JpSpacing.sm,
            runSpacing: JpSpacing.sm,
            children: [
              if (state.categories.isNotEmpty)
                JpBadge(
                  label: '${state.categories.length} catégories',
                  tone: JpTone.brand,
                  icon: Icons.category_outlined,
                ),
              if (state.products.isNotEmpty)
                JpBadge(
                  label: '${state.products.length} produits',
                  tone: JpTone.brand,
                  icon: Icons.inventory_2_outlined,
                ),
              if (state.initialStock.isNotEmpty)
                JpBadge(
                  label: '${state.initialStock.length} stocks initialisés',
                  tone: JpTone.success,
                  icon: Icons.check_rounded,
                ),
            ],
          ),
          const Spacer(flex: 2),
          JpButton(label: 'Découvrir mon tableau de bord', isLoading: _leaving, onPressed: _enter),
        ],
      ),
    );
  }
}
