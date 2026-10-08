import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../data/team_repository.dart';
import '../domain/team_models.dart';

String? _bid(Ref ref) => ref.read(activeBusinessProvider)?.businessId;

final teamMembersProvider = FutureProvider.autoDispose<List<TeamMember>>((ref) {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  if (businessId == null) return Future.value(const []);
  return ref.watch(teamRepositoryProvider).fetchMembers(businessId);
});

final teamRolesProvider = FutureProvider.autoDispose<List<TeamRole>>((ref) {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  if (businessId == null) return Future.value(const []);
  return ref.watch(teamRepositoryProvider).fetchRoles(businessId);
});

/// Rôles que l'utilisateur peut attribuer (sous-ensemble de ses permissions).
final assignableRolesProvider = Provider.autoDispose<List<TeamRole>>((ref) {
  final mine = ref.watch(permissionsProvider);
  return [
    for (final r in ref.watch(teamRolesProvider).value ?? const <TeamRole>[])
      if (r.assignableWith(mine)) r,
  ];
});

/// Comptes actifs pouvant être liés à une fiche employé : `business_members.id`
/// → membre. Vide sans `members.read`.
final linkableMembersProvider = FutureProvider.autoDispose<Map<String, TeamMember>>((ref) async {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  if (businessId == null || !ref.watch(permissionsProvider).can(Permission.membersRead)) return const {};
  final repo = ref.watch(teamRepositoryProvider);
  final (ids, members) = (await repo.fetchMemberIds(businessId), await ref.watch(teamMembersProvider.future));
  return {
    for (final m in members)
      if (m.status != MemberStatus.invited && ids[m.userId] != null) ids[m.userId]!: m,
  };
});

final employeesArchivedProvider = NotifierProvider.autoDispose<EmployeesArchivedNotifier, bool>(
  EmployeesArchivedNotifier.new,
);

class EmployeesArchivedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool archived) => state = archived;
}

final employeesProvider = FutureProvider.autoDispose<List<Employee>>((ref) {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  final archived = ref.watch(employeesArchivedProvider);
  if (businessId == null) return Future.value(const []);
  return ref.watch(teamRepositoryProvider).fetchEmployees(businessId, archived: archived);
});

final employeeDetailProvider = FutureProvider.autoDispose.family<Employee, String>(
  (ref, id) => ref.watch(teamRepositoryProvider).fetchEmployee(id),
);

final teamActionsProvider = Provider<TeamActions>(TeamActions.new);

class TeamActions {
  TeamActions(this._ref);

  final Ref _ref;

  TeamRepository get _repo => _ref.read(teamRepositoryProvider);

  String get _businessId => _bid(_ref)!;

  void _members() {
    _ref.invalidate(teamMembersProvider);
    _ref.invalidate(linkableMembersProvider);
  }

  void _employees([String? id]) {
    _ref.invalidate(employeesProvider);
    if (id != null) _ref.invalidate(employeeDetailProvider(id));
  }

  Future<InviteResult> invite(String email, String roleCode) async {
    final r = await _repo.invite(_businessId, email: email, roleCode: roleCode);
    _members();
    return r;
  }

  Future<void> changeRole(TeamMember m, String roleCode) async {
    await _repo.changeRole(_businessId, m.userId, roleCode);
    _members();
  }

  Future<void> setStatus(TeamMember m, MemberStatus status) async {
    await _repo.setStatus(_businessId, m.userId, status);
    _members();
  }

  Future<void> remove(TeamMember m) async {
    await _repo.remove(_businessId, m.userId);
    _members();
    _employees();
  }

  /// Quitte l'entreprise active puis recharge le contexte (le routeur
  /// renvoie vers le choix d'entreprise ou l'onboarding).
  Future<void> leave() async {
    await _repo.leave(_businessId);
    await _ref.read(workspaceProvider.notifier).retry();
  }

  Future<Employee> createEmployee(EmployeeInput input) async {
    final e = await _repo.createEmployee(_businessId, input);
    _employees(e.id);
    return e;
  }

  Future<Employee> updateEmployee(String id, EmployeeInput input) async {
    final e = await _repo.updateEmployee(id, input);
    _employees(id);
    return e;
  }

  Future<void> setEmployeeArchived(Employee e, {required bool archived}) async {
    await _repo.setEmployeeArchived(e.id, archived: archived);
    _employees(e.id);
  }
}
