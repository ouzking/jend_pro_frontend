import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/notification_models.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(supabaseClientProvider)),
);

/// Notifications de l'utilisateur connecté : la RLS ne renvoie que les
/// siennes ; on filtre en plus sur l'entreprise active (+ globales).
class NotificationsRepository {
  NotificationsRepository(this._client);

  final SupabaseClient _client;

  String _scope(String businessId) => 'business_id.is.null,business_id.eq.$businessId';

  Future<List<AppNotification>> fetch(String businessId, {required int offset, required int limit}) =>
      guardSupabase(() async {
        final rows = await _client
            .from('notifications')
            .select(AppNotification.columns)
            .or(_scope(businessId))
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1);
        return rows.map(AppNotification.fromRow).toList();
      });

  Future<int> unreadCount(String businessId) => guardSupabase(
    () => _client
        .from('notifications')
        .select('id')
        .or(_scope(businessId))
        .isFilter('read_at', null)
        .count(CountOption.exact)
        .then((r) => r.count),
  );

  Future<void> markRead(String id) => guardSupabase(
    () => _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .isFilter('read_at', null),
  );

  /// Renvoie le nombre de notifications passées à « lu ».
  Future<int> markAllRead(String businessId) => guardSupabase(
    () async => (await _client.rpc<int>('mark_all_notifications_read', params: {'p_business_id': businessId})),
  );

  Future<void> delete(String id) => guardSupabase(() => _client.from('notifications').delete().eq('id', id));

  /// Temps réel : nouvelles notifications de l'utilisateur (la RLS filtre
  /// déjà côté serveur ; le filtre `user_id` limite le trafic).
  ///
  /// [onReady] : la réplication est réellement active (message système
  /// « ok » du serveur — le statut `subscribed` est émis avant, de façon
  /// optimiste). [onError] : abonnement en échec (jeton expiré, serveur
  /// indisponible…) ; l'appelant doit se réabonner.
  RealtimeChannel subscribe(
    String userId,
    void Function(AppNotification) onInsert, {
    void Function()? onReady,
    void Function()? onError,
  }) {
    var ready = false;
    final channel = _client
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId),
          callback: (payload) {
            try {
              onInsert(AppNotification.fromRow(payload.newRecord));
            } catch (_) {
              // Ligne inattendue : ignorée, la liste se resynchronise au prochain chargement.
            }
          },
        )
        .onSystemEvents((payload) {
          if (!ready && payload is Map && payload['status'] == 'ok') {
            ready = true;
            onReady?.call();
          }
        });
    channel.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
        onError?.call();
      }
    });
    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel channel) => _client.removeChannel(channel);
}
