import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/storage/preferences.dart';
import '../../../core/voice/voice_order_parser.dart';
import '../../business/application/workspace_controller.dart';
import '../data/sales_repository.dart';
import '../domain/sale_models.dart';

/// Ligne proposée à partir d'une commande dictée (à vérifier avant d'aller au
/// panier : la voix ne fait que préremplir, le serveur reste seul juge).
class VoiceLine {
  const VoiceLine({
    required this.item,
    required this.alternatives,
    required this.quantity,
    this.product,
    this.rounded = false,
    this.ambiguous = false,
  });

  final VoiceItem item;
  final SellableProduct? product;

  /// Autres articles proches (pour corriger un mauvais choix).
  final List<SellableProduct> alternatives;
  final num quantity;

  /// Quantité arrondie : l'article se vend uniquement à l'unité.
  final bool rounded;
  final bool ambiguous;

  bool get found => product != null;

  VoiceLine copyWith({SellableProduct? product, num? quantity}) {
    final p = product ?? this.product;
    final q = quantity ?? this.quantity;
    return VoiceLine(
      item: item,
      alternatives: alternatives,
      product: p,
      quantity: p != null && !p.allowsFractional ? q.round().clamp(1, 1 << 31) : q,
      rounded: rounded && quantity == null,
      ambiguous: ambiguous && product == null,
    );
  }
}

final voiceOrderResolverProvider = Provider<VoiceOrderResolver>(VoiceOrderResolver.new);

class VoiceOrderResolver {
  VoiceOrderResolver(this._ref);

  final Ref _ref;

  /// Comprend [transcript] et propose une ligne par article demandé.
  Future<List<VoiceLine>> resolve(String transcript) async {
    final items = VoiceOrderParser.parse(transcript);
    if (items.isEmpty) return const [];
    final businessId = _ref.read(activeBusinessProvider)!.businessId;
    final repo = _ref.read(salesRepositoryProvider);
    final (catalog, online) = await _catalog(businessId);

    final lines = <VoiceLine>[];
    for (final item in items) {
      var pool = catalog;
      var m = _match(item, pool);
      // Catalogue de plus de 200 articles : recherche ciblée sur le serveur.
      if (m.best == null && online) {
        // Mot le plus long, sans pluriel : « ciments » doit trouver « Ciment ».
        final keyword = VoiceOrderParser.stem(([...item.words]..sort((a, b) => b.length.compareTo(a.length))).first);
        try {
          pool = await repo.fetchSellable(businessId, query: keyword, limit: 30);
          m = _match(item, pool);
        } on AppFailure {
          // Hors ligne entre-temps : on garde le résultat local.
        }
      }
      final byId = {for (final p in pool) p.id: p};
      final best = m.best == null ? null : byId[m.best!.id];
      final alternatives = [
        for (final (c, _) in m.ranked)
          if (c.id != best?.id && byId[c.id] != null) byId[c.id]!,
      ];
      final fractional = item.quantity != item.quantity.roundToDouble();
      final rounded = best != null && !best.allowsFractional && fractional;
      lines.add(
        VoiceLine(
          item: item,
          product: best,
          alternatives: alternatives,
          quantity: rounded ? item.quantity.round().clamp(1, 1 << 31) : item.quantity,
          rounded: rounded,
          ambiguous: m.ambiguous,
        ),
      );
    }
    return lines;
  }

  VoiceMatch _match(VoiceItem item, List<SellableProduct> pool) =>
      VoiceOrderParser.match(item, [for (final p in pool) VoiceCandidate(id: p.id, name: p.name)]);

  /// Catalogue vendable complet ; à défaut de réseau, la copie gardée par la
  /// caisse sur le téléphone.
  Future<(List<SellableProduct>, bool)> _catalog(String businessId) async {
    try {
      return (await _ref.read(salesRepositoryProvider).fetchSellable(businessId), true);
    } on AppFailure catch (f) {
      if (f.kind != FailureKind.network) rethrow;
      final raw = _ref.read(sharedPreferencesProvider).getString('pos_catalog:$businessId');
      if (raw == null) rethrow;
      return ((jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(SellableProduct.fromRow).toList(), false);
    }
  }
}
