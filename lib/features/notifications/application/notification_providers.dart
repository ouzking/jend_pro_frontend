import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/pagination/paged.dart';
import '../../auth/application/auth_session.dart';
import '../../business/application/workspace_controller.dart';
import '../data/notifications_repository.dart';
import '../domain/notification_models.dart';

/// Nombre de notifications non lues de l'entreprise active, tenu à jour en
/// temps réel. Crée l'abonnement Realtime tant que l'utilisateur est dans
/// un espace de travail.
final unreadNotificationsProvider = NotifierProvider<UnreadNotificationsNotifier, int>(UnreadNotificationsNotifier.new);

class UnreadNotificationsNotifier extends Notifier<int> {
  @override
  int build() {
    final userId = ref.watch(authSessionProvider.select((s) => s.userId));
    final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    if (userId == null || businessId == null) return 0;
    final repo = ref.watch(notificationsRepositoryProvider);

    final channel = repo.subscribe(userId, (n) => _onInsert(n, businessId));
    ref.onDispose(() => unawaited(repo.unsubscribe(channel)));
    unawaited(_load(businessId));
    return 0;
  }

  Future<void> _load(String businessId) async {
    try {
      final count = await ref.read(notificationsRepositoryProvider).unreadCount(businessId);
      if (ref.mounted) state = count;
    } catch (_) {
      // Badge non essentiel : on réessaiera au prochain rafraîchissement.
    }
  }

  void _onInsert(AppNotification n, String businessId) {
    if (!ref.mounted) return;
    // Une invitation ou un problème d'abonnement change le contexte de travail.
    if (n.kind == NotificationKind.memberInvited || n.kind == NotificationKind.subscription) {
      unawaited(ref.read(workspaceProvider.notifier).refreshContext());
    }
    if (!n.belongsTo(businessId)) return;
    state = state + 1;
    ref.invalidate(notificationListProvider);
    ref.read(incomingNotificationProvider.notifier).push(n);
  }

  Future<void> refresh() async {
    final businessId = ref.read(activeBusinessProvider)?.businessId;
    if (businessId != null) await _load(businessId);
  }

  void decrement() => state = state > 0 ? state - 1 : 0;

  void clear() => state = 0;
}

/// Dernière notification reçue en direct (affichée en bandeau par le shell).
final incomingNotificationProvider = NotifierProvider<IncomingNotificationNotifier, AppNotification?>(
  IncomingNotificationNotifier.new,
);

class IncomingNotificationNotifier extends Notifier<AppNotification?> {
  @override
  AppNotification? build() => null;

  void push(AppNotification n) => state = n;
}

final notificationListProvider = AsyncNotifierProvider.autoDispose<NotificationListController, Paged<AppNotification>>(
  NotificationListController.new,
);

class NotificationListController extends AsyncNotifier<Paged<AppNotification>> {
  static const pageSize = 30;

  NotificationsRepository get _repo => ref.read(notificationsRepositoryProvider);

  @override
  Future<Paged<AppNotification>> build() async {
    final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    if (businessId == null) return const Paged(items: [], hasMore: false);
    final items = await _repo.fetch(businessId, offset: 0, limit: pageSize);
    return Paged(items: items, hasMore: items.length == pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    final businessId = ref.read(activeBusinessProvider)?.businessId;
    if (current == null || businessId == null || !current.hasMore || current.loadingMore || state.isLoading) return;
    state = AsyncData(current.copyWith(loadingMore: true, loadMoreError: () => null));
    try {
      final next = await _repo.fetch(businessId, offset: current.items.length, limit: pageSize);
      if (ref.mounted) state = AsyncData(current.append(next, pageSize: pageSize, keyOf: (n) => n.id));
    } catch (e) {
      if (ref.mounted) state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: () => e));
    }
  }

  void _replace(List<AppNotification> Function(List<AppNotification>) update) {
    final current = state.value;
    if (current != null) state = AsyncData(current.copyWith(items: update(current.items)));
  }

  /// Marque comme lue (optimiste) ; l'échec réseau n'est pas bloquant.
  Future<void> markRead(AppNotification n) async {
    if (!n.unread) return;
    final now = DateTime.now();
    _replace((items) => [for (final i in items) i.id == n.id ? i.markedRead(now) : i]);
    ref.read(unreadNotificationsProvider.notifier).decrement();
    try {
      await _repo.markRead(n.id);
    } catch (_) {
      unawaited(ref.read(unreadNotificationsProvider.notifier).refresh());
    }
  }

  Future<void> markAllRead() async {
    final businessId = ref.read(activeBusinessProvider)?.businessId;
    if (businessId == null) return;
    await _repo.markAllRead(businessId);
    final now = DateTime.now();
    _replace((items) => [for (final i in items) i.unread ? i.markedRead(now) : i]);
    ref.read(unreadNotificationsProvider.notifier).clear();
  }

  Future<void> delete(AppNotification n) async {
    _replace((items) => items.where((i) => i.id != n.id).toList());
    if (n.unread) ref.read(unreadNotificationsProvider.notifier).decrement();
    await _repo.delete(n.id);
  }
}
