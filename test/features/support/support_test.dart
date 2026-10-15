import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jend_pro_mobile/app/router/routes.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/business/domain/workspace.dart';
import 'package:jend_pro_mobile/features/notifications/application/notification_providers.dart';
import 'package:jend_pro_mobile/features/notifications/domain/notification_models.dart';
import 'package:jend_pro_mobile/features/notifications/presentation/notification_navigation.dart';
import 'package:jend_pro_mobile/features/support/data/support_repository.dart';
import 'package:jend_pro_mobile/features/support/domain/support_models.dart';
import 'package:jend_pro_mobile/features/support/presentation/new_ticket_screen.dart';
import 'package:jend_pro_mobile/features/support/presentation/support_screen.dart';
import 'package:jend_pro_mobile/features/support/presentation/ticket_screen.dart';
import 'package:mocktail/mocktail.dart';

class _Repo extends Mock implements SupportRepository {}

const _business = BusinessMembership(
  businessId: 'b1',
  businessName: 'Boutique Ndèye',
  roleCode: 'OWNER',
  roleName: 'P',
);

SupportTicket _ticket({TicketStatus status = TicketStatus.inProgress}) => SupportTicket(
  id: 't1',
  number: 42,
  subject: 'Impression des reçus',
  status: status,
  lastMessageAt: DateTime.now().subtract(const Duration(minutes: 5)),
  createdAt: DateTime(2026, 10, 15),
  businessId: 'b1',
);

final _messages = [
  SupportMessage(
    id: 'm1',
    body: 'Mon imprimante n’apparaît pas.',
    fromStaff: false,
    createdAt: DateTime(2026, 10, 15, 9),
  ),
  SupportMessage(
    id: 'm2',
    body: 'Avez-vous installé le pilote ?',
    fromStaff: true,
    createdAt: DateTime(2026, 10, 15, 9, 5),
  ),
];

void main() {
  late _Repo repo;

  setUpAll(() => initializeDateFormatting('fr'));

  setUp(() {
    repo = _Repo();
    when(() => repo.fetchTickets()).thenAnswer((_) async => [_ticket()]);
    when(() => repo.fetchTicket('t1')).thenAnswer((_) async => _ticket());
    when(() => repo.fetchMessages('t1')).thenAnswer((_) async => _messages);
  });

  Future<ProviderContainer> pump(WidgetTester t, String location) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        supportRepositoryProvider.overrideWithValue(repo),
        activeBusinessProvider.overrideWithValue(_business),
        permissionsProvider.overrideWithValue(const PermissionSet({})),
      ],
    );
    addTearDown(c.dispose);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: Routes.support,
          builder: (_, _) => const SupportScreen(),
          routes: [
            GoRoute(path: 'new', builder: (_, _) => const NewTicketScreen()),
            GoRoute(
              path: ':id',
              builder: (_, s) => TicketScreen(ticketId: s.pathParameters['id']!),
            ),
          ],
        ),
      ],
    );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await t.pumpAndSettle();
    return c;
  }

  testWidgets('liste des demandes', (t) async {
    await pump(t, Routes.support);
    expect(find.text('Impression des reçus'), findsOneWidget);
    expect(find.text('En cours'), findsOneWidget);
    expect(find.textContaining('#42'), findsOneWidget);
  });

  testWidgets('aucune demande : invitation à écrire', (t) async {
    when(() => repo.fetchTickets()).thenAnswer((_) async => const []);
    await pump(t, Routes.support);
    expect(find.text('Aucune demande'), findsOneWidget);
  });

  testWidgets('nouvelle demande : sujet suggéré, validation, envoi avec le commerce actif', (t) async {
    when(
      () => repo.createTicket(
        subject: any(named: 'subject'),
        body: any(named: 'body'),
        businessId: any(named: 'businessId'),
        urgent: any(named: 'urgent'),
      ),
    ).thenAnswer((_) async => 't1');
    await pump(t, Routes.supportNew);
    await t.tap(find.text('Envoyer'));
    await t.pumpAndSettle();
    expect(find.text('Écrivez votre message.'), findsOneWidget);

    await t.tap(find.text('Impression des reçus'));
    await t.enterText(find.widgetWithText(JpTextField, 'Votre message'), 'Mon imprimante n’apparaît pas.');
    await t.drag(find.byType(ListView).first, const Offset(0, -400));
    await t.pumpAndSettle();
    await t.tap(find.text('C’est bloquant'));
    await t.pump();
    await t.tap(find.text('Envoyer'));
    await t.pumpAndSettle();
    verify(
      () => repo.createTicket(
        subject: 'Impression des reçus',
        body: 'Mon imprimante n’apparaît pas.',
        businessId: 'b1',
        urgent: true,
      ),
    ).called(1);
    expect(find.text('Demande #42'), findsOneWidget, reason: 'ouvre la conversation créée');
  });

  testWidgets('conversation : bulles, réponse, rafraîchie par la notification de réponse', (t) async {
    when(() => repo.reply('t1', any())).thenAnswer((_) async {});
    final c = await pump(t, Routes.supportTicket('t1'));
    expect(find.text('Support JËND PRO'), findsOneWidget);
    expect(find.text('Avez-vous installé le pilote ?'), findsOneWidget);

    await t.enterText(find.byType(TextField).last, '  Oui, merci !  ');
    await t.tap(find.byTooltip('Envoyer'));
    await t.pumpAndSettle();
    verify(() => repo.reply('t1', 'Oui, merci !')).called(1);
    final before = verify(() => repo.fetchMessages('t1')).callCount;

    c
        .read(incomingNotificationProvider.notifier)
        .push(
          AppNotification(
            id: 'n1',
            kind: NotificationKind.system,
            title: 'Réponse du support — ticket #42',
            createdAt: DateTime.now(),
            resourceType: 'support_ticket',
            resourceId: 't1',
            data: const {'kind': 'SUPPORT_REPLY', 'ticket_id': 't1'},
          ),
        );
    await t.pumpAndSettle();
    expect(verify(() => repo.fetchMessages('t1')).callCount, greaterThanOrEqualTo(1));
    expect(before, greaterThanOrEqualTo(1));
  });

  testWidgets('demande fermée : plus de saisie', (t) async {
    when(() => repo.fetchTicket('t1')).thenAnswer((_) async => _ticket(status: TicketStatus.closed));
    await pump(t, Routes.supportTicket('t1'));
    expect(find.textContaining('Demande fermée'), findsOneWidget);
    expect(find.byTooltip('Envoyer'), findsNothing);
  });

  test('notification « Réponse du support » → conversation', () {
    final n = AppNotification(
      id: 'n',
      kind: NotificationKind.system,
      title: 'x',
      createdAt: DateTime(2026),
      resourceType: 'support_ticket',
      resourceId: 't1',
    );
    expect(notificationRoute(n, const PermissionSet({})), Routes.supportTicket('t1'));
  });
}
