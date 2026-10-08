import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/errors/app_failure.dart';
import '../../application/setup_wizard_controller.dart';
import '../../domain/business_templates.dart';
import '../setup_wizard_screen.dart';

class TypeStep extends ConsumerStatefulWidget {
  const TypeStep({super.key});

  @override
  ConsumerState<TypeStep> createState() => _TypeStepState();
}

class _TypeStepState extends ConsumerState<TypeStep> {
  late BusinessTemplate? _template = ref.read(setupWizardProvider).template;
  late Set<String> _selected = {...?_template?.categories};
  bool _saving = false;

  void _choose(BusinessTemplate t) {
    HapticFeedback.selectionClick();
    setState(() {
      _template = t;
      _selected = {...t.categories};
    });
  }

  Future<void> _continue() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(setupWizardProvider.notifier)
          .chooseTemplate(_template!, _template!.categories.where(_selected.contains).toList());
    } on AppFailure catch (f) {
      if (mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final columns = MediaQuery.sizeOf(context).width >= JpBreakpoints.tablet ? 4 : 2;
    return SetupStepLayout(
      stepLabel: 'Étape 1 sur 5',
      title: 'Quel est votre commerce ?',
      subtitle: 'Nous vous proposerons des catégories adaptées. Rien n’est définitif.',
      primary: JpButton(
        label: 'Continuer',
        trailingIcon: Icons.arrow_forward_rounded,
        isLoading: _saving,
        onPressed: _template == null ? null : _continue,
      ),
      secondary: Center(
        child: TextButton(
          onPressed: _saving ? null : ref.read(setupWizardProvider.notifier).next,
          child: const Text('Passer cette étape'),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: JpSpacing.md,
            crossAxisSpacing: JpSpacing.md,
            childAspectRatio: 1.45,
            children: [
              for (final t in BusinessTemplate.all)
                _TypeCard(template: t, selected: _template?.id == t.id, onTap: _saving ? null : () => _choose(t)),
            ],
          ),
          AnimatedSize(
            duration: JpMotion.base,
            curve: JpMotion.emphasized,
            alignment: Alignment.topCenter,
            child: (_template?.categories.isEmpty ?? true)
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: JpSpacing.xxl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Catégories proposées', style: JpTypography.titleSmall.copyWith(color: p.textPrimary)),
                        const SizedBox(height: JpSpacing.xs),
                        Text(
                          'Touchez pour retirer celles qui ne vous concernent pas.',
                          style: JpTypography.bodySmall.copyWith(color: p.textMuted),
                        ),
                        const SizedBox(height: JpSpacing.md),
                        Wrap(
                          spacing: JpSpacing.sm,
                          runSpacing: JpSpacing.sm,
                          children: [
                            for (final c in _template!.categories)
                              FilterChip(
                                label: Text(c),
                                selected: _selected.contains(c),
                                avatar: Icon(
                                  _selected.contains(c) ? Icons.check_rounded : Icons.add_rounded,
                                  size: 18,
                                  color: _selected.contains(c) ? p.brandStrong : p.textMuted,
                                ),
                                onSelected: _saving
                                    ? null
                                    : (v) => setState(() => v ? _selected.add(c) : _selected.remove(c)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.template, required this.selected, required this.onTap});

  final BusinessTemplate template;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      selected: selected,
      child: AnimatedContainer(
        duration: JpMotion.base,
        curve: JpMotion.emphasized,
        decoration: BoxDecoration(
          color: selected ? p.brandSoft : p.surface,
          borderRadius: JpRadius.all(JpRadius.lg),
          border: Border.all(color: selected ? p.brand : p.border, width: selected ? 1.6 : 1),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: JpRadius.all(JpRadius.lg),
            child: Padding(
              padding: const EdgeInsets.all(JpSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(template.icon, color: selected ? p.brandStrong : p.textSecondary, size: JpSize.iconLg),
                      const Spacer(),
                      AnimatedOpacity(
                        opacity: selected ? 1 : 0,
                        duration: JpMotion.fast,
                        child: Icon(Icons.check_circle_rounded, color: p.brand, size: 20),
                      ),
                    ],
                  ),
                  Text(
                    template.label,
                    maxLines: 2,
                    style: JpTypography.label.copyWith(color: selected ? p.brandStrong : p.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
