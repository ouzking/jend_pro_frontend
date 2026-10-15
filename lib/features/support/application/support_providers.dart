import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../business/application/workspace_controller.dart';
import '../../notifications/domain/notification_models.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';

final supportTicketsProvider = FutureProvider.autoDispose<List<SupportTicket>>(
  (ref) => ref.watch(supportRepositoryProvider).fetchTickets(),
);

final supportTicketProvider = FutureProvider.autoDispose.family<SupportTicket, String>(
  (ref, id) => ref.watch(supportRepositoryProvider).fetchTicket(id),
);

final supportMessagesProvider = FutureProvider.autoDispose.family<List<SupportMessage>, String>(
  (ref, id) => ref.watch(supportRepositoryProvider).fetchMessages(id),
);

/// La notification « Réponse du support » concerne-t-elle cette demande ?
/// (Le backend notifie le demandeur à chaque réponse publique de l'équipe.)
bool isSupportReplyFor(AppNotification? n, String ticketId) =>
    n != null &&
    (n.data['kind'] == 'SUPPORT_REPLY' || n.resourceType == 'support_ticket') &&
    (n.data['ticket_id'] == ticketId || n.resourceId == ticketId);

final supportActionsProvider = Provider<SupportActions>(SupportActions.new);

class SupportActions {
  SupportActions(this._ref);

  final Ref _ref;

  SupportRepository get _repo => _ref.read(supportRepositoryProvider);

  /// Ouvre une demande, rattachée au commerce actif s'il y en a un.
  Future<String> create({required String subject, required String body, bool urgent = false}) async {
    final id = await _repo.createTicket(
      subject: subject,
      body: body,
      businessId: _ref.read(activeBusinessProvider)?.businessId,
      urgent: urgent,
    );
    _ref.invalidate(supportTicketsProvider);
    return id;
  }

  Future<void> reply(String ticketId, String body) async {
    await _repo.reply(ticketId, body);
    refresh(ticketId);
  }

  void refresh(String ticketId) {
    _ref
      ..invalidate(supportMessagesProvider(ticketId))
      ..invalidate(supportTicketProvider(ticketId))
      ..invalidate(supportTicketsProvider);
  }
}
