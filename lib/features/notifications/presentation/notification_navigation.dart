import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../domain/notification_models.dart';

/// Écran lié à une notification, si l'utilisateur peut l'ouvrir.
String? notificationRoute(AppNotification n, PermissionSet permissions) {
  String? id(String key) => n.data[key] as String? ?? n.resourceId;
  final path = switch ((n.kind, n.resourceType)) {
    (NotificationKind.lowStock, _) || (_, 'product') when id('product_id') != null =>
      permissions.can(Permission.inventoryRead)
          ? Routes.productStock(id('product_id')!)
          : Routes.productDetail(id('product_id')!),
    (NotificationKind.largeSale, _) || (_, 'sale') when id('sale_id') != null => Routes.saleDetail(id('sale_id')!),
    (_, 'customer') when n.resourceId != null => Routes.customerDetail(n.resourceId!),
    (_, 'supplier') when n.resourceId != null => Routes.supplierDetail(n.resourceId!),
    (_, 'purchase') when n.resourceId != null => Routes.purchaseDetail(n.resourceId!),
    (_, 'expense') when n.resourceId != null => Routes.expenseDetail(n.resourceId!),
    (NotificationKind.subscription, _) => Routes.more,
    _ => null,
  };
  if (path == null) return null;
  final required = Routes.requiredPermissions(path);
  return required == null || permissions.canAny(required) ? path : null;
}

void openNotification(BuildContext context, WidgetRef ref, AppNotification n) {
  final path = notificationRoute(n, ref.read(permissionsProvider));
  if (path == null) return;
  if (path == Routes.more) {
    context.go(path);
  } else {
    context.push(path);
  }
}
