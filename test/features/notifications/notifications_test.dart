import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jend_pro_mobile/app/router/routes.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/pagination/paged.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/business/domain/workspace.dart';
import 'package:jend_pro_mobile/features/notifications/application/notification_providers.dart';
import 'package:jend_pro_mobile/features/notifications/domain/notification_models.dart';
import 'package:jend_pro_mobile/features/notifications/presentation/notification_bell.dart';
import 'package:jend_pro_mobile/features/notifications/presentation/notification_navigation.dart';
import 'package:jend_pro_mobile/features/notifications/presentation/notifications_screen.dart';

class _Unread extends UnreadNotificationsNotifier {
  _Unread(this.initial);

  final int initial;

  @override
  int build() => initial;
}

class _List extends NotificationListController {
  _List(this.items);

  final List<AppNotification> items;
  bool allRead = false;

  @override
  Future<Paged<AppNotification>> build() async => Paged(items: items, hasMore: false);

  @override
  Future<void> markAllRead() async {
    allRead = true;
    ref.read(unreadNotificationsProvider.notifier).clear();
  }
}

class _Workspace extends WorkspaceController {
  _Workspace(this.value);

  final Workspace value;

  @override
  Future<Workspace?> build() async => value;
}

AppNotification _n(
  String id,
  NotificationKind kind,
  DateTime at, {
  Map<String, dynamic> data = const {},
  String? resourceType,
  bool read = false,
}) => AppNotification(
  id: id,
  kind: kind,
  title: 'Titre $id',
  body: 'Corps $id',
  data: data,
  resourceType: resourceType,
  resourceId: data.values.whereType<String>().firstOrNull,
  readAt: read ? at : null,
  createdAt: at,
);

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  group('notificationRoute', () {
    final stock = _n(
      'a',
      NotificationKind.lowStock,
      DateTime(2026),
      data: {'product_id': 'p1'},
      resourceType: 'product',
    );
    final sale = _n('b', NotificationKind.largeSale, DateTime(2026), data: {'sale_id': 's1'}, resourceType: 'sale');

    test('stock faible : fiche stock si inventory.read, sinon fiche produit', () {
      expect(
        notificationRoute(stock, const PermissionSet({Permission.productsRead, Permission.inventoryRead})),
        Routes.productStock('p1'),
      );
      expect(notificationRoute(stock, const PermissionSet({Permission.productsRead})), Routes.productDetail('p1'));
      expect(notificationRoute(stock, const PermissionSet.empty()), isNull, reason: 'catalogue non autorisé');
    });

    test('vente importante : ouverte seulement avec un droit de lecture des ventes', () {
      expect(notificationRoute(sale, const PermissionSet({Permission.salesRead})), Routes.saleDetail('s1'));
      expect(notificationRoute(sale, const PermissionSet({Permission.productsRead})), isNull);
    });

    test('abonnement → Plus ; invitation → aucune navigation', () {
      expect(
        notificationRoute(_n('c', NotificationKind.subscription, DateTime(2026)), const PermissionSet.empty()),
        Routes.more,
      );
      expect(
        notificationRoute(_n('d', NotificationKind.memberInvited, DateTime(2026)), const PermissionSet.empty()),
        isNull,
      );
    });

    test('libellés de jour', () {
      final now = DateTime(2026, 10, 9, 15);
      expect(NotificationsScreen.dayLabel(DateTime(2026, 10, 9, 8), now), 'Aujourd’hui');
      expect(NotificationsScreen.dayLabel(DateTime(2026, 10, 8, 23), now), 'Hier');
      expect(NotificationsScreen.dayLabel(DateTime(2026, 10, 1), now), '1 oct. 2026');
    });
  });

  Future<_List> pump(
    WidgetTester t, {
    required Widget home,
    List<AppNotification> items = const [],
    int unread = 0,
    List<PendingInvitation> invitations = const [],
    Set<String> perms = const {},
  }) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final list = _List(items);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          workspaceProvider.overrideWith(
            () => _Workspace(
              Workspace(memberships: const [], invitations: invitations, permissions: PermissionSet(perms)),
            ),
          ),
          activeBusinessProvider.overrideWithValue(null),
          unreadNotificationsProvider.overrideWith(() => _Unread(unread)),
          notificationListProvider.overrideWith(() => list),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ),
    );
    await t.pumpAndSettle();
    return list;
  }

  testWidgets('pastille : non lues + invitations', (t) async {
    await pump(
      t,
      home: const Scaffold(body: Center(child: NotificationBell())),
      unread: 3,
      invitations: [
        PendingInvitation(
          businessId: 'b2',
          businessName: 'Autre boutique',
          roleCode: 'CASHIER',
          roleName: 'Caissier',
          invitedAt: DateTime(2026),
        ),
      ],
    );
    expect(find.text('4'), findsOneWidget);
    expect(find.byTooltip('Notifications, 4 non lues'), findsOneWidget);
  });

  testWidgets('centre : groupes par jour, non lues, invitations, tout lire', (t) async {
    final now = DateTime.now();
    final list = await pump(
      t,
      home: const NotificationsScreen(),
      unread: 1,
      items: [
        _n('1', NotificationKind.largeSale, now, data: {'sale_id': 's1'}, resourceType: 'sale'),
        _n('2', NotificationKind.lowStock, now.subtract(const Duration(days: 3)), read: true),
      ],
      invitations: [
        PendingInvitation(
          businessId: 'b2',
          businessName: 'Autre boutique',
          roleCode: 'CASHIER',
          roleName: 'Caissier',
          invitedAt: DateTime(2026),
        ),
      ],
    );
    expect(find.text('INVITATIONS'), findsOneWidget);
    expect(find.text('Autre boutique'), findsOneWidget);
    expect(find.text('AUJOURD’HUI'), findsOneWidget);
    expect(find.text('Titre 1'), findsOneWidget);
    expect(find.text('Titre 2'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Non lue')), findsOneWidget);
    await t.tap(find.text('Tout lire'));
    await t.pumpAndSettle();
    expect(list.allRead, isTrue);
    expect(find.text('Tout lire'), findsNothing);
  });

  testWidgets('centre vide', (t) async {
    await pump(t, home: const NotificationsScreen());
    expect(find.text('Tout est calme'), findsOneWidget);
  });
}
