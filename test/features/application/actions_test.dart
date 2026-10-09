// Règles d'état des actions : justificatifs, lecture des notifications,
// comptes liables, rôles attribuables.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/domain/payment_method.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/business/domain/workspace.dart';
import 'package:jend_pro_mobile/features/expenses/application/expense_providers.dart';
import 'package:jend_pro_mobile/features/expenses/data/expenses_repository.dart';
import 'package:jend_pro_mobile/features/expenses/domain/expense_models.dart';
import 'package:jend_pro_mobile/features/notifications/application/notification_providers.dart';
import 'package:jend_pro_mobile/features/notifications/data/notifications_repository.dart';
import 'package:jend_pro_mobile/features/notifications/domain/notification_models.dart';
import 'package:jend_pro_mobile/features/team/application/team_providers.dart';
import 'package:jend_pro_mobile/features/team/data/team_repository.dart';
import 'package:jend_pro_mobile/features/team/domain/team_models.dart';
import 'package:mocktail/mocktail.dart';

class _Expenses extends Mock implements ExpensesRepository {}

class _Notifications extends Mock implements NotificationsRepository {}

class _Team extends Mock implements TeamRepository {}

class _Unread extends UnreadNotificationsNotifier {
  @override
  int build() => 3;

  int refreshes = 0;

  @override
  Future<void> refresh() async => refreshes++;
}

const _b1 = BusinessMembership(businessId: 'b1', businessName: 'B', roleCode: 'OWNER', roleName: 'Propriétaire');

Expense _expense({String? receipt}) => Expense(
  id: 'e1',
  categoryId: 'c',
  amount: 5000,
  spentOn: DateTime(2026, 10, 1),
  method: PaymentMethod.cash,
  createdAt: DateTime(2026, 10, 1),
  receiptPath: receipt,
);

ExpenseInput _input({String? receipt}) => ExpenseInput(
  categoryId: 'c',
  amount: 6000,
  spentOn: DateTime(2026, 10, 1),
  method: PaymentMethod.cash,
  receiptPath: receipt,
);

AppNotification _n(String id, {bool read = false}) => AppNotification(
  id: id,
  kind: NotificationKind.lowStock,
  title: id,
  businessId: 'b1',
  createdAt: DateTime(2026, 10, 9),
  readAt: read ? DateTime(2026, 10, 9) : null,
);

