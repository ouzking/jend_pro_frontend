import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/formatting/formatters.dart';
import '../application/support_providers.dart';
import '../domain/support_models.dart';

/// Aide et support : demandes adressées à l'équipe JËND PRO.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final tickets = ref.watch(supportTicketsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Aide et support')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-ticket',
        onPressed: () => context.push(Routes.supportNew),
        backgroundColor: p.brand,
        foregroundColor: p.textOnBrand,
        elevation: 2,
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        label: Text('Écrire au support', style: JpTypography.label.copyWith(color: p.textOnBrand)),
      ),
      body: JpConstrained(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(supportTicketsProvider.future).then<void>((_) {}, onError: (_) {}),
          child: JpAsyncView<List<SupportTicket>>(
            value: tickets,
            onRetry: () => ref.invalidate(supportTicketsProvider),
            loading: const JpSkeletonList(itemCount: 4),
            data: (list) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, 120),
              children: [
                JpCard(
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: p.brandSoft, borderRadius: JpRadius.all(JpRadius.md)),
                        child: Icon(Icons.support_agent_rounded, color: p.brand),
                      ),
                      const SizedBox(width: JpSpacing.md),
                      Expanded(
                        child: Text(
                          'Une question, un blocage ? L’équipe JËND PRO vous répond ici. '
                          'Vous êtes prévenu dès qu’elle répond.',
                          style: JpTypography.bodySmall.copyWith(color: p.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: JpSpacing.lg),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: JpSpacing.xxl),
                    child: JpEmptyState(
                      icon: Icons.forum_outlined,
                      title: 'Aucune demande',
                      message: 'Écrivez-nous : problème à la caisse, impression, abonnement, équipe…',
                      actionLabel: 'Écrire au support',
                      onAction: () => context.push(Routes.supportNew),
                    ),
                  )
                else ...[
                  Text('VOS DEMANDES', style: JpTypography.overline.copyWith(color: p.textMuted)),
                  const SizedBox(height: JpSpacing.sm),
                  JpCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (i, t) in list.indexed) ...[
                          if (i > 0) Divider(height: 1, color: p.border),
                          _TicketTile(ticket: t),
                        ],
                      ],
                    ),
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

class _TicketTile extends StatelessWidget {
  const _TicketTile({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = ticket;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.xs),
      title: Text(t.subject, maxLines: 2, overflow: TextOverflow.ellipsis),
      titleTextStyle: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: JpSpacing.xs),
        child: Wrap(
          spacing: JpSpacing.sm,
          runSpacing: JpSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            JpBadge(label: t.status.label, tone: t.status.tone, dot: t.status == TicketStatus.waiting),
            Text(
              '#${t.number} · ${Formatters.relative(t.lastMessageAt)}',
              style: JpTypography.caption.copyWith(color: p.textMuted),
            ),
          ],
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
      onTap: () => context.push(Routes.supportTicket(t.id)),
    );
  }
}
