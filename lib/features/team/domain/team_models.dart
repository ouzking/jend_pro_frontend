import '../../../core/formatting/formatters.dart';
import '../../../core/permissions/permission.dart';

int _int(Object? v) => v is num ? v.toInt() : int.parse('$v');

DateTime? _day(Object? v) => v is String ? DateTime.parse(v) : null;

/// Rôle attribuable (`roles` + `role_permissions`). Les rôles système sont
/// partagés par toutes les entreprises.
class TeamRole {
  const TeamRole({
    required this.id,
    required this.code,
    required this.name,
    required this.permissions,
    this.description,
  });

  static const columns = 'id, code, name, description, grants:role_permissions(permission_code)';

  factory TeamRole.fromRow(Map<String, dynamic> r) => TeamRole(
    id: r['id'] as String,
    code: r['code'] as String,
    name: r['name'] as String,
    description: r['description'] as String?,
    permissions: {
      for (final g in (r['grants'] as List? ?? const [])) (g as Map<String, dynamic>)['permission_code'] as String,
    },
  );

  final String id;
  final String code;
  final String name;
  final String? description;
  final Set<String> permissions;

  /// Ordre d'affichage : du plus large au plus restreint.
  static const _order = ['OWNER', 'ADMIN', 'MANAGER', 'CASHIER', 'STOCK_MANAGER'];

  int get rank {
    final i = _order.indexOf(code);
    return i < 0 ? _order.length : i;
  }

  /// Règle du backend : on n'attribue qu'un rôle dont **toutes** les
  /// permissions sont détenues par l'appelant. Simple confort d'UI.
  bool assignableWith(PermissionSet mine) => permissions.every(mine.can);

  /// Résumé lisible (le libellé `description` de la base est en anglais ou absent).
  String get summary => switch (code) {
    'OWNER' => 'Tous les droits, y compris l’abonnement',
    'ADMIN' => 'Tous les droits sauf l’abonnement',
    'MANAGER' => 'Ventes, stock, achats, clients, rapports',
    'CASHIER' => 'Caisse, clients et crédits ; pas de coûts ni marges',
    'STOCK_MANAGER' => 'Produits, stock, fournisseurs et réceptions',
    _ => description ?? '',
  };
}

enum MemberStatus {
  invited('INVITED', 'Invitation envoyée'),
  active('ACTIVE', 'Actif'),
  suspended('SUSPENDED', 'Suspendu');

  const MemberStatus(this.code, this.label);

  final String code;
  final String label;

  static MemberStatus parse(String code) => values.firstWhere((s) => s.code == code, orElse: () => active);
}

/// Membre de l'entreprise (`list_business_members`). E-mail et téléphone ne
/// sont renvoyés qu'avec `members.read`.
class TeamMember {
  const TeamMember({
    required this.userId,
    this.fullName,
    required this.roleCode,
    required this.roleName,
    required this.status,
    this.email,
    this.phone,
    this.joinedAt,
  });

  factory TeamMember.fromRow(Map<String, dynamic> r) => TeamMember(
    userId: r['user_id'] as String,
    fullName: (r['full_name'] as String?)?.trim().isNotEmpty == true ? r['full_name'] as String : null,
    roleCode: r['role_code'] as String,
    roleName: r['role_name'] as String,
    status: MemberStatus.parse(r['status'] as String),
    email: r['email'] as String?,
    phone: r['phone'] as String?,
    joinedAt: r['joined_at'] == null ? null : DateTime.parse(r['joined_at'] as String),
  );

  final String userId;

  /// `null` tant que la personne invitée n'a pas complété son profil.
  final String? fullName;
  final String roleCode;
  final String roleName;
  final MemberStatus status;
  final String? email;
  final String? phone;
  final DateTime? joinedAt;

  String get displayName => fullName ?? email ?? 'Membre';
}

/// Résultat de l'Edge Function `invite-member`.
class InviteResult {
  const InviteResult({required this.accountCreated});

  /// `true` si la personne n'avait pas de compte : elle reçoit un e-mail.
  final bool accountCreated;
}

/// Fiche RH (`employees`), distincte du compte de connexion.
class Employee {
  const Employee({
    required this.id,
    required this.fullName,
    required this.archived,
    this.phone,
    this.position,
    this.salaryAmount,
    this.hiredAt,
    this.endedAt,
    this.notes,
    this.memberId,
  });

  static const columns = 'id, full_name, phone, position, salary_amount, hired_at, ended_at, notes, member_id, status';

  factory Employee.fromRow(Map<String, dynamic> r) => Employee(
    id: r['id'] as String,
    fullName: r['full_name'] as String,
    phone: r['phone'] as String?,
    position: r['position'] as String?,
    salaryAmount: r['salary_amount'] == null ? null : _int(r['salary_amount']),
    hiredAt: _day(r['hired_at']),
    endedAt: _day(r['ended_at']),
    notes: r['notes'] as String?,
    memberId: r['member_id'] as String?,
    archived: r['status'] == 'ARCHIVED',
  );

  final String id;
  final String fullName;
  final String? phone;
  final String? position;

  /// Salaire mensuel brut, en monnaie de l'entreprise.
  final int? salaryAmount;
  final DateTime? hiredAt;
  final DateTime? endedAt;
  final String? notes;

  /// `business_members.id` du compte de connexion lié, le cas échéant.
  final String? memberId;
  final bool archived;
}

/// Champs modifiables d'une fiche employé (colonnes autorisées en écriture).
class EmployeeInput {
  const EmployeeInput({
    required this.fullName,
    this.phone,
    this.position,
    this.salaryAmount,
    this.hiredAt,
    this.endedAt,
    this.notes,
    this.memberId,
  });

  final String fullName;
  final String? phone;
  final String? position;
  final int? salaryAmount;
  final DateTime? hiredAt;
  final DateTime? endedAt;
  final String? notes;
  final String? memberId;

  static String? _text(String? v) => (v?.trim().isEmpty ?? true) ? null : v!.trim();

  Map<String, Object?> toColumns() => {
    'full_name': fullName.trim(),
    'phone': _text(phone),
    'position': _text(position),
    'salary_amount': salaryAmount,
    'hired_at': hiredAt == null ? null : Formatters.isoDay(hiredAt!),
    'ended_at': endedAt == null ? null : Formatters.isoDay(endedAt!),
    'notes': _text(notes),
    'member_id': memberId,
  };
}
