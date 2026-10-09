import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../../business/presentation/widgets/invitation_card.dart';
import '../application/notification_providers.dart';
import '../domain/notification_models.dart';
import 'large_sale_threshold_sheet.dart';
import 'notification_navigation.dart';

/// Centre de notifications : invitations en attente, puis alertes par jour.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final list = ref.watch(notificationListProvider);
    final unread = ref.watch(unreadNotificationsProvider);
    final invitations = ref.watch(workspaceProvider.select((w) => w.value?.invitations ?? const []));
    final canSettings = ref.watch(permissionsProvider).can(Permission.settingsManage);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () async {
                try {
                  await ref.read(notificationListProvider.notifier).markAllRead();
                } on AppFailure catch (f) {
                  if (context.mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
                }
              },
              child: const Text('Tout lire'),
            ),
          if (canSettings)
            IconButton(
              tooltip: 'Réglages des alertes',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => showLargeSaleThresholdSheet(context),
            ),
        ],
      ),
      body: JpConstrained(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(workspaceProvider.notifier).refreshContext();
            await ref.read(unreadNotificationsProvider.notifier).refresh();
            await ref.refresh(notificationListProvider.future).then<void>((_) {}, onError: (_) {});
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 400) ref.read(notificationListProvider.notifier).loadMore();
              return false;
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                if (invitations.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, 0),
                    sliver: SliverList.list(
                      children: [
                        Text('INVITATIONS', style: JpTypography.overline.copyWith(color: p.textMuted)),
                        const SizedBox(height: JpSpacing.sm),
                        for (final inv in invitations) ...[
                          InvitationCard(invitation: inv),
                          const SizedBox(height: JpSpacing.md),
                        ],
                      ],
                    ),
                  ),
                ...switch (list) {
                  AsyncValue(:final value?) when value.items.isEmpty => [
                    if (invitations.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: JpEmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: 'Tout est calme',
                          message: 'Stock faible, ventes importantes, invitations : vous serez prévenu ici en direct.',
                        ),
                      ),
                  ],
                  AsyncValue(:final value?) => [_grouped(value.items)],
                  AsyncError(:final error) => [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: JpErrorState(error: error, onRetry: () => ref.invalidate(notificationListProvider)),
                    ),
                  ],
                  _ => [const SliverToBoxAdapter(child: JpSkeletonList(itemCount: 6))],
                },
                const SliverToBoxAdapter(child: SizedBox(height: JpSpacing.huge)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String dayLabel(DateTime at, DateTime now) {
    final d = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Aujourd’hui';
    if (diff == 1) return 'Hier';
    return Formatters.date(at);
  }

  Widget _grouped(List<AppNotification> items) {
    final now = DateTime.now();
    final rows = <Object>[];
    String? day;
    for (final n in items) {
      final label = dayLabel(n.createdAt.toLocal(), now);
      if (label != day) {
        rows.add(label);
        day = label;
      }
      rows.add(n);
    }
    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        if (row is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.lg, JpSpacing.gutter, JpSpacing.xs),
            child: Text(row.toUpperCase(), style: JpTypography.overline.copyWith(color: context.palette.textMuted)),
          );
        }
        return _NotificationTile(notification: row as AppNotification);
      },
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final n = notification;
    final tone = p.tone(n.kind.tone);
    final hasTarget = notificationRoute(n, ref.watch(permissionsProvider)) != null;
    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: JpSpacing.xl),
        color: p.dangerSoft,
        child: Icon(Icons.delete_outline_rounded, color: p.danger),
      ),
      onDismissed: (_) => ref.read(notificationListProvider.notifier).delete(n).catchError((Object _) {}),
      child: Material(
        color: n.unread ? p.brandSoft.withValues(alpha: 0.35) : Colors.transparent,
        child: InkWell(
          onTap: () {
            ref.read(notificationListProvider.notifier).markRead(n);
            if (hasTarget) openNotification(context, ref, n);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: tone.background, borderRadius: JpRadius.all(JpRadius.md)),
                  child: Icon(n.kind.icon, color: tone.foreground, size: 20),
                ),
                const SizedBox(width: JpSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        style: (n.unread ? JpTypography.bodyStrong : JpTypography.body).copyWith(color: p.textPrimary),
                      ),
                      if (n.body != null) ...[
                        const SizedBox(height: 2),
                        Text(n.body!, style: JpTypography.bodySmall.copyWith(color: p.textSecondary)),
                      ],
                      const SizedBox(height: JpSpacing.xs),
                      Text(Formatters.time(n.createdAt), style: JpTypography.caption.copyWith(color: p.textMuted)),
                    ],
                  ),
                ),
                if (n.unread)
                  Padding(
                    padding: const EdgeInsets.only(left: JpSpacing.sm, top: 6),
                    child: Semantics(
                      label: 'Non lue',
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(color: p.signal, shape: BoxShape.circle),
                      ),
                    ),
                  )
                else if (hasTarget)
                  Icon(Icons.chevron_right_rounded, color: p.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
