import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/formatting/formatters.dart';
import '../../business/application/workspace_controller.dart';
import '../../business/domain/workspace.dart';
import '../application/settings_providers.dart';
import '../domain/settings_models.dart';

/// État de l'abonnement, utilisation du plan et formules disponibles. Le
/// paiement passe par le serveur (`billing-webhook`) : aucun paiement n'est
/// déclenché depuis l'application.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  static (String, JpTone) statusOf(SubscriptionStatus s) => switch (s.status) {
    _ when s.isRestricted => ('Lecture seule', JpTone.danger),
    'TRIALING' => ('Période d’essai', JpTone.accent),
    'ACTIVE' => ('Actif', JpTone.success),
    'PAST_DUE' => ('Paiement en retard', JpTone.warning),
    'CANCELLED' => ('Résilié', JpTone.danger),
    _ => ('Expiré', JpTone.danger),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final sub = ref.watch(workspaceProvider.select((w) => w.value?.subscription));
    final plans = ref.watch(subscriptionPlansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Abonnement')),
      body: JpConstrained(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(workspaceProvider.notifier).refreshContext();
            ref.invalidate(subscriptionPlansProvider);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, JpSpacing.huge),
            children: [
              if (sub == null)
                const JpBanner(
                  tone: JpTone.warning,
                  icon: Icons.cloud_off_rounded,
                  message: 'État de l’abonnement indisponible. Tirez pour actualiser.',
                )
              else ...[
                _StatusCard(subscription: sub),
                const SizedBox(height: JpSpacing.xl),
                const JpSectionHeader(title: 'Utilisation'),
                const SizedBox(height: JpSpacing.sm),
                JpCard(
                  child: Column(
                    children: [
                      _UsageRow(
                        'Membres (actifs et invités)',
                        sub.usage.members,
                        sub.limits.members,
                        Icons.groups_2_outlined,
                      ),
                      _UsageRow('Produits actifs', sub.usage.products, sub.limits.products, Icons.inventory_2_outlined),
                      _UsageRow(
                        'Emplacements actifs',
                        sub.usage.locations,
                        sub.limits.locations,
                        Icons.storefront_outlined,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: JpSpacing.xl),
              const JpSectionHeader(title: 'Formules'),
              const SizedBox(height: JpSpacing.sm),
              JpAsyncView<List<SubscriptionPlan>>(
                value: plans,
                onRetry: () => ref.invalidate(subscriptionPlansProvider),
                loading: const JpSkeletonList(itemCount: 3, padding: EdgeInsets.zero),
                data: (list) => Column(
                  children: [
                    for (final plan in list) ...[
                      _PlanCard(plan: plan, current: plan.code == sub?.planCode),
                      const SizedBox(height: JpSpacing.sm),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: JpSpacing.md),
              Text(
                'Le paiement de l’abonnement en ligne (Wave, Orange Money) n’est pas encore disponible dans l’application. '
                'Dès qu’un paiement est confirmé, votre formule se met à jour automatiquement ici.',
                style: JpTypography.caption.copyWith(color: p.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.subscription});

  final SubscriptionStatus subscription;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = subscription;
    final (label, tone) = SubscriptionScreen.statusOf(s);
    final end = s.isTrial ? s.trialEndsAt : s.currentPeriodEnd;
    final daysLeft = end?.difference(DateTime.now()).inDays;
    return JpCard(
      padding: const EdgeInsets.all(JpSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_rounded, color: p.accent, size: 28),
              const SizedBox(width: JpSpacing.sm),
              Expanded(
                child: Text('Formule ${s.planName}', style: JpTypography.title.copyWith(color: p.textPrimary)),
              ),
              JpBadge(label: label, tone: tone, dot: true),
            ],
          ),
          if (end != null) ...[
            const SizedBox(height: JpSpacing.md),
            Text(
              '${s.isTrial ? 'Essai gratuit jusqu’au' : 'Période en cours jusqu’au'} ${Formatters.date(end)}'
              '${daysLeft != null && daysLeft >= 0 ? ' · ${daysLeft == 0 ? 'dernier jour' : '$daysLeft jour(s) restant(s)'}' : ''}',
              style: JpTypography.body.copyWith(color: p.textSecondary),
            ),
          ],
          if (s.isRestricted) ...[
            const SizedBox(height: JpSpacing.md),
            const JpBanner(
              tone: JpTone.danger,
              icon: Icons.lock_clock_outlined,
              message: 'Votre espace est en lecture seule. La caisse reste ouverte : vous pouvez continuer à vendre.',
            ),
          ],
        ],
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow(this.label, this.used, this.max, this.icon);

  final String label;
  final int? used;
  final int? max;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final u = used ?? 0;
    final ratio = max == null || max == 0 ? null : (u / max!).clamp(0.0, 1.0);
    final full = ratio != null && ratio >= 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: JpSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: p.textMuted),
              const SizedBox(width: JpSpacing.sm),
              Expanded(
                child: Text(label, style: JpTypography.body.copyWith(color: p.textPrimary)),
              ),
              Text(
                max == null ? '$u · illimité' : '$u / $max',
                style: JpTypography.label.copyWith(color: full ? p.danger : p.textSecondary),
              ),
            ],
          ),
          if (ratio != null) ...[
            const SizedBox(height: JpSpacing.xs),
            ClipRRect(
              borderRadius: JpRadius.all(JpRadius.xs),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: p.surfaceMuted,
                color: full ? p.danger : (ratio >= 0.8 ? p.warning : p.brand),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.current});

  final SubscriptionPlan plan;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    String quota(int? v, String unit) => v == null ? '$unit illimités' : '$v $unit';
    return JpCard(
      borderColor: current ? p.accent : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(plan.name, style: JpTypography.titleSmall.copyWith(color: p.textPrimary)),
              ),
              if (current) const JpBadge(label: 'Votre formule', tone: JpTone.accent),
            ],
          ),
          if (plan.description != null)
            Text(plan.description!, style: JpTypography.caption.copyWith(color: p.textMuted)),
          const SizedBox(height: JpSpacing.sm),
          Text(
            plan.price == 0
                ? 'Gratuit'
                : '${Formatters.money(plan.price, currency: plan.currencyCode)} ${plan.periodLabel}',
            style: JpTypography.numeric(JpTypography.title).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: JpSpacing.sm),
          Text(
            [
              quota(plan.limits.members, 'membres'),
              quota(plan.limits.products, 'produits'),
              quota(plan.limits.locations, 'emplacements'),
            ].join(' · '),
            style: JpTypography.bodySmall.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}
