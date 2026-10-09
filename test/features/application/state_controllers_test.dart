// Logique d'état (contrôleurs Riverpod) testée avec des dépôts simulés :
// sélection du commerce, chargement selon les droits, pagination, temps réel.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/core/pagination/paged.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/core/storage/preferences.dart';
import 'package:jend_pro_mobile/features/auth/application/auth_session.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/business/data/business_repository.dart';
import 'package:jend_pro_mobile/features/business/domain/workspace.dart';
import 'package:jend_pro_mobile/features/customers/application/customer_providers.dart';
import 'package:jend_pro_mobile/features/customers/data/customers_repository.dart';
import 'package:jend_pro_mobile/features/customers/domain/customer_models.dart';
import 'package:jend_pro_mobile/features/dashboard/application/dashboard_controller.dart';
import 'package:jend_pro_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:jend_pro_mobile/features/dashboard/domain/dashboard_models.dart';
import 'package:jend_pro_mobile/features/expenses/application/expense_providers.dart';
import 'package:jend_pro_mobile/features/notifications/application/notification_providers.dart';
import 'package:jend_pro_mobile/features/notifications/data/notifications_repository.dart';
import 'package:jend_pro_mobile/features/notifications/domain/notification_models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _BusinessRepo extends Mock implements BusinessRepository {}

class _DashboardRepo extends Mock implements DashboardRepository {}

class _CustomersRepo extends Mock implements CustomersRepository {}

class _NotificationsRepo extends Mock implements NotificationsRepository {}

class _Channel extends Mock implements RealtimeChannel {}

class _Session extends AuthSessionNotifier {
  _Session(this.userId);

  final String? userId;

  @override
  AuthSession build() => AuthSession(userId: userId);
}

/// Espace de travail figé qui compte les rafraîchissements demandés.
class _Workspace extends WorkspaceController {
  int refreshes = 0;

  @override
  Future<Workspace?> build() async => const Workspace(memberships: [], invitations: []);

  @override
  Future<void> refreshContext() async => refreshes++;
}

BusinessMembership _m(String id, {String tz = 'Africa/Dakar'}) => BusinessMembership(
  businessId: id,
  businessName: 'Boutique $id',
  roleCode: 'OWNER',
  roleName: 'Propriétaire',
  timezone: tz,
);

final _summary = DashboardSummary.fromJson(const {'revenue': 1000, 'sales_count': 2});

Customer _c(int i) => Customer(id: 'c$i', name: 'Client $i', balance: 0, archived: false, createdAt: DateTime(2026));

AppNotification _n(String id, NotificationKind kind, {String? business = 'b1'}) =>
    AppNotification(id: id, kind: kind, title: id, businessId: business, createdAt: DateTime(2026, 10, 9));

