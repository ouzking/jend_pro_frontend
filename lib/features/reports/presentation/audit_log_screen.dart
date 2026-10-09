import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/formatting/formatters.dart';
import '../application/report_providers.dart';
import '../domain/report_models.dart';

/// Journal d'audit (OWNER / ADMIN) : qui a fait quoi, quand. Lecture seule,
/// en ajout seul côté serveur.
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  static IconData iconFor(String? domain) => switch (domain) {
    'sale' => Icons.receipt_long_outlined,
    'product' => Icons.sell_outlined,
    'inventory' => Icons.inventory_2_outlined,
    'customer' => Icons.person_outline_rounded,
    'purchase' => Icons.local_shipping_outlined,
    'expense' => Icons.payments_outlined,
    'member' => Icons.groups_2_outlined,
    'employee' => Icons.badge_outlined,
    'subscription' => Icons.workspace_premium_outlined,
    _ => Icons.storefront_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final domain = ref.watch(auditDomainProvider);
    final log = ref.watch(auditLogProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Journal d’audit')),
      body: JpConstrained(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.sm),
                children: [
                  for (final d in AuditDomain.values) ...[
                    ChoiceChip(
                      label: Text(d.label),
                      selected: domain == d,
                      onSelected: (_) => ref.read(auditDomainProvider.notifier).set(d),
                    ),
                    const SizedBox(width: JpSpacing.sm),
                  ],
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(auditLogProvider.future).then<void>((_) {}, onError: (_) {}),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.extentAfter < 500) ref.read(auditLogProvider.notifier).loadMore();
                    return false;
                  },
                  child: switch (log) {
                    AsyncValue(:final value?) when value.items.isEmpty => ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        JpEmptyState(
                          icon: Icons.history_rounded,
                          title: 'Aucune action enregistrée',
                          message: 'Les opérations sensibles (prix, stock, annulations, équipe…) apparaîtront ici.',
                        ),
                      ],
                    ),
                    AsyncValue(:final value?) => ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: JpSpacing.huge),
                      itemCount: value.items.length + (value.hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => Divider(height: 1, indent: 72, color: p.border),
                      itemBuilder: (context, i) {
                        if (i >= value.items.length) {
                          return const Padding(
                            padding: EdgeInsets.all(JpSpacing.lg),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _AuditTile(entry: value.items[i]);
                      },
                    ),
                    AsyncError(:final error) => ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [JpErrorState(error: error, onRetry: () => ref.invalidate(auditLogProvider))],
                    ),
                    _ => const JpSkeletonList(itemCount: 8),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = entry;
    final details = e.details;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: p.surfaceMuted, borderRadius: JpRadius.all(JpRadius.md)),
            child: Icon(AuditLogScreen.iconFor(e.domain), color: p.textSecondary, size: 20),
          ),
          const SizedBox(width: JpSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label, style: JpTypography.bodyStrong.copyWith(color: p.textPrimary)),
                if (details != null) ...[
                  const SizedBox(height: 2),
                  Text(details, style: JpTypography.bodySmall.copyWith(color: p.textSecondary)),
                ],
                const SizedBox(height: JpSpacing.xs),
                Text(
                  [e.actorLabel, Formatters.dateTime(e.createdAt)].join(' · '),
                  style: JpTypography.caption.copyWith(color: p.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
