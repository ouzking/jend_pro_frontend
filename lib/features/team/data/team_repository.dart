import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/supabase/guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/team_models.dart';

final teamRepositoryProvider = Provider<TeamRepository>((ref) => TeamRepository(ref.watch(supabaseClientProvider)));

/// Membres (RPC uniquement : la table `business_members` n'est jamais écrite
/// directement) et fiches employés (`employees`).
class TeamRepository {
  TeamRepository(this._client);

  final SupabaseClient _client;

  // ---------------------------------------------------------------- Membres

  Future<List<TeamMember>> fetchMembers(String businessId) => guardSupabase(() async {
    final rows = await _client.rpc<List<dynamic>>('list_business_members', params: {'p_business_id': businessId});
    return rows.cast<Map<String, dynamic>>().map(TeamMember.fromRow).toList();
  });

  /// Rôles système + rôles propres à l'entreprise, avec leurs permissions.
  Future<List<TeamRole>> fetchRoles(String businessId) => guardSupabase(() async {
    final rows = await _client
        .from('roles')
        .select(TeamRole.columns)
        .or('business_id.is.null,business_id.eq.$businessId');
    return rows.map(TeamRole.fromRow).toList()..sort((a, b) => a.rank.compareTo(b.rank));
  });

  /// `business_members.id` par utilisateur (`members.read`), pour lier une
  /// fiche employé à un compte.
  Future<Map<String, String>> fetchMemberIds(String businessId) => guardSupabase(() async {
    final rows = await _client.from('business_members').select('id, user_id').eq('business_id', businessId);
    return {for (final r in rows) r['user_id'] as String: r['id'] as String};
  });

  /// Invite par e-mail via l'Edge Function, qui crée le compte si besoin puis
  /// appelle `invite_member` **en tant que l'appelant** (toutes les règles
  /// restent vérifiées en base).
  Future<InviteResult> invite(String businessId, {required String email, required String roleCode}) =>
      guardSupabase(() async {
        final res = await _client.functions.invoke(
          'invite-member',
          body: {'business_id': businessId, 'email': email.trim().toLowerCase(), 'role_code': roleCode},
        );
        final data = res.data;
        return InviteResult(accountCreated: data is Map && data['account_created'] == true);
      });

  Future<void> changeRole(String businessId, String userId, String roleCode) => guardSupabase(
    () => _client.rpc<void>(
      'change_member_role',
      params: {'p_business_id': businessId, 'p_user_id': userId, 'p_role_code': roleCode},
    ),
  );

  Future<void> setStatus(String businessId, String userId, MemberStatus status) => guardSupabase(
    () => _client.rpc<void>(
      'set_member_status',
      params: {'p_business_id': businessId, 'p_user_id': userId, 'p_status': status.code},
    ),
  );

  /// Retire un membre ou annule une invitation.
  Future<void> remove(String businessId, String userId) => guardSupabase(
    () => _client.rpc<void>('remove_member', params: {'p_business_id': businessId, 'p_user_id': userId}),
  );

  Future<void> leave(String businessId) =>
      guardSupabase(() => _client.rpc<void>('leave_business', params: {'p_business_id': businessId}));

  // --------------------------------------------------------------- Employés

  Future<List<Employee>> fetchEmployees(String businessId, {required bool archived}) => guardSupabase(() async {
    final rows = await _client
        .from('employees')
        .select(Employee.columns)
        .eq('business_id', businessId)
        .eq('status', archived ? 'ARCHIVED' : 'ACTIVE')
        .order('full_name', ascending: true);
    return rows.map(Employee.fromRow).toList();
  });

  Future<Employee> fetchEmployee(String id) => guardSupabase(() async {
    final row = await _client.from('employees').select(Employee.columns).eq('id', id).single();
    return Employee.fromRow(row);
  });

  Future<Employee> createEmployee(String businessId, EmployeeInput input) => guardSupabase(() async {
    final row = await _client
        .from('employees')
        .insert({'business_id': businessId, ...input.toColumns()})
        .select(Employee.columns)
        .single();
    return Employee.fromRow(row);
  });

  Future<Employee> updateEmployee(String id, EmployeeInput input) => guardSupabase(
    () async =>
        _single(await _client.from('employees').update(input.toColumns()).eq('id', id).select(Employee.columns)),
  );

  Future<Employee> setEmployeeArchived(String id, {required bool archived}) => guardSupabase(
    () async => _single(
      await _client
          .from('employees')
          .update({'status': archived ? 'ARCHIVED' : 'ACTIVE'})
          .eq('id', id)
          .select(Employee.columns),
    ),
  );

  Employee _single(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      throw const AppFailure(
        FailureKind.permission,
        'Vous n’avez pas l’autorisation de modifier cette fiche.',
        code: 'PERMISSION_DENIED',
      );
    }
    return Employee.fromRow(rows.first);
  }
}
