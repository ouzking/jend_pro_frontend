import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/features/auth/application/auth_session.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/team/application/team_providers.dart';
import 'package:jend_pro_mobile/features/team/domain/team_models.dart';
import 'package:jend_pro_mobile/features/team/presentation/employee_form_screen.dart';
import 'package:jend_pro_mobile/features/team/presentation/employees_screen.dart';
import 'package:jend_pro_mobile/features/team/presentation/team_screen.dart';
import 'package:mocktail/mocktail.dart';

class _Actions extends Mock implements TeamActions {}

class _Session extends AuthSessionNotifier {
  @override
  AuthSession build() => const AuthSession(userId: 'me');
}

const _owner = {
  Permission.membersRead,
  Permission.membersManage,
  Permission.employeesRead,
  Permission.employeesManage,
  Permission.subscriptionManage,
  Permission.salesCreate,
};
const _adminPerms = {
  Permission.membersRead,
  Permission.membersManage,
  Permission.employeesRead,
  Permission.employeesManage,
  Permission.salesCreate,
};

const _roles = [
  TeamRole(id: '1', code: 'OWNER', name: 'Propriétaire', permissions: _owner),
  TeamRole(id: '2', code: 'ADMIN', name: 'Administrateur', permissions: _adminPerms),
  TeamRole(id: '4', code: 'CASHIER', name: 'Caissier', permissions: {Permission.salesCreate}),
];

final _members = [
  const TeamMember(
    userId: 'me',
    fullName: 'Awa Ndiaye',
    roleCode: 'OWNER',
    roleName: 'Propriétaire',
    status: MemberStatus.active,
  ),
  const TeamMember(
    userId: 'u2',
    fullName: 'Moussa Diop',
    email: 'moussa@exemple.sn',
    roleCode: 'CASHIER',
    roleName: 'Caissier',
    status: MemberStatus.active,
  ),
  const TeamMember(
    userId: 'u3',
    email: 'fatou@exemple.sn',
    roleCode: 'CASHIER',
    roleName: 'Caissier',
    status: MemberStatus.invited,
  ),
  const TeamMember(
    userId: 'u4',
    fullName: 'Ibou Sarr',
    roleCode: 'OWNER',
    roleName: 'Propriétaire',
    status: MemberStatus.suspended,
  ),
];

