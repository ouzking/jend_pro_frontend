import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/formatting/formatters.dart';
import '../../../../core/voice/voice_listen_sheet.dart';
import '../../../business/application/workspace_controller.dart';
import '../../application/pos_providers.dart';
import '../../application/voice_order.dart';
import '../../domain/sale_models.dart';

/// Issue de la vérification d'une commande dictée.
sealed class VoiceOrderOutcome {
  const VoiceOrderOutcome();
}

class VoiceOrderAdded extends VoiceOrderOutcome {
  const VoiceOrderAdded(this.count);

  final int count;
}

class VoiceOrderRedo extends VoiceOrderOutcome {
  const VoiceOrderRedo();
}

/// Article non trouvé : l'utilisateur veut le chercher à la main.
class VoiceOrderSearch extends VoiceOrderOutcome {
  const VoiceOrderSearch(this.text);

  final String text;
}

/// Dictée d'une vente : écoute → vérification → panier. Renvoie le texte à
/// mettre dans la recherche si l'utilisateur choisit « Chercher ».
Future<String?> dictateSale(BuildContext context) async {
  while (context.mounted) {
    final said = await listenToVoice(
      context,
      title: 'Dictez la vente',
      example: 'deux sacs de riz et une huile 5 litres',
    );
    if (said == null || !context.mounted) return null;
    final outcome = await JpOverlays.listSheet<VoiceOrderOutcome>(
      context,
      title: 'Vérifiez avant d’ajouter',
      child: VoiceOrderReview(transcript: said),
    );
    if (!context.mounted) return null;
    switch (outcome) {
      case VoiceOrderAdded(:final count):
        JpOverlays.toast(
          context,
          count == 1 ? '1 article ajouté au panier.' : '$count articles ajoutés au panier.',
          tone: JpTone.success,
        );
        return null;
      case VoiceOrderSearch(:final text):
        return text;
      case VoiceOrderRedo():
        continue;
      case null:
        return null;
    }
  }
  return null;
}

class VoiceOrderReview extends ConsumerStatefulWidget {
  const VoiceOrderReview({super.key, required this.transcript});

  final String transcript;

  @override
  ConsumerState<VoiceOrderReview> createState() => _VoiceOrderReviewState();
}

class _VoiceOrderReviewState extends ConsumerState<VoiceOrderReview> {
  List<VoiceLine>? _lines;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final lines = await ref.read(voiceOrderResolverProvider).resolve(widget.transcript);
      if (mounted) setState(() => _lines = lines);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  void _update(int i, VoiceLine line) => setState(() => _lines = [..._lines!]..[i] = line);

  void _remove(int i) => setState(() => _lines = [..._lines!]..removeAt(i));

