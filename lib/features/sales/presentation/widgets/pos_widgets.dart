import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/formatting/formatters.dart';
import '../../../../core/formatting/input_formatters.dart';
import '../../../products/presentation/widgets/product_visuals.dart';
import '../../application/pos_providers.dart';
import '../../domain/sale_models.dart';

/// Carte produit de la caisse : un toucher = +1 au panier.
class PosProductCard extends StatelessWidget {
  const PosProductCard({
    super.key,
    required this.product,
    required this.inCart,
    required this.favorite,
    required this.currency,
    required this.onTap,
    required this.onLongPress,
  });

  final SellableProduct product;
  final num inCart;
  final bool favorite;
  final String currency;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final out = product.trackStock && (product.stockQuantity ?? 0) <= 0;
    final selected = inCart > 0;
    return Semantics(
      button: true,
      label:
          '${product.name}, ${Formatters.money(product.salePrice, currency: currency)}'
          '${selected ? ', ${Formatters.quantity(inCart)} dans le panier' : ''}',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: JpMotion.fast,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: JpRadius.all(JpRadius.lg),
          border: Border.all(color: selected ? p.brand : p.border, width: selected ? 1.6 : 1),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: JpRadius.all(JpRadius.lg),
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            onLongPress: () {
              HapticFeedback.mediumImpact();
              onLongPress();
            },
            child: Padding(
              padding: const EdgeInsets.all(JpSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProductThumb(name: product.name, imagePath: product.imagePath, size: 44, radius: JpRadius.sm),
                      const Spacer(),
                      if (selected)
                        TweenAnimationBuilder<double>(
                          key: ValueKey(inCart),
                          tween: Tween(begin: 1.35, end: 1),
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutBack,
                          builder: (_, s, child) => Transform.scale(scale: s, child: child),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: JpSpacing.sm, vertical: 2),
                            decoration: BoxDecoration(color: p.brand, borderRadius: JpRadius.all(JpRadius.pill)),
                            child: Text(
                              '×${Formatters.quantity(inCart)}',
                              style: JpTypography.caption.copyWith(color: p.textOnBrand, fontWeight: FontWeight.w700),
                            ),
                          ),
                        )
                      else if (favorite)
                        Icon(Icons.star_rounded, size: 18, color: p.accent),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: JpTypography.label.copyWith(color: p.textPrimary, height: 1.2),
                  ),
                  const SizedBox(height: JpSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: JpAmount(product.salePrice, currency: currency, style: JpTypography.label),
                      ),
                      if (out)
                        Text(
                          'Rupture',
                          style: JpTypography.caption.copyWith(color: p.danger, fontWeight: FontWeight.w600),
                        )
                      else if (product.trackStock && product.stockQuantity != null)
                        Text(
                          Formatters.quantity(product.stockQuantity!),
                          style: JpTypography.caption.copyWith(color: p.textMuted),
                        ),
                    ],
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

/// Saisie d'une quantité précise (vente au poids, grandes quantités).
Future<num?> askQuantity(BuildContext context, SellableProduct product, {num? initial}) {
  final controller = TextEditingController(text: initial == null ? '' : Formatters.quantity(initial));
  return JpOverlays.sheet<num>(
    context,
    title: 'Quantité',
    subtitle: product.name,
    child: Builder(
      builder: (sheet) {
        void done() {
          final q = QuantityInputFormatter.parse(controller.text);
          if (q != null && q > 0) Navigator.of(sheet).pop(q);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            JpTextField(
              controller: controller,
              autofocus: true,
              hint: '0',
              suffixText: product.unit,
              keyboardType: TextInputType.numberWithOptions(decimal: product.allowsFractional),
              inputFormatters: [QuantityInputFormatter(allowDecimals: product.allowsFractional)],
              onSubmitted: (_) => done(),
            ),
            const SizedBox(height: JpSpacing.lg),
            JpButton(label: 'Valider', onPressed: done),
          ],
        );
      },
    ),
  );
}

