import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../application/expense_providers.dart';
import '../domain/expense_models.dart';

class ExpenseDetailScreen extends ConsumerWidget {
  const ExpenseDetailScreen({super.key, required this.expenseId});

  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expense = ref.watch(expenseDetailProvider(expenseId));
    final canManage = ref.watch(permissionsProvider).can(Permission.expensesManage);
    final e = expense.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dépense'),
        actions: [
          if (e != null && canManage) ...[
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push(Routes.expenseEdit(e.id)),
            ),
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await JpOverlays.confirm(
                  context,
                  title: 'Supprimer cette dépense ?',
                  message: 'Elle disparaît des totaux. La suppression reste tracée dans le journal d’audit.',
                  confirmLabel: 'Supprimer',
                  destructive: true,
                );
                if (!ok) return;
                try {
                  await ref.read(expenseActionsProvider).delete(e);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    JpOverlays.toast(context, 'Dépense supprimée.', tone: JpTone.success);
                  }
                } on AppFailure catch (f) {
                  if (context.mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
                }
              },
            ),
          ],
        ],
      ),
      body: JpAsyncView<Expense>(
        value: expense,
        onRetry: () => ref.invalidate(expenseDetailProvider(expenseId)),
        data: (e) => _Body(expense: e),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final e = expense;
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    return ListView(
      padding: const EdgeInsets.all(JpSpacing.gutter),
      children: [
        JpConstrained(
          maxWidth: JpSpacing.maxFormWidth + 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: p.accentSoft, borderRadius: JpRadius.all(JpRadius.lg)),
                  child: Icon(e.category.icon, color: p.accent, size: 30),
                ),
              ),
              const SizedBox(height: JpSpacing.md),
              Center(
                child: JpAmount(e.amount, currency: currency, style: JpTypography.display),
              ),
              Center(
                child: Text(
                  '${e.categoryName ?? 'Dépense'} · ${Formatters.date(e.spentOn)}',
                  style: JpTypography.body.copyWith(color: p.textSecondary),
                ),
              ),
              const SizedBox(height: JpSpacing.xl),
              JpCard(
                child: Column(
                  children: [
                    _Row(label: 'Payée par', value: e.method.label),
                    if (e.description != null) _Row(label: 'Description', value: e.description!),
                    _Row(label: 'Saisie le', value: Formatters.dateTime(e.createdAt)),
                  ],
                ),
              ),
              if (e.receiptPath != null) ...[
                const SizedBox(height: JpSpacing.xl),
                const JpSectionHeader(title: 'Justificatif'),
                const SizedBox(height: JpSpacing.sm),
                if (e.receiptPath!.endsWith('.pdf'))
                  const JpBanner(
                    message: 'Justificatif PDF joint (affichage à venir).',
                    icon: Icons.picture_as_pdf_outlined,
                  )
                else
                  ClipRRect(
                    borderRadius: JpRadius.all(JpRadius.lg),
                    child: ref
                        .watch(receiptUrlProvider(e.receiptPath!))
                        .when(
                          data: (url) => InteractiveViewer(
                            child: Image.network(
                              url,
                              fit: BoxFit.contain,
                              semanticLabel: 'Justificatif de la dépense',
                              errorBuilder: (_, _, _) =>
                                  const JpBanner(message: 'Justificatif indisponible.', tone: JpTone.warning),
                            ),
                          ),
                          loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                          error: (err, _) => JpErrorState(error: err),
                        ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: JpSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: JpTypography.body.copyWith(color: p.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: JpTypography.bodyStrong.copyWith(color: p.textPrimary)),
          ),
        ],
      ),
    );
  }
}
