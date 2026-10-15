import '../../../core/design_system/design_system.dart';

/// Statuts du backend (`ticket_status`).
enum TicketStatus {
  open('OPEN', 'Ouverte', JpTone.info),
  inProgress('IN_PROGRESS', 'En cours', JpTone.brand),
  waiting('WAITING', 'En attente de votre réponse', JpTone.warning),
  resolved('RESOLVED', 'Résolue', JpTone.success),
  closed('CLOSED', 'Fermée', JpTone.neutral);

  const TicketStatus(this.code, this.label, this.tone);

  final String code;
  final String label;
  final JpTone tone;

  static TicketStatus parse(String code) => values.firstWhere((s) => s.code == code, orElse: () => open);
}

/// Demande d'aide adressée à l'équipe JËND PRO (`support_tickets`, RLS : les
/// siennes uniquement).
class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.number,
    required this.subject,
    required this.status,
    required this.lastMessageAt,
    required this.createdAt,
    this.businessId,
    this.urgent = false,
  });

  static const columns = 'id, number, subject, status, priority, business_id, last_message_at, created_at';

  factory SupportTicket.fromRow(Map<String, dynamic> r) => SupportTicket(
    id: r['id'] as String,
    number: (r['number'] as num).toInt(),
    subject: r['subject'] as String,
    status: TicketStatus.parse(r['status'] as String),
    urgent: r['priority'] == 'URGENT' || r['priority'] == 'HIGH',
    businessId: r['business_id'] as String?,
    lastMessageAt: DateTime.parse(r['last_message_at'] as String),
    createdAt: DateTime.parse(r['created_at'] as String),
  );

  final String id;
  final int number;
  final String subject;
  final TicketStatus status;
  final bool urgent;
  final String? businessId;
  final DateTime lastMessageAt;
  final DateTime createdAt;

  /// Une réponse est encore possible (le backend refuse sur une demande fermée).
  bool get canReply => status != TicketStatus.closed;
}

/// Message d'une conversation (les notes internes de l'équipe ne sont jamais
/// renvoyées à l'utilisateur : RLS).
class SupportMessage {
  const SupportMessage({required this.id, required this.body, required this.fromStaff, required this.createdAt});

  static const columns = 'id, body, is_staff, created_at';

  factory SupportMessage.fromRow(Map<String, dynamic> r) => SupportMessage(
    id: r['id'] as String,
    body: r['body'] as String,
    fromStaff: r['is_staff'] as bool,
    createdAt: DateTime.parse(r['created_at'] as String),
  );

  final String id;
  final String body;
  final bool fromStaff;
  final DateTime createdAt;
}

/// Sujets proposés pour démarrer vite (le texte reste modifiable).
const supportTopics = [
  'Problème à la caisse',
  'Impression des reçus',
  'Stock et produits',
  'Abonnement et paiement',
  'Équipe et accès',
  'Autre question',
];
