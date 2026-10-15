// Test d'intégration du support (demandes ↔ équipe JËND PRO) contre le
// Supabase local, avec le compte support des données de démo du backend.
//   flutter test test/integration -j 1 --dart-define-from-file=env/dev.json
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/config/env.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/business/data/business_repository.dart';
import 'package:jend_pro_mobile/features/notifications/data/notifications_repository.dart';
import 'package:jend_pro_mobile/features/support/data/support_repository.dart';
import 'package:jend_pro_mobile/features/support/domain/support_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support.dart';

SupabaseClient _client() => SupabaseClient(
  Env.supabaseUrl,
  Env.supabasePublishableKey,
  authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
);

Matcher _failure(String code) => isA<AppFailure>().having((f) => f.code, 'code', code);

void main() {
  final skip = Env.isConfigured ? false : 'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY non fournis';

  test(
    'support : demande, réponse de l’équipe notifiée, note interne invisible, fermeture',
    () async {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final merchant = _client();
      final other = _client();
      final staff = _client();
      await signUpForTest(
        AuthRepository(merchant),
        fullName: 'Commerçant Support',
        email: 'support-$stamp@test.jendpro.local',
        password: 'motdepasse-test',
      );
      final bid = await BusinessRepository(merchant).createBusiness(name: 'Boutique Support');
      final support = SupportRepository(merchant);

      // Demande rattachée au commerce, marquée bloquante.
      final id = await support.createTicket(
        subject: '  Impression des reçus ',
        body: 'Mon imprimante Bluetooth n’apparaît pas.',
        businessId: bid,
        urgent: true,
      );
      var ticket = await support.fetchTicket(id);
      expect(
        (ticket.subject, ticket.status, ticket.urgent, ticket.businessId),
        ('Impression des reçus', TicketStatus.open, true, bid),
      );
      expect((await support.fetchTickets()).single.id, id);
      expect((await support.fetchMessages(id)).single.fromStaff, isFalse);

      // Un autre utilisateur ne voit rien (RLS).
      await signUpForTest(
        AuthRepository(other),
        fullName: 'Autre',
        email: 'support-other-$stamp@test.jendpro.local',
        password: 'motdepasse-test',
      );
      expect(await SupportRepository(other).fetchTickets(), isEmpty);
      await expectLater(SupportRepository(other).reply(id, 'intrusion'), throwsA(_failure('PERMISSION_DENIED')));

      // L'équipe répond (compte support des données de démo) + note interne.
      await staff.auth.signInWithPassword(email: 'support@demo.jendpro.local', password: 'jendpro-demo');
      await staff.rpc<String>(
        'admin_reply_support_ticket',
        params: {'p_ticket_id': id, 'p_body': 'Bonjour ! Avez-vous installé l’application du pilote ?'},
      );
      await staff.rpc<String>(
        'admin_reply_support_ticket',
        params: {'p_ticket_id': id, 'p_body': 'Note interne : client prioritaire', 'p_internal': true},
      );

      final messages = await support.fetchMessages(id);
      expect(messages.map((m) => (m.fromStaff, m.body.startsWith('Note interne'))), [(false, false), (true, false)]);
      ticket = await support.fetchTicket(id);
      expect(ticket.status, TicketStatus.inProgress);

      // Le commerçant est notifié de la réponse (ouvre la conversation).
      final notifications = await NotificationsRepository(merchant).fetch(bid, offset: 0, limit: 10);
      final reply = notifications.firstWhere((n) => n.resourceType == 'support_ticket');
      expect((reply.resourceId, reply.data['kind'], reply.data['ticket_id']), (id, 'SUPPORT_REPLY', id));

      // Réponse du commerçant, puis fermeture par l'équipe : plus de réponse possible.
      await support.reply(id, 'Oui, merci, ça marche maintenant.');
      expect((await support.fetchMessages(id)).length, 3);
      await staff.rpc<void>('admin_update_support_ticket', params: {'p_ticket_id': id, 'p_status': 'CLOSED'});
      ticket = await support.fetchTicket(id);
      expect((ticket.status, ticket.canReply), (TicketStatus.closed, false));
      await expectLater(support.reply(id, 'encore une question'), throwsA(_failure('TICKET_CLOSED')));

      await merchant.dispose();
      await other.dispose();
      await staff.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
