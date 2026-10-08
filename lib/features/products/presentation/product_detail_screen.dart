import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/media/image_picking.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../application/catalog_providers.dart';
import '../domain/catalog_models.dart';
import 'widgets/product_visuals.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productDetailProvider(productId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produit'),
        actions: [
          if (product.value case final p?
              when ref.watch(permissionsProvider).can(Permission.productsUpdate) && !p.archived)
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push(Routes.productEdit(p.id)),
            ),
        ],
      ),
      body: JpAsyncView<Product>(
        value: product,
        onRetry: () => ref.invalidate(productDetailProvider(productId)),
        loading: const _DetailSkeleton(),
        data: (p) => _DetailBody(product: p),
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.product});

  final Product product;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  bool _busy = false;

  Product get product => widget.product;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) JpOverlays.toast(context, success, tone: JpTone.success);
    } on AppFailure catch (f) {
      if (mounted) {
        JpOverlays.toast(
          context,
          f.code == 'PLAN_LIMIT_REACHED' ? 'Limite de produits actifs de votre abonnement atteinte.' : f.message,
          tone: JpTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePhoto() async {
    final image = await pickImage(context, maxBytes: 2 * 1024 * 1024, title: 'Photo du produit');
    if (image == null || !mounted) return;
    await _run(
      () => ref.read(productActionsProvider).uploadImage(product, image.bytes, image.mimeType),
      'Photo mise à jour.',
    );
  }

  Future<void> _toggleArchive() async {
    final archiving = !product.archived;
    final ok = await JpOverlays.confirm(
      context,
      title: archiving ? 'Archiver ce produit ?' : 'Réactiver ce produit ?',
      message: archiving
          ? 'Il ne sera plus proposé à la vente. Son historique (ventes, stock) est conservé et vous pourrez le réactiver.'
          : 'Il sera de nouveau proposé à la vente.',
      confirmLabel: archiving ? 'Archiver' : 'Réactiver',
      destructive: archiving,
      icon: archiving ? Icons.archive_outlined : Icons.unarchive_outlined,
    );
    if (!ok) return;
    await _run(
      () => ref.read(productActionsProvider).setArchived(product, archived: archiving),
      archiving ? 'Produit archivé.' : 'Produit réactivé.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final permissions = ref.watch(permissionsProvider);
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final canUpdate = permissions.can(Permission.productsUpdate);
    final canArchive = permissions.can(Permission.productsDelete);
    final margin = product.unitMargin;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(productDetailProvider(product.id).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, JpSpacing.huge),
        children: [
          JpConstrained(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Hero(
                          tag: 'product-${product.id}',
                          child: ProductThumb(
                            name: product.name,
                            imagePath: product.imagePath,
                            size: 96,
                            radius: JpRadius.xl,
                          ),
                        ),
                        if (canUpdate && !product.archived)
                          Positioned(
                            right: -8,
                            bottom: -8,
                            child: Material(
                              color: p.surface,
                              shape: CircleBorder(side: BorderSide(color: p.border)),
                              child: IconButton(
                                tooltip: 'Changer la photo',
                                iconSize: 18,
                                constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                                padding: EdgeInsets.zero,
                                icon: Icon(Icons.photo_camera_outlined, color: p.brandStrong),
                                onPressed: _busy ? null : _changePhoto,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: JpSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.name, style: JpTypography.title.copyWith(color: p.textPrimary)),
                          const SizedBox(height: JpSpacing.sm),
                          Wrap(
                            spacing: JpSpacing.sm,
                            runSpacing: JpSpacing.xs,
                            children: [
                              if (product.archived) const JpBadge(label: 'Archivé', icon: Icons.archive_outlined),
                              if (product.categoryName != null)
                                JpBadge(label: product.categoryName!, tone: JpTone.brand),
                              if (!product.archived) StockBadge(product: product),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: JpSpacing.lg),
                    child: LinearProgressIndicator(),
                  ),
                const SizedBox(height: JpSpacing.xl),
                JpCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: _Figure(
                          label: 'Prix de vente',
                          value: JpAmount(product.salePrice, currency: currency, style: JpTypography.title),
                          caption: 'par ${product.unit}',
                        ),
                      ),
                      if (product.costPrice != null) ...[
                        Container(width: 1, height: 48, color: p.border),
                        const SizedBox(width: JpSpacing.lg),
                        Expanded(
                          child: _Figure(
                            label: 'Coût d’achat',
                            value: JpAmount(product.costPrice!, currency: currency, style: JpTypography.title),
                            caption: margin == null
                                ? 'Non renseigné'
                                : 'Marge ${Formatters.money(margin, currency: currency)}'
                                      '${product.salePrice > 0 ? ' · ${(margin / product.salePrice * 100).round()} %' : ''}',
                            captionColor: margin != null && margin < 0 ? p.danger : null,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (product.trackStock) ...[
                  const SizedBox(height: JpSpacing.md),
                  JpCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: _Figure(
                            label: 'Stock disponible',
                            value: Text(
                              product.stockQuantity == null
                                  ? '—'
                                  : '${Formatters.quantity(product.stockQuantity!)} ${product.unit}',
                              style: JpTypography.numeric(JpTypography.title).copyWith(color: p.textPrimary),
                            ),
                            caption: product.stockQuantity == null ? 'Stock pas encore saisi' : 'Tous emplacements',
                          ),
                        ),
                        Container(width: 1, height: 48, color: p.border),
                        const SizedBox(width: JpSpacing.lg),
                        Expanded(
                          child: _Figure(
                            label: 'Seuil d’alerte',
                            value: Text(
                              product.minStockLevel > 0 ? Formatters.quantity(product.minStockLevel) : 'Aucun',
                              style: JpTypography.numeric(JpTypography.title).copyWith(color: p.textPrimary),
                            ),
                            caption: 'Alerte « stock faible »',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (product.trackStock && permissions.can(Permission.inventoryRead)) ...[
                  const SizedBox(height: JpSpacing.sm),
                  JpButton.ghost(
                    label: 'Gérer le stock et voir l’historique',
                    icon: Icons.stacked_bar_chart_rounded,
                    expand: true,
                    onPressed: () => context.push(Routes.productStock(product.id)),
                  ),
                ],
                if (product.description?.isNotEmpty ?? false) ...[
                  const SizedBox(height: JpSpacing.xl),
                  const JpSectionHeader(title: 'Description'),
                  const SizedBox(height: JpSpacing.xs),
                  Text(product.description!, style: JpTypography.body.copyWith(color: p.textSecondary)),
                ],
                const SizedBox(height: JpSpacing.xl),
                const JpSectionHeader(title: 'Informations'),
                const SizedBox(height: JpSpacing.sm),
                JpCard(
                  padding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.xs),
                  child: Column(
                    children: [
                      _InfoRow(label: 'Code-barres', value: product.barcode),
                      _InfoRow(label: 'SKU', value: product.sku),
                      _InfoRow(label: 'Unité', value: product.unit),
                      _InfoRow(
                        label: 'Vente au détail',
                        value: product.allowsFractionalQuantity ? 'Oui (décimales)' : 'Non',
                      ),
                      _InfoRow(
                        label: 'Suivi du stock',
                        value: product.trackStock ? 'Oui' : 'Non (service)',
                        last: true,
                      ),
                    ],
                  ),
                ),
                if (canArchive) ...[
                  const SizedBox(height: JpSpacing.xxl),
                  JpButton.outline(
                    label: product.archived ? 'Réactiver le produit' : 'Archiver le produit',
                    icon: product.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                    onPressed: _busy ? null : _toggleArchive,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.caption, this.captionColor});

  final String label;
  final Widget value;
  final String? caption;
  final Color? captionColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: JpTypography.caption.copyWith(color: p.textSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: JpSpacing.xs),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
        if (caption != null)
          Text(caption!, maxLines: 2, style: JpTypography.caption.copyWith(color: captionColor ?? p.textMuted)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.last = false});

  final String label;
  final String? value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: JpSpacing.md),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: JpTypography.body.copyWith(color: p.textSecondary)),
          ),
          Flexible(
            child: Text(
              value?.isNotEmpty ?? false ? value! : '—',
              textAlign: TextAlign.end,
              style: JpTypography.bodyStrong.copyWith(color: value == null ? p.textMuted : p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return const JpShimmer(
      child: Padding(
        padding: EdgeInsets.all(JpSpacing.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                JpSkeleton(width: 96, height: 96, radius: JpRadius.xl),
                SizedBox(width: JpSpacing.lg),
                Expanded(child: JpSkeleton(height: 24)),
              ],
            ),
            SizedBox(height: JpSpacing.xl),
            JpSkeleton(height: 90, radius: JpRadius.lg),
            SizedBox(height: JpSpacing.md),
            JpSkeleton(height: 90, radius: JpRadius.lg),
            SizedBox(height: JpSpacing.xl),
            JpSkeleton(height: 220, radius: JpRadius.lg),
          ],
        ),
      ),
    );
  }
}
