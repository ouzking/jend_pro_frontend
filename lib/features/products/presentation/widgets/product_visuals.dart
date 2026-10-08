import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/formatting/formatters.dart';
import '../../data/products_repository.dart';
import '../../domain/catalog_models.dart';

/// Vignette produit : photo (cache disque, décodée à la taille affichée)
/// ou monogramme de l'article.
class ProductThumb extends ConsumerWidget {
  const ProductThumb({super.key, required this.name, this.imagePath, this.size = 52, this.radius = JpRadius.md});

  final String name;
  final String? imagePath;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.brandSoft, borderRadius: JpRadius.all(radius)),
      child: Text(
        Formatters.productMonogram(name),
        style: JpTypography.label.copyWith(color: p.brandStrong, fontSize: size * 0.3),
      ),
    );
    if (imagePath == null) return ExcludeSemantics(child: fallback);
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: JpRadius.all(radius),
      child: CachedNetworkImage(
        imageUrl: ref.read(productsRepositoryProvider).publicImageUrl(imagePath!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: cacheSize,
        fadeInDuration: JpMotion.fast,
        placeholder: (_, _) => Container(width: size, height: size, color: p.skeletonBase),
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

/// Pastille d'état de stock.
class StockBadge extends StatelessWidget {
  const StockBadge({super.key, required this.product, this.compact = false});

  final Product product;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final q = product.stockQuantity;
    final qty = q == null ? '' : Formatters.quantity(q);
    return switch (product.stockLevel) {
      StockLevel.notTracked => JpBadge(label: compact ? 'Service' : 'Non stocké', tone: JpTone.neutral),
      StockLevel.unknown => const JpBadge(label: 'Stock à saisir', tone: JpTone.info),
      StockLevel.out => const JpBadge(label: 'Rupture', tone: JpTone.danger, dot: true),
      StockLevel.low => JpBadge(label: compact ? qty : 'Faible · $qty', tone: JpTone.warning, dot: true),
      StockLevel.ok => JpBadge(label: compact ? qty : '$qty en stock', tone: JpTone.success, dot: true),
    };
  }
}

/// Ligne de la liste du catalogue.
class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, required this.currency, this.onTap});

  final Product product;
  final String currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final meta = [?product.categoryName, 'par ${product.unit}'].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.md),
        child: Row(
          children: [
            Hero(
              tag: 'product-${product.id}',
              child: ProductThumb(name: product.name, imagePath: product.imagePath),
            ),
            const SizedBox(width: JpSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: JpTypography.bodyStrong.copyWith(
                      color: product.archived ? p.textMuted : p.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: JpSpacing.xxs),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: JpTypography.caption.copyWith(color: p.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: JpSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                JpAmount(product.salePrice, currency: currency, style: JpTypography.label),
                const SizedBox(height: JpSpacing.xs),
                if (product.archived) const JpBadge(label: 'Archivé') else StockBadge(product: product, compact: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Squelette d'une ligne produit.
class ProductTileSkeleton extends StatelessWidget {
  const ProductTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.md),
      child: Row(
        children: [
          JpSkeleton(width: 52, height: 52, radius: JpRadius.md),
          SizedBox(width: JpSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(widthFactor: 0.7, child: JpSkeleton()),
                SizedBox(height: JpSpacing.sm),
                FractionallySizedBox(widthFactor: 0.4, child: JpSkeleton(height: 10)),
              ],
            ),
          ),
          SizedBox(width: JpSpacing.md),
          JpSkeleton(width: 70),
        ],
      ),
    );
  }
}
