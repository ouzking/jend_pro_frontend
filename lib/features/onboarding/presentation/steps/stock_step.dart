import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/formatting/formatters.dart';
import '../../../../core/formatting/input_formatters.dart';
import '../../../../core/permissions/permission.dart';
import '../../../business/application/workspace_controller.dart';
import '../../../products/domain/catalog_models.dart';
import '../../application/setup_wizard_controller.dart';
import '../setup_wizard_screen.dart';

/// Stock d'ouverture des produits créés (`adjust_stock` type `INITIAL`).
class StockStep extends ConsumerStatefulWidget {
  const StockStep({super.key});

  @override
  ConsumerState<StockStep> createState() => _StockStepState();
}

class _StockStepState extends ConsumerState<StockStep> {
  final _controllers = <String, TextEditingController>{};
  bool _saving = false;
  String? _error;

  TextEditingController _controllerFor(String productId) =>
      _controllers.putIfAbsent(productId, TextEditingController.new);

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(setupWizardProvider.notifier).saveInitialStock({
        for (final e in _controllers.entries) e.key: ?QuantityInputFormatter.parse(e.value.text),
      });
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(setupWizardProvider.select((s) => s.stockedProducts));
    final saved = ref.watch(setupWizardProvider.select((s) => s.initialStock));
    final canAdjust = ref.watch(permissionsProvider).can(Permission.inventoryAdjust);

    return SetupStepLayout(
      stepLabel: 'Étape 5 sur 5',
      title: 'Stock de départ',
      subtitle: 'Combien en avez-vous aujourd’hui en boutique ? Laissez vide si vous ne savez pas encore.',
      primary: JpButton(
        label: canAdjust ? 'Enregistrer le stock' : 'Continuer',
        trailingIcon: Icons.arrow_forward_rounded,
        isLoading: _saving,
        onPressed: canAdjust ? _save : ref.read(setupWizardProvider.notifier).next,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormErrorBanner(message: _error),
          if (!canAdjust)
            const JpBanner(
              message: 'Votre rôle ne permet pas de saisir le stock. Un gérant pourra le faire.',
              tone: JpTone.warning,
            ),
          for (final product in products) ...[
            _StockRow(
              product: product,
              controller: _controllerFor(product.id),
              savedQuantity: saved[product.id],
              enabled: canAdjust && !_saving,
            ),
            const SizedBox(height: JpSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({required this.product, required this.controller, required this.enabled, this.savedQuantity});

  final ProductSummary product;
  final TextEditingController controller;
  final bool enabled;
  final num? savedQuantity;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return JpCard(
      padding: const EdgeInsets.fromLTRB(JpSpacing.lg, JpSpacing.sm, JpSpacing.sm, JpSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
            ),
          ),
          const SizedBox(width: JpSpacing.md),
          if (savedQuantity != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: JpSpacing.md, horizontal: JpSpacing.sm),
              child: JpBadge(
                label: '${Formatters.quantity(savedQuantity!)} ${product.unit}',
                tone: JpTone.success,
                icon: Icons.check_rounded,
              ),
            )
          else
            SizedBox(
              width: 132,
              child: TextField(
                controller: controller,
                enabled: enabled,
                textAlign: TextAlign.end,
                keyboardType: TextInputType.numberWithOptions(decimal: product.allowsFractionalQuantity),
                inputFormatters: [QuantityInputFormatter(allowDecimals: product.allowsFractionalQuantity)],
                style: JpTypography.numeric(JpTypography.bodyStrong).copyWith(color: p.textPrimary),
                decoration: InputDecoration(
                  hintText: '0',
                  isDense: true,
                  suffixText: product.unit,
                  contentPadding: const EdgeInsets.symmetric(horizontal: JpSpacing.md, vertical: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
