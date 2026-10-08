import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sales_repository.dart';

/// Vente en attente d'envoi (coupure réseau au moment de la validation).
class PendingSale {
  const PendingSale({required this.request, required this.createdAt, required this.total, this.lastError});

  factory PendingSale.fromJson(Map<String, dynamic> j) => PendingSale(
    request: SaleRequest.fromJson(j['request'] as Map<String, dynamic>),
    createdAt: DateTime.parse(j['created_at'] as String),
    total: (j['total'] as num).toInt(),
    lastError: j['last_error'] as String?,
  );

  final SaleRequest request;
  final DateTime createdAt;

  /// Total estimé (affichage seulement).
  final int total;

  /// Dernier refus **métier** (ex. stock insuffisant) : la vente ne sera pas
  /// rejouée automatiquement tant que l'utilisateur n'a pas décidé.
  final String? lastError;

  bool get blocked => lastError != null;

  PendingSale withError(String? error) =>
      PendingSale(request: request, createdAt: createdAt, total: total, lastError: error);

  Map<String, dynamic> toJson() => {
    'request': request.toJson(),
    'created_at': createdAt.toIso8601String(),
    'total': total,
    'last_error': lastError,
  };
}

/// File locale des ventes non envoyées, dans l'ordre de validation.
///
/// Chaque vente garde son `client_reference` : la rejouer est sans risque
/// (le serveur renvoie la vente déjà créée au lieu d'en créer une autre).
class OfflineSalesQueue {
  OfflineSalesQueue(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'pending_sales_v1';

  List<PendingSale> all() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(PendingSale.fromJson).toList();
    } on FormatException {
      return const [];
    }
  }

  List<PendingSale> forBusiness(String businessId) => all().where((p) => p.request.businessId == businessId).toList();

  Future<void> add(PendingSale sale) =>
      _save([...all().where((p) => p.request.clientReference != sale.request.clientReference), sale]);

  Future<void> remove(String clientReference) =>
      _save(all().where((p) => p.request.clientReference != clientReference).toList());

  Future<void> update(PendingSale sale) =>
      _save([for (final p in all()) p.request.clientReference == sale.request.clientReference ? sale : p]);

  Future<void> _save(List<PendingSale> sales) =>
      _prefs.setString(_key, jsonEncode([for (final s in sales) s.toJson()]));
}
