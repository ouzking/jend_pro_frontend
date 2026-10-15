import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/support_models.dart';

final supportRepositoryProvider = Provider<SupportRepository>(
  (ref) => SupportRepository(ref.watch(supabaseClientProvider)),
);

/// Demandes d'aide à l'équipe JËND PRO. Lecture directe (RLS : ses propres
/// demandes, messages publics) ; écritures par RPC uniquement.
class SupportRepository {
  SupportRepository(this._client);

  final SupabaseClient _client;

  Future<List<SupportTicket>> fetchTickets() => guardSupabase(() async {
    final rows = await _client
        .from('support_tickets')
        .select(SupportTicket.columns)
        .order('last_message_at', ascending: false)
        .limit(100);
    return rows.map(SupportTicket.fromRow).toList();
  });

  Future<SupportTicket> fetchTicket(String id) => guardSupabase(() async {
    final row = await _client.from('support_tickets').select(SupportTicket.columns).eq('id', id).single();
    return SupportTicket.fromRow(row);
  });

  Future<List<SupportMessage>> fetchMessages(String ticketId) => guardSupabase(() async {
    final rows = await _client
        .from('support_messages')
        .select(SupportMessage.columns)
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: true);
    return rows.map(SupportMessage.fromRow).toList();
  });

  /// Ouvre une demande (sujet + premier message). Renvoie son identifiant.
  Future<String> createTicket({
    required String subject,
    required String body,
    String? businessId,
    bool urgent = false,
  }) => guardSupabase(
    () => _client.rpc<String>(
      'create_support_ticket',
      params: {
        'p_subject': subject.trim(),
        'p_body': body.trim(),
        'p_business_id': businessId,
        'p_priority': urgent ? 'URGENT' : 'NORMAL',
      },
    ),
  );

  Future<void> reply(String ticketId, String body) => guardSupabase(
    () => _client.rpc<String>('reply_support_ticket', params: {'p_ticket_id': ticketId, 'p_body': body.trim()}),
  );
}