void main() {
  setUpAll(() {
    registerFallbackValue(const EmployeeInput(fullName: ''));
    registerFallbackValue(_members.first);
    return initializeDateFormatting('fr');
  });

  test('un rôle n’est attribuable que si toutes ses permissions sont détenues', () {
    const admin = PermissionSet(_adminPerms);
    expect(_roles.where((r) => r.assignableWith(admin)).map((r) => r.code), ['ADMIN', 'CASHIER']);
  });

  test('EmployeeInput : champs vides envoyés à null, dates ISO', () {
    final cols = EmployeeInput(
      fullName: ' Moussa ',
      position: ' ',
      hiredAt: DateTime(2026, 1, 5),
      salaryAmount: 90000,
    ).toColumns();
    expect(cols, {
      'full_name': 'Moussa',
      'phone': null,
      'position': null,
      'salary_amount': 90000,
      'hired_at': '2026-01-05',
      'ended_at': null,
      'notes': null,
      'member_id': null,
    });
  });

  Future<void> pump(WidgetTester t, Widget home, Set<String> perms, List overrides) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          permissionsProvider.overrideWithValue(PermissionSet(perms)),
          activeBusinessProvider.overrideWithValue(null),
          authSessionProvider.overrideWith(_Session.new),
          teamRolesProvider.overrideWith((ref) async => _roles),
          teamMembersProvider.overrideWith((ref) async => _members),
          ...overrides.cast(),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('équipe : groupes par statut, « vous », invitation réservée à members.manage', (t) async {
    await pump(t, const TeamScreen(), {Permission.membersRead}, []);
    expect(find.text('Awa Ndiaye (vous)'), findsOneWidget);
    expect(find.text('INVITATIONS EN ATTENTE · 1'), findsOneWidget);
    expect(find.text('MEMBRES ACTIFS · 2'), findsOneWidget);
    expect(find.text('ACCÈS SUSPENDUS · 1'), findsOneWidget);
    expect(find.text('fatou@exemple.sn'), findsWidgets, reason: 'invité sans nom : e-mail affiché');
    expect(find.text('Inviter'), findsNothing);
    await t.tap(find.text('Moussa Diop'));
    await t.pumpAndSettle();
    expect(find.text('Suspendre l’accès'), findsNothing, reason: 'lecture seule');
  });

  testWidgets('admin : propriétaire verrouillé, caissier modifiable', (t) async {
    final actions = _Actions();
    when(() => actions.changeRole(any(), any())).thenAnswer((_) async {});
    await pump(t, const TeamScreen(), _adminPerms, [teamActionsProvider.overrideWithValue(actions)]);

    await t.tap(find.text('Ibou Sarr'));
    await t.pumpAndSettle();
    expect(find.textContaining('rôle supérieur au vôtre'), findsOneWidget);
    expect(find.text('Réactiver l’accès'), findsNothing);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    await t.tap(find.text('Moussa Diop'));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('Propriétaire')),
      findsNothing,
      reason: 'OWNER non attribuable par un admin',
    );
    expect(find.text('Suspendre l’accès'), findsOneWidget);
    await t.tap(find.text('Administrateur'));
    await t.pumpAndSettle();
    await t.tap(find.text('Enregistrer le nouveau rôle'));
    await t.pumpAndSettle();
    verify(() => actions.changeRole(_members[1], 'ADMIN')).called(1);
  });

  testWidgets('invitation : e-mail validé puis envoi avec le rôle choisi', (t) async {
    final actions = _Actions();
    when(() => actions.invite(any(), any())).thenAnswer((_) async => const InviteResult(accountCreated: true));
    await pump(t, const TeamScreen(), _owner, [teamActionsProvider.overrideWithValue(actions)]);
    await t.tap(find.text('Inviter'));
    await t.pumpAndSettle();
    await t.tap(find.text('Envoyer l’invitation'));
    await t.pumpAndSettle();
    verifyNever(() => actions.invite(any(), any()));
    await t.enterText(find.byType(TextFormField).first, 'Fatou@Exemple.sn ');
    await t.tap(find.text('Envoyer l’invitation'));
    await t.pumpAndSettle();
    verify(() => actions.invite('fatou@exemple.sn', 'CASHIER')).called(1);
    expect(find.textContaining('Invitation envoyée par e-mail'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('employés : masse salariale et bouton selon droits', (t) async {
    await pump(
      t,
      const EmployeesScreen(),
      {Permission.employeesRead},
      [
        employeesProvider.overrideWith(
          (ref) async => const [
            Employee(id: 'a', fullName: 'Moussa Diop', archived: false, position: 'Vendeur', salaryAmount: 120000),
            Employee(id: 'b', fullName: 'Aïda Fall', archived: false, salaryAmount: 80000, memberId: 'm1'),
          ],
        ),
      ],
    );
    expect(find.text('Masse salariale mensuelle'), findsOneWidget);
    expect(find.text('2 en poste'), findsOneWidget);
    expect(find.text('Poste non précisé · accès à l’app'), findsOneWidget);
    expect(find.text('Employé'), findsNothing);
  });

  testWidgets('fiche employé : nom obligatoire, puis création', (t) async {
    final actions = _Actions();
    when(
      () => actions.createEmployee(any()),
    ).thenAnswer((_) async => const Employee(id: 'n', fullName: 'Moussa', archived: false));
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const EmployeeFormScreen()),
        GoRoute(path: '/employees/:id', builder: (_, s) => Text('fiche ${s.pathParameters['id']}')),
      ],
    );
    await pump(t, MaterialApp.router(theme: AppTheme.light(), routerConfig: router), _owner, [
      teamActionsProvider.overrideWithValue(actions),
      linkableMembersProvider.overrideWith((ref) async => const {}),
    ]);
    await t.tap(find.text('Créer la fiche'));
    await t.pumpAndSettle();
    expect(find.text('Saisissez le nom.'), findsOneWidget);
    verifyNever(() => actions.createEmployee(any()));

    await t.enterText(find.byType(TextFormField).at(0), 'Moussa Diop');
    await t.enterText(find.byType(TextFormField).at(3), '120000');
    await t.tap(find.text('Créer la fiche'));
    await t.pump();
    final input = verify(() => actions.createEmployee(captureAny())).captured.single as EmployeeInput;
    expect((input.fullName, input.salaryAmount), ('Moussa Diop', 120000));
    await t.pumpAndSettle();
    expect(find.text('fiche n'), findsOneWidget);
  });
}