void main() {
  setUpAll(() {
    registerFallbackValue(DashboardPeriod.custom(DateTime(2026), DateTime(2026)));
    registerFallbackValue(const CustomerFilter());
    registerFallbackValue(_Channel());
  });

  group('WorkspaceController', () {
    late _BusinessRepo repo;
    late SharedPreferences prefs;

    Future<ProviderContainer> make({
      required List<BusinessMembership> memberships,
      Map<String, Object> stored = const {},
    }) async {
      SharedPreferences.setMockInitialValues(stored);
      prefs = await SharedPreferences.getInstance();
      repo = _BusinessRepo();
      when(() => repo.fetchMemberships('u1')).thenAnswer((_) async => memberships);
      when(() => repo.fetchInvitations()).thenAnswer((_) async => const []);
      when(() => repo.fetchPermissions(any())).thenAnswer((_) async => {Permission.salesCreate});
      when(() => repo.fetchSubscription(any())).thenAnswer(
        (_) async => const SubscriptionStatus(planCode: 'PRO', planName: 'Pro', status: 'ACTIVE', isRestricted: false),
      );
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          businessRepositoryProvider.overrideWithValue(repo),
          authSessionProvider.overrideWith(() => _Session('u1')),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('un seul commerce : activé et mémorisé, permissions chargées', () async {
      final c = await make(memberships: [_m('b1')]);
      final w = await c.read(workspaceProvider.future);
      expect(w!.active?.businessId, 'b1');
      expect(c.read(permissionsProvider).can(Permission.salesCreate), isTrue);
      expect(prefs.getString('active_business_id:u1'), 'b1');
    });

    test('plusieurs commerces : le dernier choisi est restauré, sinon aucun', () async {
      var c = await make(memberships: [_m('b1'), _m('b2')], stored: {'active_business_id:u1': 'b2'});
      expect((await c.read(workspaceProvider.future))!.active?.businessId, 'b2');

      c = await make(memberships: [_m('b1'), _m('b2')]);
      final w = await c.read(workspaceProvider.future);
      expect(w!.active, isNull, reason: 'l’utilisateur choisit');
      expect(w.isReady, isFalse);
      verifyNever(() => repo.fetchPermissions(any()));
    });

    test('abonnement indisponible : l’entrée dans l’app n’est pas bloquée', () async {
      final c = await make(memberships: [_m('b1')]);
      when(
        () => repo.fetchSubscription(any()),
      ).thenAnswer((_) async => throw const AppFailure(FailureKind.network, 'x'));
      final w = await c.read(workspaceProvider.future);
      expect((w!.active?.businessId, w.subscription), ('b1', null));
    });

    test('changer de commerce, puis rafraîchissement silencieux en cas d’échec', () async {
      final c = await make(memberships: [_m('b1'), _m('b2')], stored: {'active_business_id:u1': 'b1'});
      await c.read(workspaceProvider.future);
      await c.read(workspaceProvider.notifier).selectBusiness('b2');
      expect(c.read(activeBusinessProvider)?.businessId, 'b2');
      expect(prefs.getString('active_business_id:u1'), 'b2');

      when(
        () => repo.fetchMemberships('u1'),
      ).thenAnswer((_) async => throw const AppFailure(FailureKind.network, 'hors ligne'));
      await c.read(workspaceProvider.notifier).refreshContext();
      expect(c.read(activeBusinessProvider)?.businessId, 'b2', reason: 'état conservé');
    });

    test('déconnecté : aucun espace de travail', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
          businessRepositoryProvider.overrideWithValue(_BusinessRepo()),
          authSessionProvider.overrideWith(() => _Session(null)),
        ],
      );
      addTearDown(c.dispose);
      expect(await c.read(workspaceProvider.future), isNull);
    });
  });

  group('dashboardProvider : appels selon les droits', () {
    late _DashboardRepo repo;

    ProviderContainer make(Set<String> perms) {
      repo = _DashboardRepo();
      when(() => repo.fetchSummary(any(), any())).thenAnswer((_) async => _summary);
      when(() => repo.fetchSeries(any(), any())).thenAnswer((_) async => const []);
      when(() => repo.fetchTopProducts(any(), any())).thenAnswer((_) async => const []);
      when(() => repo.fetchLowStock(any())).thenAnswer((_) async => const []);
      when(() => repo.fetchRecentSales(any())).thenAnswer((_) async => const []);
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          activeBusinessProvider.overrideWithValue(_m('b1')),
          permissionsProvider.overrideWithValue(PermissionSet(perms)),
          dashboardRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
      c.listen(dashboardProvider, (_, _) {});
      return c;
    }

    test('caissier : aucune requête d’analyse, seulement ses ventes', () async {
      final c = make({Permission.salesReadOwn, Permission.salesCreate});
      final data = await c.read(dashboardProvider.future);
      expect((data.summary, data.lowStock), (null, null));
      verifyNever(() => repo.fetchSummary(any(), any()));
      verifyNever(() => repo.fetchLowStock(any()));
      verify(() => repo.fetchRecentSales('b1')).called(1);
    });

    test('gérant : période courante + précédente, stock, ventes ; changement de période', () async {
      final c = make({Permission.reportsRead, Permission.inventoryRead, Permission.salesRead});
      final data = await c.read(dashboardProvider.future);
      expect(data.summary?.revenue, 1000);
      final periods = verify(() => repo.fetchSummary('b1', captureAny())).captured.cast<DashboardPeriod>();
      expect(periods[1], periods[0].previous);

      c.read(dashboardPeriodProvider.notifier).select(PeriodKind.week);
      final week = await c.read(dashboardProvider.future);
      expect(week.period.days, 7);
      verify(() => repo.fetchSeries('b1', week.period)).called(1);
    });
  });

  group('pagination (clients)', () {
    late _CustomersRepo repo;

    ProviderContainer make() {
      repo = _CustomersRepo();
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          activeBusinessProvider.overrideWithValue(_m('b1')),
          customersRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('page pleine → suite chargée, doublons ignorés, fin détectée', () async {
      final c = make();
      when(
        () => repo.fetchCustomers('b1', any(), offset: 0, limit: 30),
      ).thenAnswer((_) async => [for (var i = 0; i < 30; i++) _c(i)]);
      // Un client inséré entre deux pages décale l'offset : c29 revient.
      when(
        () => repo.fetchCustomers('b1', any(), offset: 30, limit: 30),
      ).thenAnswer((_) async => [_c(29), _c(30), _c(31)]);
      c.listen(customerListProvider, (_, _) {});
      expect((await c.read(customerListProvider.future)).hasMore, isTrue);
      await c.read(customerListProvider.notifier).loadMore();
      final page = c.read(customerListProvider).value!;
      expect(page.items.length, 32);
      expect(page.hasMore, isFalse);
      await c.read(customerListProvider.notifier).loadMore();
      verify(() => repo.fetchCustomers('b1', any(), offset: any(named: 'offset'), limit: 30)).called(2);
    });

    test('échec de la page suivante : liste conservée, erreur exposée', () async {
      final c = make();
      when(
        () => repo.fetchCustomers('b1', any(), offset: 0, limit: 30),
      ).thenAnswer((_) async => [for (var i = 0; i < 30; i++) _c(i)]);
      when(
        () => repo.fetchCustomers('b1', any(), offset: 30, limit: 30),
      ).thenAnswer((_) async => throw const AppFailure(FailureKind.network, 'hors ligne'));
      c.listen(customerListProvider, (_, _) {});
      await c.read(customerListProvider.future);
      await c.read(customerListProvider.notifier).loadMore();
      final page = c.read(customerListProvider).value!;
      expect((page.items.length, page.loadingMore), (30, false));
      expect(page.loadMoreError, isA<AppFailure>());
    });

    test('changement de filtre : retour à la première page', () async {
      final c = make();
      when(() => repo.fetchCustomers('b1', any(), offset: 0, limit: 30)).thenAnswer((_) async => [_c(1)]);
      c.listen(customerListProvider, (_, _) {});
      await c.read(customerListProvider.future);
      c.read(customerFilterProvider.notifier).search('  awa ');
      c.read(customerFilterProvider.notifier).segment(CustomerSegment.debtors);
      await c.read(customerListProvider.future);
      final last =
          verify(() => repo.fetchCustomers('b1', captureAny(), offset: 0, limit: 30)).captured.last as CustomerFilter;
      expect((last.query, last.segment), ('awa', CustomerSegment.debtors));
    });
  });

  group('notifications en direct', () {
    late _NotificationsRepo repo;
    late _Workspace workspace;
    void Function(AppNotification)? push;
    void Function()? fail;

    ProviderContainer make() {
      repo = _NotificationsRepo();
      workspace = _Workspace();
      when(() => repo.unreadCount('b1')).thenAnswer((_) async => 4);
      when(() => repo.unsubscribe(any())).thenAnswer((_) async {});
      when(
        () => repo.subscribe(
          'u1',
          any(),
          onReady: any(named: 'onReady'),
          onError: any(named: 'onError'),
        ),
      ).thenAnswer((inv) {
        push = inv.positionalArguments[1] as void Function(AppNotification);
        fail = inv.namedArguments[#onError] as void Function()?;
        return _Channel();
      });
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          authSessionProvider.overrideWith(() => _Session('u1')),
          activeBusinessProvider.overrideWithValue(_m('b1')),
          workspaceProvider.overrideWith(() => workspace),
          notificationsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
      c.listen(unreadNotificationsProvider, (_, _) {});
      return c;
    }

    test('compteur initial, arrivée en direct, filtrage par commerce, invitation', () async {
      final c = make();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(unreadNotificationsProvider), 4);

      push!(_n('n1', NotificationKind.largeSale));
      expect(c.read(unreadNotificationsProvider), 5);
      expect(c.read(incomingNotificationProvider)?.id, 'n1');

      push!(_n('n2', NotificationKind.lowStock, business: 'autre'));
      expect(c.read(unreadNotificationsProvider), 5, reason: 'autre commerce : ignorée');

      push!(_n('n3', NotificationKind.memberInvited, business: 'autre'));
      expect(workspace.refreshes, 1, reason: 'une invitation recharge le contexte');

      c.read(unreadNotificationsProvider.notifier).decrement();
      c.read(unreadNotificationsProvider.notifier).clear();
      c.read(unreadNotificationsProvider.notifier).decrement();
      expect(c.read(unreadNotificationsProvider), 0, reason: 'jamais négatif');
    });

    test('abonnement en échec : réabonnement après 15 s', () {
      fakeAsync((async) {
        make();
        async.flushMicrotasks();
        verify(
          () => repo.subscribe(
            'u1',
            any(),
            onReady: any(named: 'onReady'),
            onError: any(named: 'onError'),
          ),
        ).called(1);
        fail!();
        fail!(); // une seule relance programmée
        async.elapse(const Duration(seconds: 14));
        verifyNever(
          () => repo.subscribe(
            'u1',
            any(),
            onReady: any(named: 'onReady'),
            onError: any(named: 'onError'),
          ),
        );
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        verify(
          () => repo.subscribe(
            'u1',
            any(),
            onReady: any(named: 'onReady'),
            onError: any(named: 'onError'),
          ),
        ).called(1);
        verify(() => repo.unsubscribe(any())).called(1);
      });
    });
  });

  group('dépenses : navigation par mois', () {
    test('pas de mois futur ; filtre catégorie conservé', () {
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [activeBusinessProvider.overrideWithValue(_m('b1'))],
      );
      addTearDown(c.dispose);
      final n = c.read(expenseViewProvider.notifier);
      final start = c.read(expenseViewProvider).month;
      expect(n.canGoNext, isFalse);
      n.next();
      expect(c.read(expenseViewProvider).month, start);
      n.category('loyer');
      n.previous();
      expect(c.read(expenseViewProvider), ExpenseView(month: start.previous, categoryId: 'loyer'));
      expect(n.canGoNext, isTrue);
      n.next();
      expect(c.read(expenseViewProvider).month, start);
    });
  });

  test('Paged.append : déduplication par clé', () {
    const p = Paged(items: [1, 2, 3], hasMore: true);
    final next = p.append([3, 4], pageSize: 2, keyOf: (i) => i);
    expect(next.items, [1, 2, 3, 4]);
    expect(next.hasMore, isTrue);
  });
}