void main() {
  setUpAll(() => registerFallbackValue(_input()));

  group('dépenses : justificatif remplacé', () {
    late _Expenses repo;

    ProviderContainer make() {
      repo = _Expenses();
      when(() => repo.update('e1', any())).thenAnswer((_) async => _expense());
      when(() => repo.deleteReceipt(any())).thenAnswer((_) async {});
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [activeBusinessProvider.overrideWithValue(_b1), expensesRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('ancien fichier supprimé seulement après une mise à jour réussie', () async {
      final c = make();
      await c
          .read(expenseActionsProvider)
          .update(_expense(receipt: 'b1/expenses/old.jpg'), _input(receipt: 'b1/expenses/new.jpg'));
      verify(() => repo.deleteReceipt('b1/expenses/old.jpg')).called(1);
    });

    test('même justificatif ou aucun avant : rien à supprimer', () async {
      final c = make();
      await c.read(expenseActionsProvider).update(_expense(receipt: 'b1/x.jpg'), _input(receipt: 'b1/x.jpg'));
      await c.read(expenseActionsProvider).update(_expense(), _input(receipt: 'b1/y.jpg'));
      verifyNever(() => repo.deleteReceipt(any()));
    });

    test('échec de la mise à jour : l’ancien justificatif est conservé', () async {
      final c = make();
      when(
        () => repo.update('e1', any()),
      ).thenAnswer((_) async => throw const AppFailure(FailureKind.permission, 'refus'));
      await expectLater(
        c.read(expenseActionsProvider).update(_expense(receipt: 'b1/old.jpg'), _input()),
        throwsA(isA<AppFailure>()),
      );
      verifyNever(() => repo.deleteReceipt(any()));
    });
  });

  group('notifications : lecture', () {
    late _Notifications repo;
    late _Unread unread;

    Future<ProviderContainer> make(List<AppNotification> items) async {
      repo = _Notifications();
      unread = _Unread();
      when(() => repo.fetch('b1', offset: 0, limit: 30)).thenAnswer((_) async => items);
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          activeBusinessProvider.overrideWithValue(_b1),
          notificationsRepositoryProvider.overrideWithValue(repo),
          unreadNotificationsProvider.overrideWith(() => unread),
        ],
      );
      addTearDown(c.dispose);
      c.listen(notificationListProvider, (_, _) {});
      await c.read(notificationListProvider.future);
      return c;
    }

    test('lecture optimiste ; déjà lue : aucun appel', () async {
      final c = await make([_n('a'), _n('b', read: true)]);
      when(() => repo.markRead('a')).thenAnswer((_) async {});
      await c.read(notificationListProvider.notifier).markRead(_n('a'));
      await c.read(notificationListProvider.notifier).markRead(_n('b', read: true));
      expect(c.read(notificationListProvider).value!.items.every((n) => !n.unread), isTrue);
      expect(c.read(unreadNotificationsProvider), 2);
      verify(() => repo.markRead('a')).called(1);
    });

    test('échec réseau : le compteur est resynchronisé', () async {
      final c = await make([_n('a')]);
      when(() => repo.markRead('a')).thenAnswer((_) async => throw const AppFailure(FailureKind.network, 'x'));
      await c.read(notificationListProvider.notifier).markRead(_n('a'));
      expect(unread.refreshes, 1);
    });

    test('tout lire, supprimer', () async {
      final c = await make([_n('a'), _n('b')]);
      when(() => repo.markAllRead('b1')).thenAnswer((_) async => 2);
      when(() => repo.delete('b')).thenAnswer((_) async {});
      await c.read(notificationListProvider.notifier).markAllRead();
      expect(c.read(unreadNotificationsProvider), 0);
      await c.read(notificationListProvider.notifier).delete(c.read(notificationListProvider).value!.items.last);
      expect(c.read(notificationListProvider).value!.items.map((n) => n.id), ['a']);
    });
  });

  group('équipe', () {
    test('comptes liables : invitations exclues, sans members.read rien', () async {
      final repo = _Team();
      when(() => repo.fetchMemberIds('b1')).thenAnswer((_) async => {'u1': 'm1', 'u2': 'm2'});
      when(() => repo.fetchMembers('b1')).thenAnswer(
        (_) async => const [
          TeamMember(
            userId: 'u1',
            fullName: 'Awa',
            roleCode: 'CASHIER',
            roleName: 'Caissier',
            status: MemberStatus.active,
          ),
          TeamMember(userId: 'u2', roleCode: 'CASHIER', roleName: 'Caissier', status: MemberStatus.invited),
        ],
      );
      ProviderContainer make(Set<String> perms) {
        final c = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            activeBusinessProvider.overrideWithValue(_b1),
            permissionsProvider.overrideWithValue(PermissionSet(perms)),
            teamRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(c.dispose);
        c.listen(linkableMembersProvider, (_, _) {});
        return c;
      }

      final linkable = await make({Permission.membersRead}).read(linkableMembersProvider.future);
      expect(linkable.keys, ['m1']);
      expect(await make({}).read(linkableMembersProvider.future), isEmpty);
    });

    test('rôles attribuables selon les permissions détenues', () async {
      final repo = _Team();
      when(() => repo.fetchRoles('b1')).thenAnswer(
        (_) async => const [
          TeamRole(id: '1', code: 'OWNER', name: 'Propriétaire', permissions: {'a', 'b', 'subscription.manage'}),
          TeamRole(id: '2', code: 'ADMIN', name: 'Administrateur', permissions: {'a', 'b'}),
          TeamRole(id: '3', code: 'CASHIER', name: 'Caissier', permissions: {'a'}),
        ],
      );
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          activeBusinessProvider.overrideWithValue(_b1),
          permissionsProvider.overrideWithValue(const PermissionSet({'a', 'b'})),
          teamRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
      c.listen(assignableRolesProvider, (_, _) {});
      await c.read(teamRolesProvider.future);
      expect(c.read(assignableRolesProvider).map((r) => r.code), ['ADMIN', 'CASHIER']);
    });
  });
}
