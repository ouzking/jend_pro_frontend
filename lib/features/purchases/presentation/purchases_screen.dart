import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../../suppliers/presentation/supplier_detail_screen.dart';
import '../application/purchase_providers.dart';
import '../domain/purchase_models.dart';

class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final segment = ref.watch(purchaseSegmentProvider);
    final list = ref.watch(purchaseListProvider);
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final canCreate = ref.watch(permissionsProvider).can(Permission.purchasesCreate);

    return Scaffold(
      appBar: AppBar(title: const Text('Achats')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              heroTag: 'new-purchase',
              onPressed: () => context.push(Routes.purchaseNew()),
              backgroundColor: p.brand,
              foregroundColor: p.textOnBrand,
              elevation: 2,
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: Text('Achat', style: JpTypography.label.copyWith(color: p.textOnBrand)),
            )
          : null,
      body: JpConstrained(
        child: Column(
          children: [
            SizedBox(
              height: 60,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.md),
                children: [
                  for (final (s, label) in const [
                    (PurchaseSegment.all, 'Tous'),
                    (PurchaseSegment.open, 'En cours'),
                    (PurchaseSegment.received, 'Reçus'),
                    (PurchaseSegment.unpaid, 'À payer'),
                  ]) ...[
                    ChoiceChip(
                      label: Text(label),
                      selected: segment == s,
                      onSelected: (_) => ref.read(purchaseSegmentProvider.notifier).select(s),
                    ),
                    const SizedBox(width: JpSpacing.sm),
                  ],
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(purchaseListProvider.future).then<void>((_) {}, onError: (_) {}),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.extentAfter < 500) ref.read(purchaseListProvider.notifier).loadMore();
                    return false;
                  },
                  child: JpAsyncView(
                    value: list,
                    onRetry: () => ref.invalidate(purchaseListProvider),
                    data: (page) => page.items.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 60),
                              JpEmptyState(
                                icon: Icons.local_shipping_outlined,
                                tone: segment == PurchaseSegment.unpaid ? JpTone.success : JpTone.brand,
                                title: switch (segment) {
                                  PurchaseSegment.unpaid => 'Tout est payé',
                                  PurchaseSegment.open => 'Aucun achat en cours',
                                  _ => 'Aucun achat',
                                },
                                message: segment == PurchaseSegment.all
                                    ? 'Enregistrez vos achats fournisseurs : la réception met le stock et les coûts à jour.'
                                    : null,
                                actionLabel: canCreate && segment == PurchaseSegment.all ? 'Nouvel achat' : null,
                                onAction: () => context.push(Routes.purchaseNew()),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 120),
                            itemCount: page.items.length + (page.loadingMore ? 1 : 0),
                            separatorBuilder: (_, _) => Divider(color: p.border, indent: JpSpacing.gutter),
                            itemBuilder: (context, i) {
                              if (i >= page.items.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(JpSpacing.lg),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              final item = page.items[i];
                              return PurchaseSummaryTile(
                                purchase: item,
                                currency: currency,
                                showSupplier: true,
                                onTap: () => context.push(Routes.purchaseDetail(item.id)),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
