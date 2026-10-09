// Test d'intégration des notifications (déclencheurs serveur + Realtime).
//   flutter test test/integration -j 1 --dart-define-from-file=env/dev.json
@Tags(['integration'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/config/env.dart';
import 'package:jend_pro_mobile/core/domain/payment_method.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/business/data/business_repository.dart';
import 'package:jend_pro_mobile/features/inventory/data/inventory_repository.dart';
import 'package:jend_pro_mobile/features/notifications/data/notifications_repository.dart';
import 'package:jend_pro_mobile/features/notifications/domain/notification_models.dart';
import 'package:jend_pro_mobile/features/products/data/products_repository.dart';
import 'package:jend_pro_mobile/features/products/domain/catalog_models.dart';
import 'package:jend_pro_mobile/features/sales/data/sales_repository.dart';
import 'package:jend_pro_mobile/features/team/data/team_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support.dart';

SupabaseClient _client() => SupabaseClient(
  Env.supabaseUrl,
  Env.supabasePublishableKey,
  authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
);

void main() {
  final skip = Env.isConfigured ? false : 'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY non fournis';

  test(
    'notifications : vente importante, stock faible, invitation, temps réel, lecture, suppression',
    () async {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final client = _client();
      final staffClient = _client();
      final auth = AuthRepository(client);
      final business = BusinessRepository(client);
      final notifications = NotificationsRepository(client);

      await signUpForTest(
        auth,
        fullName: 'Test Notifs',
        email: 'notifs-$stamp@test.jendpro.local',
        password: 'motdepasse-test',
      );
      final userId = client.auth.currentUser!.id;
      final bid = await business.createBusiness(name: 'Boutique Notifs');
      final loc = await business.fetchDefaultLocationId(bid);

      // Seuil « vente importante ».
      expect(await business.fetchLargeSaleThreshold(bid), isNull);
      await business.setLargeSaleThreshold(bid, 10000);
      expect(await business.fetchLargeSaleThreshold(bid), 10000);

      // Temps réel : on écoute avant de déclencher.
      final received = <AppNotification>[];
      final ready = Completer<void>();
      final channel = notifications.subscribe(userId, received.add, onReady: ready.complete);
      await ready.future.timeout(const Duration(seconds: 10));

      final products = ProductsRepository(client);
      final huile = await products.createProduct(
        bid,
        const NewProduct(name: 'Huile 5 L', salePrice: 6500, minStockLevel: 5),
      );
      await InventoryRepository(
        client,
      ).setInitialStock(businessId: bid, productId: huile.id, locationId: loc, quantity: 8);

      // 2 × 6 500 = 13 000 ≥ 10 000 → LARGE_SALE ; stock 8 → 6 (> 5) : pas encore d'alerte.
      final sales = SalesRepository(client);
      Future<String> sell(int qty) => sales.createSale(
        SaleRequest(
          businessId: bid,
          clientReference: const Uuid().v4(),
          locationId: loc,
          items: [
            {'product_id': huile.id, 'quantity': qty},
          ],
          payments: [
            {'method': PaymentMethod.cash.code, 'amount': 6500 * qty},
          ],
        ),
      );
      final bigSale = await sell(2);
      await sell(1); // 6 → 5 : franchit le seuil → LOW_STOCK.

      var list = await notifications.fetch(bid, offset: 0, limit: 20);
      expect(list.map((n) => n.kind).toSet(), {NotificationKind.largeSale, NotificationKind.lowStock});
      final large = list.firstWhere((n) => n.kind == NotificationKind.largeSale);
      expect((large.data['sale_id'], large.resourceType), (bigSale, 'sale'));
      expect(list.firstWhere((n) => n.kind == NotificationKind.lowStock).data['product_id'], huile.id);
      expect(await notifications.unreadCount(bid), 2);

      // Livrées aussi en direct.
      for (var i = 0; i < 150 && received.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(received.map((n) => n.kind).toSet(), {NotificationKind.largeSale, NotificationKind.lowStock});
      await notifications.unsubscribe(channel);

      // Lecture, tout lire, suppression.
      await notifications.markRead(large.id);
      expect(await notifications.unreadCount(bid), 1);
      expect(await notifications.markAllRead(bid), 1);
      expect(await notifications.unreadCount(bid), 0);
      await notifications.delete(large.id);
      list = await notifications.fetch(bid, offset: 0, limit: 20);
      expect(list.single.kind, NotificationKind.lowStock);

      // Invitation : notification pour l'invité, isolée des autres utilisateurs.
      final staffEmail = 'notifs-staff-$stamp@test.jendpro.local';
      await signUpForTest(
        AuthRepository(staffClient),
        fullName: 'Invité',
        email: staffEmail,
        password: 'motdepasse-test',
      );
      await TeamRepository(client).invite(bid, email: staffEmail, roleCode: 'CASHIER');
      final staffList = await NotificationsRepository(staffClient).fetch(bid, offset: 0, limit: 20);
      expect(staffList.single.kind, NotificationKind.memberInvited);
      expect(staffList.single.title, contains('Boutique Notifs'));

      // Désactivation du seuil.
      await business.setLargeSaleThreshold(bid, null);
      expect(await business.fetchLargeSaleThreshold(bid), isNull);

      await auth.signOut();
      await client.dispose();
      await staffClient.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
