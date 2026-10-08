import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../application/pos_providers.dart';
import '../domain/sale_models.dart';
import 'widgets/pos_widgets.dart';

/// Historique des ventes : toutes (`sales.read`) ou les siennes.
class SalesHistoryScreen extends ConsumerWidget {
  const SalesHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final history = ref.watch(salesHistoryProvider);
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final own = !ref.watch(permissionsProvider).can(Permission.salesRead);

    return Scaffold(
      appBar: AppBar(title: Text(own ? 'Mes ventes' : 'Ventes')),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(pendingSalesProvider.notifier).sync();
          ref.invalidate(salesHistoryProvider);
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 500) ref.read(salesHistoryProvider.notifier).loadMore();
            return false;
          },
          child: JpAsyncView(
            value: history,
            onRetry: () => ref.invalidate(salesHistoryProvider),
            data: (page) {
              if (page.items.isEmpty) {
                return ListView(
                  children: const [
                    SizedBox(height: 80),
                    JpEmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Aucune vente',
                      message: 'Les ventes enregistrées apparaîtront ici.',
                    ),
                  ],
                );
              }
              // Regroupement par jour (en-têtes « Aujourd'hui », « Hier »…).
              final rows = <Object>[];
              DateTime? day;
              for (final s in page.items) {
                final local = s.soldAt.toLocal();
                final d = DateTime(local.year, local.month, local.day);
                if (d != day) {
                  rows.add(d);
                  day = d;
                }
                rows.add(s);
              }
              return JpConstrained(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: JpSpacing.huge),
                  itemCount: rows.length + 2,
                  itemBuilder: (context, i) {
                    if (i == 0) return const PendingSalesBanner();
                    if (i == rows.length + 1) {
                      return page.loadingMore
                          ? const Padding(
                              padding: EdgeInsets.all(JpSpacing.lg),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : const SizedBox(height: JpSpacing.lg);
                    }
                    final row = rows[i - 1];
                    if (row is DateTime) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                          JpSpacing.gutter,
                          JpSpacing.lg,
                          JpSpacing.gutter,
                          JpSpacing.xs,
                        ),
                        child: Text(
                          _dayLabel(row).toUpperCase(),
                          style: JpTypography.overline.copyWith(color: p.textMuted),
                        ),
                      );
                    }
                    final sale = row as Sale;
                    return _SaleRow(
                      sale: sale,
                      currency: currency,
                      onTap: () => context.push(Routes.saleDetail(sale.id)),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Aujourd’hui';
    if (diff == 1) return 'Hier';
    return Formatters.date(day);
  }
}

class _SaleRow extends StatelessWidget {
  const _SaleRow({required this.sale, required this.currency, required this.onTap});

  final Sale sale;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final first = sale.lines.isEmpty ? null : sale.lines.first;
    final title = first == null
        ? sale.number
        : '${first.productName}${sale.itemCount > 1 ? ' +${sale.itemCount - 1}' : ''}';
    final method = sale.payments.where((x) => x.incoming).map((x) => x.method.label).toSet().join(' + ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sale.cancelled ? p.dangerSoft : p.brandSoft,
                borderRadius: JpRadius.all(JpRadius.md),
              ),
              child: Text(
                Formatters.productMonogram(first?.productName ?? 'V'),
                style: JpTypography.label.copyWith(color: sale.cancelled ? p.danger : p.brandStrong, fontSize: 13),
              ),
            ),
            const SizedBox(width: JpSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: JpTypography.bodyStrong.copyWith(
                      color: sale.cancelled ? p.textMuted : p.textPrimary,
                      fontSize: 14,
                      decoration: sale.cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    [
                      Formatters.time(sale.soldAt),
                      sale.number,
                      if (sale.cancelled)
                        'Annulée'
                      else if (sale.creditAmount > 0)
                        'Crédit ${Formatters.money(sale.creditAmount, currency: currency)}'
                      else if (method.isNotEmpty)
                        method,
                      ?sale.customerName,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: JpTypography.caption.copyWith(color: sale.cancelled ? p.danger : p.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: JpSpacing.sm),
            JpAmount(
              sale.total,
              currency: currency,
              style: JpTypography.label,
              color: sale.cancelled ? p.textMuted : null,
            ),
          ],
        ),
      ),
    );
  }
}
