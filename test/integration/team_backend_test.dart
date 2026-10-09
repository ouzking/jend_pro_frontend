// Test d'intégration équipe (membres + fiches employés) contre un Supabase réel,
// Edge Function `invite-member` comprise.
//   flutter test test/integration -j 1 --dart-define-from-file=env/dev.json
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/config/env.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/business/data/business_repository.dart';
import 'package:jend_pro_mobile/features/team/data/team_repository.dart';
import 'package:jend_pro_mobile/features/team/domain/team_models.dart';
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
    'équipe : invitation, acceptation, rôle, suspension, retrait, fiches employés',
    () async {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final ownerClient = _client();
      final staffClient = _client();
      final ownerAuth = AuthRepository(ownerClient);
      final staffAuth = AuthRepository(staffClient);
      final team = TeamRepository(ownerClient);
      final staffTeam = TeamRepository(staffClient);
      final staffBusiness = BusinessRepository(staffClient);

      await signUpForTest(
        ownerAuth,
        fullName: 'Awa Propriétaire',
        email: 'owner-$stamp@test.jendpro.local',
        password: 'motdepasse-test',
      );
      final bid = await BusinessRepository(ownerClient).createBusiness(name: 'Boutique Équipe');
      final staffEmail = 'staff-$stamp@test.jendpro.local';
      await signUpForTest(staffAuth, fullName: 'Moussa Caissier', email: staffEmail, password: 'motdepasse-test');
      final staffId = staffClient.auth.currentUser!.id;
      final ownerId = ownerClient.auth.currentUser!.id;

      // Rôles système, du plus large au plus restreint.
      final roles = await team.fetchRoles(bid);
      expect(roles.map((r) => r.code).take(5), ['OWNER', 'ADMIN', 'MANAGER', 'CASHIER', 'STOCK_MANAGER']);
      final ownerPerms = PermissionSet(await BusinessRepository(ownerClient).fetchPermissions(bid));
      expect(roles.every((r) => r.assignableWith(ownerPerms)), isTrue);
      final admin = roles.firstWhere((r) => r.code == 'ADMIN');
      expect(admin.assignableWith(PermissionSet(admin.permissions)), isTrue);
      expect(roles.first.assignableWith(PermissionSet(admin.permissions)), isFalse, reason: 'ADMIN ≠ OWNER');

      // Invitation d'un compte existant via l'Edge Function.
      final invite = await team.invite(bid, email: staffEmail.toUpperCase(), roleCode: 'CASHIER');
      expect(invite.accountCreated, isFalse);
      await expectLater(team.invite(bid, email: staffEmail, roleCode: 'CASHIER'), throwsA(_failure('ALREADY_MEMBER')));
      var members = await team.fetchMembers(bid);
      expect(members.firstWhere((m) => m.userId == staffId).status, MemberStatus.invited);

      // L'invité accepte.
      final invitations = await staffBusiness.fetchInvitations();
      expect(invitations.single.businessId, bid);
      await staffBusiness.acceptInvitation(bid);

      // Changement de rôle, suspension, réactivation.
      await team.changeRole(bid, staffId, 'MANAGER');
      await team.setStatus(bid, staffId, MemberStatus.suspended);
      members = await team.fetchMembers(bid);
      final staff = members.firstWhere((m) => m.userId == staffId);
      expect((staff.roleCode, staff.status, staff.email), ('MANAGER', MemberStatus.suspended, staffEmail));
      await team.setStatus(bid, staffId, MemberStatus.active);

      // Règles protégées par la base.
      await expectLater(team.changeRole(bid, ownerId, 'ADMIN'), throwsA(_failure('CANNOT_MODIFY_SELF')));
      await expectLater(team.leave(bid), throwsA(_failure('LAST_OWNER')));
      await expectLater(staffTeam.changeRole(bid, ownerId, 'CASHIER'), throwsA(isA<AppFailure>()));

      // Invitation d'une personne sans compte (compte créé par l'Edge Function), puis annulation.
      final newcomer = 'newcomer-$stamp@test.jendpro.local';
      expect((await team.invite(bid, email: newcomer, roleCode: 'CASHIER')).accountCreated, isTrue);
      members = await team.fetchMembers(bid);
      final pending = members.firstWhere((m) => m.email == newcomer);
      expect(pending.status, MemberStatus.invited);
      await team.remove(bid, pending.userId);
      expect((await team.fetchMembers(bid)).any((m) => m.email == newcomer), isFalse);

      // Fiches employés, liées à un compte.
      final memberIds = await team.fetchMemberIds(bid);
      final employee = await team.createEmployee(
        bid,
        EmployeeInput(
          fullName: '  Moussa Diop ',
          phone: '77 123 45 67',
          position: 'Vendeur',
          salaryAmount: 120000,
          hiredAt: DateTime(2026, 1, 15),
          memberId: memberIds[staffId],
        ),
      );
      expect((employee.fullName, employee.phone, employee.memberId), ('Moussa Diop', '771234567', memberIds[staffId]));
      final raised = await team.updateEmployee(
        employee.id,
        EmployeeInput(
          fullName: 'Moussa Diop',
          position: 'Responsable',
          salaryAmount: 150000,
          memberId: employee.memberId,
        ),
      );
      expect((raised.salaryAmount, raised.phone, raised.hiredAt), (150000, null, null));
      await expectLater(
        team.updateEmployee(
          employee.id,
          EmployeeInput(fullName: 'X', hiredAt: DateTime(2026, 5, 1), endedAt: DateTime(2026, 4, 1)),
        ),
        throwsA(_failure('CHECK_VIOLATION')),
      );
      await team.setEmployeeArchived(employee.id, archived: true);
      expect(await team.fetchEmployees(bid, archived: false), isEmpty);
      expect((await team.fetchEmployees(bid, archived: true)).single.id, employee.id);

      // Le gérant voit les fiches (employees.read) mais ne peut pas les modifier.
      expect((await staffTeam.fetchEmployees(bid, archived: true)).single.salaryAmount, 150000);
      await expectLater(
        staffTeam.setEmployeeArchived(employee.id, archived: false),
        throwsA(_failure('PERMISSION_DENIED')),
      );

      // Le membre quitte l'entreprise ; la fiche perd son lien.
      await staffTeam.leave(bid);
      expect((await team.fetchMembers(bid)).map((m) => m.userId), [ownerId]);
      expect((await team.fetchEmployee(employee.id)).memberId, isNull);

      await ownerAuth.signOut();
      await staffAuth.signOut();
      await ownerClient.dispose();
      await staffClient.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