/// Bannière « ventes en attente » (hors ligne) avec synchronisation.
class PendingSalesBanner extends ConsumerStatefulWidget {
  const PendingSalesBanner({super.key});

  @override
  ConsumerState<PendingSalesBanner> createState() => _PendingSalesBannerState();
}

class _PendingSalesBannerState extends ConsumerState<PendingSalesBanner> {
  bool _syncing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final count = await ref.read(pendingSalesProvider.notifier).sync();
    if (!mounted) return;
    setState(() => _syncing = false);
    final left = ref.read(pendingSalesProvider);
    JpOverlays.toast(
      context,
      count > 0
          ? '$count vente${count > 1 ? 's' : ''} synchronisée${count > 1 ? 's' : ''}.'
          : left.any((s) => s.blocked)
          ? 'Certaines ventes ont été refusées : vérifiez-les.'
          : 'Toujours hors ligne. Nouvel essai plus tard.',
      tone: count > 0 ? JpTone.success : JpTone.warning,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingSalesProvider);
    if (pending.isEmpty) return const SizedBox.shrink();
    final blocked = pending.where((s) => s.blocked).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, 0, JpSpacing.gutter, JpSpacing.sm),
      child: JpBanner(
        tone: blocked > 0 ? JpTone.danger : JpTone.warning,
        icon: Icons.cloud_off_rounded,
        message: blocked > 0
            ? '$blocked vente${blocked > 1 ? 's' : ''} refusée${blocked > 1 ? 's' : ''} à la synchronisation.'
            : '${pending.length} vente${pending.length > 1 ? 's' : ''} en attente d’envoi.',
        actionLabel: _syncing ? '…' : (blocked > 0 ? 'Voir' : 'Envoyer'),
        onAction: _syncing ? null : (blocked > 0 ? () => showPendingSalesSheet(context) : _sync),
      ),
    );
  }
}

/// Détail des ventes en attente : réessayer ou abandonner une vente refusée.
Future<void> showPendingSalesSheet(BuildContext context) => JpOverlays.sheet<void>(
  context,
  title: 'Ventes en attente',
  subtitle: 'Enregistrées sur ce téléphone, pas encore sur le serveur.',
  child: const _PendingSalesList(),
);

class _PendingSalesList extends ConsumerWidget {
  const _PendingSalesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final pending = ref.watch(pendingSalesProvider);
    final notifier = ref.read(pendingSalesProvider.notifier);
    if (pending.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(JpSpacing.xl),
        child: Text(
          'Tout est synchronisé.',
          textAlign: TextAlign.center,
          style: JpTypography.body.copyWith(color: p.textMuted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in pending)
          Padding(
            padding: const EdgeInsets.only(bottom: JpSpacing.md),
            child: JpCard(
              borderColor: s.blocked ? p.danger.withValues(alpha: 0.4) : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${s.request.items.length} article${s.request.items.length > 1 ? 's' : ''} · ${Formatters.dateTime(s.createdAt)}',
                          style: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
                        ),
                      ),
                      JpAmount(s.total, style: JpTypography.label),
                    ],
                  ),
                  if (s.blocked) ...[
                    const SizedBox(height: JpSpacing.sm),
                    Text(s.lastError!, style: JpTypography.bodySmall.copyWith(color: p.danger)),
                    const SizedBox(height: JpSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: JpButton.outline(
                            label: 'Abandonner',
                            size: JpButtonSize.small,
                            onPressed: () async {
                              final ok = await JpOverlays.confirm(
                                context,
                                title: 'Abandonner cette vente ?',
                                message:
                                    'Elle ne sera jamais enregistrée. Le stock et la caisse ne seront pas modifiés.',
                                confirmLabel: 'Abandonner',
                                destructive: true,
                              );
                              if (ok) await notifier.discard(s);
                            },
                          ),
                        ),
                        const SizedBox(width: JpSpacing.sm),
                        Expanded(
                          child: JpButton(
                            label: 'Réessayer',
                            size: JpButtonSize.small,
                            onPressed: () => notifier.sync(includeBlocked: true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
