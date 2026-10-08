import '../../../core/permissions/permission.dart';

/// Adhésion ACTIVE de l'utilisateur à une entreprise (`business_members`).
class BusinessMembership {
  const BusinessMembership({
    required this.businessId,
    required this.businessName,
    required this.roleCode,
    required this.roleName,
    this.city,
    this.logoPath,
    this.currencyCode = 'XOF',
    this.timezone = 'Africa/Dakar',
  });

  factory BusinessMembership.fromRow(Map<String, dynamic> row) {
    final business = row['business'] as Map<String, dynamic>;
    final role = row['role'] as Map<String, dynamic>;
    return BusinessMembership(
      businessId: business['id'] as String,
      businessName: business['name'] as String,
      city: business['city'] as String?,
      logoPath: business['logo_path'] as String?,
      currencyCode: (business['currency_code'] as String?) ?? 'XOF',
      timezone: (business['timezone'] as String?) ?? 'Africa/Dakar',
      roleCode: role['code'] as String,
      roleName: role['name'] as String,
    );
  }

  final String businessId;
  final String businessName;
  final String roleCode;
  final String roleName;
  final String? city;
  final String? logoPath;
  final String currencyCode;
  final String timezone;
}

/// Invitation en attente (`list_my_invitations`).
class PendingInvitation {
  const PendingInvitation({
    required this.businessId,
    required this.businessName,
    required this.roleCode,
    required this.roleName,
    required this.invitedAt,
  });

  factory PendingInvitation.fromRow(Map<String, dynamic> row) => PendingInvitation(
    businessId: row['business_id'] as String,
    businessName: row['business_name'] as String,
    roleCode: row['role_code'] as String,
    roleName: row['role_name'] as String,
    invitedAt: DateTime.parse(row['invited_at'] as String),
  );

  final String businessId;
  final String businessName;
  final String roleCode;
  final String roleName;
  final DateTime invitedAt;
}

/// État d'abonnement (`get_subscription_status`).
class SubscriptionStatus {
  const SubscriptionStatus({
    required this.planCode,
    required this.planName,
    required this.status,
    required this.isRestricted,
    this.trialEndsAt,
    this.currentPeriodEnd,
  });

  factory SubscriptionStatus.fromRow(Map<String, dynamic> row) => SubscriptionStatus(
    planCode: row['plan_code'] as String,
    planName: row['plan_name'] as String,
    status: row['status'] as String,
    isRestricted: (row['is_restricted'] as bool?) ?? false,
    trialEndsAt: _date(row['trial_ends_at']),
    currentPeriodEnd: _date(row['current_period_end']),
  );

  final String planCode;
  final String planName;

  /// `TRIALING`, `ACTIVE`, `PAST_DUE`, `CANCELLED`, `EXPIRED`.
  final String status;

  /// Mode restreint : lecture seule sauf la caisse.
  final bool isRestricted;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodEnd;

  bool get isTrial => status == 'TRIALING';

  static DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value) : null;
}

/// Contexte de travail de l'utilisateur connecté.
class Workspace {
  const Workspace({
    required this.memberships,
    required this.invitations,
    this.active,
    this.permissions = const PermissionSet.empty(),
    this.subscription,
  });

  final List<BusinessMembership> memberships;
  final List<PendingInvitation> invitations;

  /// Entreprise active ; `null` tant que l'utilisateur n'a pas choisi.
  final BusinessMembership? active;
  final PermissionSet permissions;
  final SubscriptionStatus? subscription;

  bool get hasBusiness => memberships.isNotEmpty;

  bool get isReady => active != null;

  bool get isRestricted => subscription?.isRestricted ?? false;
}
