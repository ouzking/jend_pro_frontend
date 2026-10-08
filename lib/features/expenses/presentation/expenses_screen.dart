import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../application/expense_providers.dart';
import '../domain/expense_models.dart';

/// Dépenses du mois, regroupées par jour.
class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final view = ref.watch(expenseViewProvider);
    final notifier = ref.read(expenseViewProvider.notifier);
    final list = ref.watch(expenseListProvider);
    final total = ref.watch(expenseMonthTotalProvider).value;
    final categories = ref.watch(expenseCategoriesProvider).value ?? const [];
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final canCreate = ref.watch(permissionsProvider).can(Permission.expensesCreate);
    final monthLabel = toBeginningOfSentenceCase(DateFormat('MMMM y', 'fr').format(view.month.first));

    return Scaffold(
      appBar: AppBar(title: const Text('Dépenses')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              heroTag: 'new-expense',
              onPressed: () => context.push(Routes.expenseNew),
              backgroundColor: p.brand,
              foregroundColor: p.textOnBrand,
              elevation: 2,
              icon: const Icon(Icons.add_rounded),
              label: Text('Dépense', style: JpTypography.label.copyWith(color: p.textOnBrand)),
            )
          : null,
      body: JpConstrained(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(expenseMonthTotalProvider);
            await ref.refresh(expenseListProvider.future).then<void>((_) {}, onError: (_) {});
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 500) ref.read(expenseListProvider.notifier).loadMore();
              return false;
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, 0),
                  sliver: SliverToBoxAdapter(
                    child: JpCard(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Mois précédent',
                                icon: const Icon(Icons.chevron_left_rounded),
                                onPressed: notifier.previous,
                              ),
                              Expanded(
                                child: Text(
                                  monthLabel,
                                  textAlign: TextAlign.center,
                                  style: JpTypography.titleSmall.copyWith(color: p.textPrimary),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Mois suivant',
                                icon: const Icon(Icons.chevron_right_rounded),
                                onPressed: notifier.canGoNext ? notifier.next : null,
                              ),
                            ],
                          ),
                          if (total != null) ...[
                            const SizedBox(height: JpSpacing.xs),
                            Text('Total du mois', style: JpTypography.caption.copyWith(color: p.textMuted)),
                            JpAmount(total, currency: currency, style: JpTypography.headline, color: p.accent),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (categories.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 60,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.md),
                        children: [
                          ChoiceChip(
                            label: const Text('Toutes'),
                            selected: view.categoryId == null,
                            onSelected: (_) => notifier.category(null),
                          ),
                          for (final c in categories) ...[
                            const SizedBox(width: JpSpacing.sm),
                            ChoiceChip(
                              avatar: Icon(c.icon, size: 16),
                              label: Text(c.name),
                              selected: view.categoryId == c.id,
                              onSelected: (v) => notifier.category(v ? c.id : null),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ...switch (list) {
                  AsyncValue(:final value?) when value.items.isEmpty => [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: JpEmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'Aucune dépense ce mois-ci',
                        message:
                            'Loyer, électricité, transport… Notez vos dépenses pour connaître votre vrai bénéfice.',
                        actionLabel: canCreate ? 'Ajouter une dépense' : null,
                        onAction: () => context.push(Routes.expenseNew),
                      ),
                    ),
                  ],
                  AsyncValue(:final value?) => [_grouped(context, value.items, currency)],
                  AsyncError(:final error) => [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: JpErrorState(error: error, onRetry: () => ref.invalidate(expenseListProvider)),
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

  Widget _grouped(BuildContext context, List<Expense> items, String currency) {
    final p = context.palette;
    final rows = <Object>[];
    DateTime? day;
    for (final e in items) {
      if (e.spentOn != day) {
        rows.add(e.spentOn);
        day = e.spentOn;
      }
      rows.add(e);
    }
    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        if (row is DateTime) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.lg, JpSpacing.gutter, JpSpacing.xs),
            child: Text(
              toBeginningOfSentenceCase(DateFormat('EEEE d MMMM', 'fr').format(row)).toUpperCase(),
              style: JpTypography.overline.copyWith(color: p.textMuted),
            ),
          );
        }
        final e = row as Expense;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: p.accentSoft, borderRadius: JpRadius.all(JpRadius.md)),
            child: Icon(e.category.icon, color: p.accent, size: 20),
          ),
          title: Text(e.description ?? e.categoryName ?? 'Dépense', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text([if (e.description != null) ?e.categoryName, e.method.label].join(' · ')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (e.receiptPath != null)
                Padding(
                  padding: const EdgeInsets.only(right: JpSpacing.sm),
                  child: Icon(Icons.attach_file_rounded, size: 16, color: p.textMuted),
                ),
              JpAmount(e.amount, currency: currency, style: JpTypography.label),
            ],
          ),
          onTap: () => context.push(Routes.expenseDetail(e.id)),
        );
      },
    );
  }
}

/// Montant formaté pour les annonces (utilisé par la fiche).
String expenseSummary(Expense e) => '${e.categoryName ?? 'Dépense'}, ${Formatters.money(e.amount)}';
