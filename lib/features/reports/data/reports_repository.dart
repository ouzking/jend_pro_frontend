import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/report_models.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(ref.watch(supabaseClientProvider)),
);

/// Journal d'audit (`get_audit_log`, `audit.read`). Les indicateurs passent
/// par `DashboardRepository` (mêmes RPC d'agrégation côté serveur).
class ReportsRepository {
  ReportsRepository(this._client);

  final SupabaseClient _client;

  /// Page suivante après [after] (curseur `created_at` + `id`).
  Future<List<AuditEntry>> fetchAudit(String businessId, {AuditEntry? after, String? action, int limit = 50}) =>
      guardSupabase(() async {
        final rows = await _client.rpc<List<dynamic>>(
          'get_audit_log',
          params: {
            'p_business_id': businessId,
            'p_limit': limit,
            if (after != null) 'p_before': after.cursor,
            if (after != null) 'p_before_id': after.id,
            'p_action': ?action,
          },
        );
        return rows.cast<Map<String, dynamic>>().map(AuditEntry.fromRow).toList();
      });
}
