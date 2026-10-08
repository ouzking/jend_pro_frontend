import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../business/application/workspace_controller.dart';
import '../application/pos_providers.dart';
import '../domain/sale_models.dart';

/// Confirmation après encaissement : l'information utile tout de suite
/// (monnaie à rendre), puis « vente suivante » en un geste.
class SaleCompleteScreen extends ConsumerWidget {
  const SaleCompleteScreen({super.key, required this.outcome, this.customer});

  final SaleOutcome outcome;
  final SaleCustomer? customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final queued = outcome is SaleQueued;
    final settlement = switch (outcome) {
      SaleRecorded(:final settlement) || SaleQueued(:final settlement) => settlement,
    };
    final saleId = outcome is SaleRecorded ? (outcome as SaleRecorded).saleId : null;
    final sale = saleId == null ? null : ref.watch(saleDetailProvider(saleId)).value;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // Cet écran remplace l'encaissement : revenir = retrouver la caisse vide.
    void nextSale() => Navigator.of(context).pop();

    return Scaffold(
      body: SafeArea(
        child: JpConstrained(
          maxWidth: JpSpacing.maxFormWidth + 40,
          child: Padding(
            padding: const EdgeInsets.all(JpSpacing.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: reduceMotion ? 1 : 0.5, end: 1),
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.elasticOut,
                    builder: (_, s, child) => Transform.scale(scale: s, child: child),
                    child: JpIllustratedIcon(
                      icon: queued ? Icons.cloud_upload_outlined : Icons.check_rounded,
                      tone: queued ? JpTone.warning : JpTone.success,
                      size: 112,
                    ),
                  ),
                ),
                const SizedBox(height: JpSpacing.xl),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    queued ? 'Vente gardée sur le téléphone' : 'Vente enregistrée',
                    textAlign: TextAlign.center,
                    style: JpTypography.headline.copyWith(color: p.textPrimary),
                  ),
                ),
                const SizedBox(height: JpSpacing.sm),
                Text(
                  queued
                      ? 'Pas de connexion : elle sera envoyée automatiquement dès le retour du réseau, sans risque de doublon.'
                      : sale == null
                      ? 'Stock et caisse mis à jour.'
                      : 'Vente ${sale.number}${customer == null ? '' : ' · ${customer!.name}'}',
                  textAlign: TextAlign.center,
                  style: JpTypography.body.copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: JpSpacing.xxl),
                JpCard(
                  child: Column(
                    children: [
                      _Row(
                        label: 'Total',
                        child: JpAmount(sale?.total ?? settlement.total, currency: currency, style: JpTypography.title),
                      ),
                      if (settlement.paid > 0)
                        _Row(
                          label: 'Encaissé',
                          child: JpAmount(settlement.paid, currency: currency, style: JpTypography.bodyStrong),
                        ),
                      if (settlement.isCredit)
                        _Row(
                          label: 'À crédit',
                          child: JpAmount(
                            settlement.credit,
                            currency: currency,
                            style: JpTypography.bodyStrong,
                            color: p.warning,
                          ),
                        ),
                    ],
                  ),
                ),
                if (settlement.change > 0) ...[
                  const SizedBox(height: JpSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(JpSpacing.xl),
                    decoration: BoxDecoration(color: p.successSoft, borderRadius: JpRadius.all(JpRadius.lg)),
                    child: Column(
                      children: [
                        Text('Monnaie à rendre', style: JpTypography.label.copyWith(color: p.success)),
                        const SizedBox(height: JpSpacing.xs),
                        JpAmount(settlement.change, currency: currency, style: JpTypography.display, color: p.success),
                      ],
                    ),
                  ),
                ],
                const Spacer(flex: 2),
                JpButton(label: 'Nouvelle vente', icon: Icons.add_rounded, onPressed: nextSale),
                if (saleId != null) ...[
                  const SizedBox(height: JpSpacing.sm),
                  JpButton.outline(
                    label: 'Voir le reçu',
                    icon: Icons.receipt_long_outlined,
                    onPressed: () {
                      final router = GoRouter.of(context);
                      nextSale();
                      router.push(Routes.saleDetail(saleId));
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: JpSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: JpTypography.body.copyWith(color: context.palette.textSecondary)),
          ),
          child,
        ],
      ),
    );
  }
}
