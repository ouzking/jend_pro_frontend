import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../application/supplier_providers.dart';
import '../domain/supplier_models.dart';

/// Fournisseurs : à qui je dois combien.
class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final permissions = ref.watch(permissionsProvider);
    final query = ref.watch(supplierQueryProvider);
    final list = ref.watch(supplierListProvider);
    final balances = ref.watch(supplierBalancesProvider).value ?? const {};
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final canManage = permissions.can(Permission.suppliersManage);
    final canSeeDebts = permissions.can(Permission.purchasesRead);
    final totalDue = balances.values.fold<int>(0, (s, b) => s + b.amountDue);

    return Scaffold(
      appBar: AppBar(title: const Text('Fournisseurs')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              heroTag: 'new-supplier',
              onPressed: () => context.push(Routes.supplierNew),
              backgroundColor: p.brand,
              foregroundColor: p.textOnBrand,
              elevation: 2,
              icon: const Icon(Icons.add_business_outlined),
              label: Text('Fournisseur', style: JpTypography.label.copyWith(color: p.textOnBrand)),
            )
          : null,
      body: JpConstrained(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(supplierBalancesProvider);
            await ref.refresh(supplierListProvider.future).then<void>((_) {}, onError: (_) {});
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 500) ref.read(supplierListProvider.notifier).loadMore();
              return false;
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                if (canSeeDebts && totalDue > 0)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, JpSpacing.md),
                    sliver: SliverToBoxAdapter(
                      child: JpCard(
                        onTap: () => ref.read(supplierQueryProvider.notifier).segment(SupplierSegment.toPay),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(color: p.dangerSoft, borderRadius: JpRadius.all(JpRadius.md)),
                              child: Icon(Icons.local_shipping_outlined, color: p.danger),
                            ),
                            const SizedBox(width: JpSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Vous devez à vos fournisseurs',
                                    style: JpTypography.caption.copyWith(
                                      color: p.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  JpAmount(totalDue, currency: currency, style: JpTypography.title, color: p.danger),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, 0),
                  sliver: SliverToBoxAdapter(
                    child: JpTextField(
                      controller: _search,
                      hint: 'Nom, contact ou téléphone',
                      prefixIcon: Icons.search_rounded,
                      onChanged: (v) {
                        _debounce?.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 300),
                          () => ref.read(supplierQueryProvider.notifier).search(v),
                        );
                      },
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 60,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.md),
                      children: [
                        for (final (s, label) in [
                          (SupplierSegment.all, 'Tous'),
                          if (canSeeDebts) (SupplierSegment.toPay, 'À payer'),
                          (SupplierSegment.archived, 'Archivés'),
                        ]) ...[
                          ChoiceChip(
                            label: Text(label),
                            selected: query.segment == s,
                            onSelected: (_) => ref.read(supplierQueryProvider.notifier).segment(s),
                          ),
                          const SizedBox(width: JpSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                ),
                ...switch (list) {
                  AsyncValue(:final value?) when value.items.isEmpty => [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: query.text.isNotEmpty
                          ? const JpEmptyState(
                              icon: Icons.search_off_rounded,
                              tone: JpTone.neutral,
                              title: 'Aucun résultat',
                            )
                          : switch (query.segment) {
                              SupplierSegment.toPay => const JpEmptyState(
                                icon: Icons.verified_outlined,
                                tone: JpTone.success,
                                title: 'Aucune dette fournisseur',
                                message: 'Tous vos achats reçus sont payés.',
                              ),
                              SupplierSegment.archived => const JpEmptyState(
                                icon: Icons.inventory_outlined,
                                tone: JpTone.neutral,
                                title: 'Aucun fournisseur archivé',
                              ),
                              SupplierSegment.all => JpEmptyState(
                                icon: Icons.local_shipping_outlined,
                                title: 'Aucun fournisseur',
                                message:
                                    'Enregistrez vos fournisseurs pour suivre vos achats et ce que vous leur devez.',
                                actionLabel: canManage ? 'Ajouter un fournisseur' : null,
                                onAction: canManage ? () => context.push(Routes.supplierNew) : null,
                              ),
                            },
                    ),
                  ],
                  AsyncValue(:final value?) => [
                    SliverList.separated(
                      itemCount: value.items.length,
                      separatorBuilder: (_, _) => Divider(indent: JpSpacing.gutter + 56, color: p.border),
                      itemBuilder: (context, i) {
                        final s = value.items[i];
                        final due = balances[s.id]?.amountDue ?? 0;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: JpSpacing.gutter,
                            vertical: JpSpacing.xs,
                          ),
                          leading: JpAvatar(name: s.name, size: 44),
                          title: Text(s.name),
                          subtitle: Text(
                            [?s.contactName, if (s.phone != null) Formatters.phone(s.phone!)].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: due > 0
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('À payer', style: JpTypography.caption.copyWith(color: p.danger)),
                                    JpAmount(due, currency: currency, style: JpTypography.label, color: p.danger),
                                  ],
                                )
                              : null,
                          onTap: () => context.push(Routes.supplierDetail(s.id)),
                        );
                      },
                    ),
                  ],
                  AsyncError(:final error) => [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: JpErrorState(error: error, onRetry: () => ref.invalidate(supplierListProvider)),
                    ),
                  ],
                  _ => [const SliverToBoxAdapter(child: JpSkeletonList(itemCount: 6))],
                },
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