  Future<void> _choose(int i) async {
    final line = _lines![i];
    final options = [?line.product, ...line.alternatives];
    final picked = await showModalBottomSheet<SellableProduct>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: JpSpacing.md),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, 0, JpSpacing.gutter, JpSpacing.sm),
              child: Text('« ${line.item.raw} »', style: JpTypography.title),
            ),
            for (final p in options)
              ListTile(
                title: Text(p.name),
                subtitle: Text(Formatters.money(p.salePrice)),
                trailing: p.id == line.product?.id ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.of(sheet).pop(p),
              ),
          ],
        ),
      ),
    );
    if (picked != null) _update(i, line.copyWith(product: picked));
  }

  void _add() {
    final found = _lines!.where((l) => l.found).toList();
    final cart = ref.read(cartProvider.notifier);
    for (final l in found) {
      cart.add(l.product!, quantity: l.quantity);
    }
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(VoiceOrderAdded(found.length));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final lines = _lines;
    final found = lines?.where((l) => l.found).length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Vous avez dit : « ${widget.transcript} »',
          style: JpTypography.bodySmall.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: JpSpacing.md),
        Expanded(
          child: switch ((lines, _error)) {
            (_, final String error) => Center(
              child: JpBanner(message: error, tone: JpTone.danger),
            ),
            (null, _) => const Center(child: CircularProgressIndicator()),
            (final List<VoiceLine> l, _) when l.isEmpty => Center(
              child: Text(
                'Aucun article compris. Redites la vente en donnant la quantité puis le nom : « deux riz, une huile ».',
                textAlign: TextAlign.center,
                style: JpTypography.body.copyWith(color: p.textMuted),
              ),
            ),
            (final List<VoiceLine> l, _) => ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: l.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: p.border),
              itemBuilder: (context, i) => _LineTile(
                line: l[i],
                currency: currency,
                onQuantity: (q) => _update(i, l[i].copyWith(quantity: q)),
                onChoose: l[i].alternatives.isEmpty && l[i].found ? null : () => _choose(i),
                onRemove: () => _remove(i),
                onSearch: () => Navigator.of(context).pop(VoiceOrderSearch(l[i].item.query)),
              ),
            ),
          },
        ),
        const SizedBox(height: JpSpacing.md),
        JpButton(
          label: found <= 1 ? 'Ajouter au panier' : 'Ajouter $found articles au panier',
          icon: Icons.add_shopping_cart_rounded,
          onPressed: found == 0 ? null : _add,
        ),
        const SizedBox(height: JpSpacing.sm),
        JpButton.ghost(
          label: 'Redire',
          icon: Icons.mic_rounded,
          onPressed: () => Navigator.of(context).pop(const VoiceOrderRedo()),
        ),
      ],
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.currency,
    required this.onQuantity,
    required this.onRemove,
    required this.onSearch,
    this.onChoose,
  });

  final VoiceLine line;
  final String currency;
  final ValueChanged<num> onQuantity;
  final VoidCallback onRemove;
  final VoidCallback onSearch;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final product = line.product;

    if (product == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: JpSpacing.md),
        child: Row(
          children: [
            Icon(Icons.help_outline_rounded, color: p.warning),
            const SizedBox(width: JpSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('« ${line.item.raw} »', style: JpTypography.bodyStrong.copyWith(color: p.textPrimary)),
                  Text(
                    line.alternatives.isEmpty ? 'Article introuvable dans le catalogue' : 'Article à préciser',
                    style: JpTypography.caption.copyWith(color: p.warning),
                  ),
                ],
              ),
            ),
            if (line.alternatives.isNotEmpty)
              TextButton(onPressed: onChoose, child: const Text('Choisir'))
            else
              TextButton(onPressed: onSearch, child: const Text('Chercher')),
            IconButton(tooltip: 'Retirer', icon: const Icon(Icons.close_rounded), onPressed: onRemove),
          ],
        ),
      );
    }

    final step = product.allowsFractional ? 0.5 : 1;
    final min = product.allowsFractional ? 0.5 : 1;
    final lowStock = product.trackStock && product.stockQuantity != null && product.stockQuantity! < line.quantity;
    final notes = [
      if (line.ambiguous) 'Vérifiez l’article',
      if (line.rounded) 'Arrondi : vendu à l’unité',
      if (lowStock) 'Stock : ${Formatters.quantity(product.stockQuantity!)}',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: JpSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onChoose,
              borderRadius: JpRadius.all(JpRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: JpSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
                          ),
                        ),
                        if (onChoose != null) Icon(Icons.unfold_more_rounded, size: 18, color: p.textMuted),
                      ],
                    ),
                    Text(
                      Formatters.money((product.salePrice * line.quantity).round(), currency: currency),
                      style: JpTypography.caption.copyWith(color: p.textSecondary),
                    ),
                    if (notes.isNotEmpty)
                      Text(
                        notes.join(' · '),
                        style: JpTypography.caption.copyWith(
                          color: line.ambiguous || lowStock ? p.warning : p.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Moins',
            icon: const Icon(Icons.remove_circle_outline_rounded),
            onPressed: line.quantity - step < min ? onRemove : () => onQuantity(line.quantity - step),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 28),
            child: Text(
              Formatters.quantity(line.quantity),
              textAlign: TextAlign.center,
              style: JpTypography.numeric(JpTypography.bodyStrong),
            ),
          ),
          IconButton(
            tooltip: 'Plus',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => onQuantity(line.quantity + step),
          ),
        ],
      ),
    );
  }
}
