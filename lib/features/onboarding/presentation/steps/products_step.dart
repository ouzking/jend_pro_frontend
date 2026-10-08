import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/permissions/permission.dart';
import '../../../business/application/workspace_controller.dart';
import '../../../products/domain/catalog_models.dart';
import '../../../products/presentation/widgets/product_quick_form.dart';
import '../../application/setup_wizard_controller.dart';
import '../../domain/business_templates.dart';
import '../setup_wizard_screen.dart';

class ProductsStep extends ConsumerWidget {
  const ProductsStep({super.key});

  Future<void> _openForm(BuildContext context, WidgetRef ref) {
    final state = ref.read(setupWizardProvider);
    final permissions = ref.read(permissionsProvider);
    final template = state.template ?? BusinessTemplate.all.last;
    return JpOverlays.sheet<void>(
      context,
      title: 'Nouveau produit',
      child: Builder(
        builder: (sheetContext) => ProductQuickForm(
          units: template.units,
          categories: state.categories,
          nameHint: template.example == null ? null : 'Ex. ${template.example}',
          canSetCost: permissions.can(Permission.productsReadCost) && permissions.can(Permission.productsUpdate),
          onSubmit: (product) async {
            final created = await ref.read(setupWizardProvider.notifier).addProduct(product);
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop();
              JpOverlays.toast(context, '« ${created.name} » ajouté.', tone: JpTone.success);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final products = ref.watch(setupWizardProvider.select((s) => s.products));
    final categories = ref.watch(setupWizardProvider.select((s) => s.categories));
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final canCreate = ref.watch(permissionsProvider).can(Permission.productsCreate);

    return SetupStepLayout(
      stepLabel: 'Étape 4 sur 5',
      title: 'Vos premiers produits',
      subtitle: 'Ajoutez quelques articles phares pour commencer à vendre tout de suite.',
      primary: JpButton(
        label: products.isEmpty ? 'Plus tard' : 'Continuer',
        variant: products.isEmpty ? JpButtonVariant.secondary : JpButtonVariant.primary,
        trailingIcon: Icons.arrow_forward_rounded,
        onPressed: ref.read(setupWizardProvider.notifier).next,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (products.isEmpty)
            JpCard(
              color: p.surfaceMuted,
              child: Column(
                children: [
                  const JpIllustratedIcon(icon: Icons.inventory_2_outlined, size: 72),
                  const SizedBox(height: JpSpacing.md),
                  Text('Aucun produit pour l’instant', style: JpTypography.bodyStrong.copyWith(color: p.textPrimary)),
                  const SizedBox(height: JpSpacing.xs),
                  Text(
                    'Nom, prix et unité suffisent. Vous compléterez le reste plus tard.',
                    textAlign: TextAlign.center,
                    style: JpTypography.bodySmall.copyWith(color: p.textMuted),
                  ),
                ],
              ),
            )
          else
            for (final product in products) ...[
              _ProductRow(
                product: product,
                currency: currency,
                category: categories.where((c) => c.id == product.categoryId).firstOrNull?.name,
              ),
              const SizedBox(height: JpSpacing.sm),
            ],
          const SizedBox(height: JpSpacing.lg),
          if (canCreate)
            JpButton.outline(
              label: products.isEmpty ? 'Ajouter un produit' : 'Ajouter un autre produit',
              icon: Icons.add_rounded,
              onPressed: () => _openForm(context, ref),
            )
          else
            const JpBanner(message: 'Votre rôle ne permet pas de créer des produits.', tone: JpTone.warning),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.currency, this.category});

  final ProductSummary product;
  final String currency;
  final String? category;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return JpCard(
      padding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.md),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: p.brandSoft, borderRadius: JpRadius.all(JpRadius.sm)),
            child: Icon(
              product.trackStock ? Icons.inventory_2_outlined : Icons.design_services_outlined,
              color: p.brandStrong,
              size: 20,
            ),
          ),
          const SizedBox(width: JpSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
                ),
                Text(
                  [category, 'par ${product.unit}', if (!product.trackStock) 'non stocké'].nonNulls.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JpTypography.bodySmall.copyWith(color: p.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: JpSpacing.sm),
          JpAmount(product.salePrice, currency: currency),
        ],
      ),
    );
  }
}
