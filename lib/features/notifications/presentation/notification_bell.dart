import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../business/application/workspace_controller.dart';
import '../application/notification_providers.dart';
import '../domain/notification_models.dart';
import 'notification_navigation.dart';

/// Cloche avec pastille du nombre de non lues (+ invitations en attente).
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final unread = ref.watch(unreadNotificationsProvider);
    final invitations = ref.watch(workspaceProvider.select((w) => w.value?.invitations.length ?? 0));
    final count = unread + invitations;
    return IconButton(
      tooltip: count == 0 ? 'Notifications' : 'Notifications, $count non lues',
      onPressed: () => context.push(Routes.notifications),
      icon: Badge(
        isLabelVisible: count > 0,
        backgroundColor: p.accent,
        textColor: JpColors.forest950,
        label: Text(count > 99 ? '99+' : '$count'),
        child: Icon(count > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded),
      ),
    );
  }
}

/// Affiche en bandeau chaque notification reçue en direct. À placer une
/// fois sous le shell (maintient aussi l'abonnement Realtime actif).
class LiveNotificationListener extends ConsumerWidget {
  const LiveNotificationListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(unreadNotificationsProvider);
    ref.listen<AppNotification?>(incomingNotificationProvider, (_, n) {
      if (n == null) return;
      final p = context.palette;
      final tone = p.tone(n.kind.tone);
      final target = notificationRoute(n, ref.read(permissionsProvider));
      final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Row(
            children: [
              Icon(n.kind.icon, color: tone.background, size: JpSize.iconMd),
              const SizedBox(width: JpSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.title, style: JpTypography.bodyStrong.copyWith(color: Colors.white)),
                    if (n.body != null)
                      Text(
                        n.body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: JpTypography.bodySmall.copyWith(color: Colors.white70),
                      ),
                  ],
                ),
              ),
            ],
          ),
          action: target == null
              ? null
              : SnackBarAction(
                  label: 'Voir',
                  onPressed: () {
                    ref.read(notificationListProvider.notifier).markRead(n);
                    openNotification(context, ref, n);
                  },
                ),
        ),
      );
    });
    return child;
  }
}
