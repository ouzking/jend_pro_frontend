import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';

/// Types du backend (`notification_type`).
enum NotificationKind {
  lowStock('LOW_STOCK', Icons.inventory_2_outlined, JpTone.warning),
  largeSale('LARGE_SALE', Icons.trending_up_rounded, JpTone.success),
  memberInvited('MEMBER_INVITED', Icons.mail_outline_rounded, JpTone.brand),
  subscription('SUBSCRIPTION', Icons.workspace_premium_outlined, JpTone.danger),
  paymentReceived('PAYMENT_RECEIVED', Icons.payments_outlined, JpTone.success),
  system('SYSTEM', Icons.info_outline_rounded, JpTone.info);

  const NotificationKind(this.code, this.icon, this.tone);

  final String code;
  final IconData icon;
  final JpTone tone;

  static NotificationKind parse(String code) => values.firstWhere((k) => k.code == code, orElse: () => system);
}

/// Notification de l'utilisateur connecté (`notifications`, RLS : les siennes).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.businessId,
    this.body,
    this.data = const {},
    this.resourceType,
    this.resourceId,
    this.readAt,
  });

  static const columns = 'id, business_id, type, title, body, data, resource_type, resource_id, read_at, created_at';

  factory AppNotification.fromRow(Map<String, dynamic> r) => AppNotification(
    id: r['id'] as String,
    businessId: r['business_id'] as String?,
    kind: NotificationKind.parse(r['type'] as String),
    title: r['title'] as String,
    body: r['body'] as String?,
    data: (r['data'] as Map?)?.cast<String, dynamic>() ?? const {},
    resourceType: r['resource_type'] as String?,
    resourceId: r['resource_id'] as String?,
    readAt: r['read_at'] == null ? null : DateTime.parse(r['read_at'] as String),
    createdAt: DateTime.parse(r['created_at'] as String),
  );

  final String id;
  final String? businessId;
  final NotificationKind kind;
  final String title;
  final String? body;

  /// Identifiants utiles à la navigation (`product_id`, `sale_id`…).
  final Map<String, dynamic> data;
  final String? resourceType;
  final String? resourceId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get unread => readAt == null;

  AppNotification markedRead(DateTime at) => AppNotification(
    id: id,
    businessId: businessId,
    kind: kind,
    title: title,
    body: body,
    data: data,
    resourceType: resourceType,
    resourceId: resourceId,
    readAt: at,
    createdAt: createdAt,
  );

  /// Concerne l'entreprise active (ou aucune entreprise en particulier).
  bool belongsTo(String? activeBusinessId) => businessId == null || businessId == activeBusinessId;
}
