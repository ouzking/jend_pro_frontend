import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/contact/contact_links.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/pagination/paged.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../application/customer_providers.dart';
import '../domain/customer_models.dart';
import 'widgets/customer_sheets.dart';

/// Fiche client : situation financière d'abord, puis relevé et achats.
class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customerDetailProvider(customerId));
    final canManage = ref.watch(permissionsProvider).can(Permission.customersManage);
    final c = customer.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Client'),
        actions: [
          if (c != null && canManage)
            PopupMenuButton<String>(
              tooltip: 'Plus d’options',
              onSelected: (v) => _menu(context, ref, c, v),
              itemBuilder: (_) => [
                if (!c.archived) const PopupMenuItem(value: 'edit', child: Text('Modifier la fiche')),
                if (!c.archived) const PopupMenuItem(value: 'limit', child: Text('Plafond de crédit')),
                if (!c.archived) const PopupMenuItem(value: 'adjust', child: Text('Ajuster le solde')),
                PopupMenuItem(value: 'archive', child: Text(c.archived ? 'Réactiver' : 'Archiver')),
              ],
            ),
        ],
      ),
      body: JpAsyncView<Customer>(
        value: customer,
        onRetry: () => ref.invalidate(customerDetailProvider(customerId)),
        data: (c) => _Body(customer: c),
      ),
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, Customer c, String action) async {
    switch (action) {
      case 'edit':
        context.push(Routes.customerEdit(c.id));
      case 'limit':
        await showCreditLimitSheet(context, c);
      case 'adjust':
        await showAdjustSheet(context, c);
      case 'archive':
        if (!c.archived && c.owes) {
          JpOverlays.toast(context, '${c.name} doit encore de l’argent : impossible d’archiver.', tone: JpTone.warning);
          return;
        }
        final ok = await JpOverlays.confirm(
          context,
          title: c.archived ? 'Réactiver ce client ?' : 'Archiver ce client ?',
          message: c.archived
              ? 'Il sera de nouveau proposé à la caisse.'
              : 'Il ne sera plus proposé à la caisse. Son historique est conservé.',
          confirmLabel: c.archived ? 'Réactiver' : 'Archiver',
          destructive: !c.archived,
        );
        if (!ok) return;
        try {
          await ref.read(customerActionsProvider).setArchived(c, archived: !c.archived);
          if (context.mounted) {
            JpOverlays.toast(context, c.archived ? 'Client réactivé.' : 'Client archivé.', tone: JpTone.success);
          }
        } on AppFailure catch (f) {
          if (context.mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
        }
    }
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final c = customer;
    final business = ref.watch(activeBusinessProvider);
    final currency = business?.currencyCode ?? 'XOF';
    final permissions = ref.watch(permissionsProvider);
    final canCollect = permissions.can(Permission.customersPayments) && c.owes && !c.archived;
    final statement = ref.watch(customerStatementProvider(c.id));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(customerDetailProvider(c.id));
        ref.invalidate(customerStatementProvider(c.id));
        ref.invalidate(customerSalesProvider(c.id));
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 400) ref.read(customerStatementProvider(c.id).notifier).loadMore();
          return false;
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, JpSpacing.huge),
          children: [
            JpConstrained(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      JpAvatar(name: c.name, size: JpSize.avatarLg),
                      const SizedBox(width: JpSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name, style: JpTypography.title.copyWith(color: p.textPrimary)),
                            if (c.phone != null)
                              Text(
                                Formatters.phone(c.phone!),
                                style: JpTypography.body.copyWith(color: p.textSecondary),
                              ),
                            if (c.archived) ...[
                              const SizedBox(height: JpSpacing.xs),
                              const JpBadge(label: 'Archivé', icon: Icons.archive_outlined),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (c.phone != null) ...[
                    const SizedBox(height: JpSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: JpButton.outline(
                            label: 'Appeler',
                            icon: Icons.call_outlined,
                            size: JpButtonSize.medium,
                            onPressed: () => ContactLinks.call(c.phone!),
                          ),
                        ),
                        const SizedBox(width: JpSpacing.sm),
                        Expanded(
                          child: JpButton.outline(
                            label: 'WhatsApp',
                            icon: Icons.chat_outlined,
                            size: JpButtonSize.medium,
                            onPressed: () => ContactLinks.whatsApp(
                              c.phone!,
                              message: c.owes
                                  ? 'Bonjour ${c.name}, petit rappel de ${business?.businessName ?? 'votre boutique'} : '
                                        'votre solde est de ${Formatters.money(c.balance, currency: currency)}. Merci !'
                                  : 'Bonjour ${c.name}, ',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: JpSpacing.xl),
                  _BalanceCard(customer: c, currency: currency),
                  if (canCollect) ...[
                    const SizedBox(height: JpSpacing.md),
                    JpButton(
                      label: 'Encaisser un règlement',
                      icon: Icons.payments_outlined,
                      onPressed: () => showPaymentSheet(context, c),
                    ),
                  ],
                  if (c.email != null || c.address != null || c.notes != null) ...[
                    const SizedBox(height: JpSpacing.xl),
                    JpCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (c.email != null) _Info(icon: Icons.alternate_email_rounded, text: c.email!),
                          if (c.address != null) _Info(icon: Icons.place_outlined, text: c.address!),
                          if (c.notes != null) _Info(icon: Icons.sticky_note_2_outlined, text: c.notes!),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: JpSpacing.xxl),
                  const JpSectionHeader(title: 'Relevé de compte'),
                  _Statement(value: statement, currency: currency),
                  const SizedBox(height: JpSpacing.xl),
                  if (permissions.canSeeSales) _Purchases(customerId: c.id, currency: currency),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.customer, required this.currency});

  final Customer customer;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = customer;
    final usage = c.creditUsage;
    final tone = p.tone(c.owes ? JpTone.warning : JpTone.success);
    return JpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.owes ? 'Montant dû' : 'Situation',
            style: JpTypography.caption.copyWith(color: p.textSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: JpSpacing.xs),
          if (c.owes)
            JpAmount(c.balance, currency: currency, style: JpTypography.display, color: tone.foreground)
          else
            Text('À jour', style: JpTypography.headline.copyWith(color: tone.foreground)),
          const SizedBox(height: JpSpacing.md),
          if (usage != null) ...[
            ClipRRect(
              borderRadius: JpRadius.all(JpRadius.pill),
              child: LinearProgressIndicator(
                value: usage,
                minHeight: 6,
                backgroundColor: p.surfaceMuted,
                color: usage >= 0.9 ? p.danger : (usage >= 0.6 ? p.warning : p.success),
              ),
            ),
            const SizedBox(height: JpSpacing.xs),
          ],
          Text(
            c.unlimitedCredit
                ? 'Crédit sans plafond'
                : c.creditLimit == 0
                ? 'Pas de crédit autorisé'
                : 'Plafond ${Formatters.money(c.creditLimit!, currency: currency)} · '
                      'disponible ${Formatters.money(c.creditAvailable!, currency: currency)}',
            style: JpTypography.bodySmall.copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: JpSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: p.textMuted),
          const SizedBox(width: JpSpacing.md),
          Expanded(
            child: Text(text, style: JpTypography.body.copyWith(color: p.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _Statement extends StatelessWidget {
  const _Statement({required this.value, required this.currency});

  final AsyncValue<Paged<CustomerTransaction>> value;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final page = value.value;
    if (page == null) {
      return value.hasError
          ? JpErrorState(error: value.error!)
          : const Padding(
              padding: EdgeInsets.all(JpSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            );
    }
    if (page.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: JpSpacing.lg),
        child: Text(
          'Aucune opération à crédit pour l’instant.',
          style: JpTypography.bodySmall.copyWith(color: p.textMuted),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < page.items.length; i++) ...[
          if (i > 0) Divider(color: p.border),
          _TransactionTile(t: page.items[i], currency: currency),
        ],
        if (page.loadingMore) const Padding(padding: EdgeInsets.all(JpSpacing.lg), child: CircularProgressIndicator()),
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.t, required this.currency});

  final CustomerTransaction t;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final increases = t.amount > 0;
    // + dette = à surveiller (ambre) ; − dette = rentrée (vert).
    final tone = p.tone(increases ? JpTone.warning : JpTone.success);
    return InkWell(
      onTap: t.saleId == null ? null : () => context.push(Routes.saleDetail(t.saleId!)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: JpSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: tone.background, borderRadius: JpRadius.all(JpRadius.sm)),
              child: Icon(t.type.icon, size: 18, color: tone.foreground),
            ),
            const SizedBox(width: JpSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.saleNumber == null ? t.type.label : '${t.type.label} · ${t.saleNumber}',
                    style: JpTypography.bodyStrong.copyWith(color: p.textPrimary, fontSize: 14),
                  ),
                  if (t.note?.isNotEmpty ?? false)
                    Text(t.note!, style: JpTypography.bodySmall.copyWith(color: p.textSecondary)),
                  Text(Formatters.dateTime(t.createdAt), style: JpTypography.caption.copyWith(color: p.textMuted)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${increases ? '+' : '−'}${Formatters.money(t.amount.abs(), currency: currency)}',
                  style: JpTypography.numeric(JpTypography.label).copyWith(color: tone.foreground),
                ),
                Text(
                  'Solde ${Formatters.money(t.balanceAfter, currency: currency)}',
                  style: JpTypography.numeric(JpTypography.caption).copyWith(color: p.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Purchases extends ConsumerWidget {
  const _Purchases({required this.customerId, required this.currency});

  final String customerId;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final sales = ref.watch(customerSalesProvider(customerId));
    final list = sales.value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const JpSectionHeader(title: 'Achats récents'),
        if (sales.isLoading && list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(JpSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (list.isEmpty)
          Text('Aucun achat enregistré.', style: JpTypography.bodySmall.copyWith(color: p.textMuted))
        else
          JpCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) Divider(color: p.border, height: 1),
                  ListTile(
                    onTap: () => context.push(Routes.saleDetail(list[i].id)),
                    title: Text(
                      '${list[i].number} · ${Formatters.date(list[i].soldAt)}',
                      style: TextStyle(decoration: list[i].cancelled ? TextDecoration.lineThrough : null),
                    ),
                    subtitle: Text(
                      list[i].cancelled
                          ? 'Annulée'
                          : list[i].creditAmount > 0
                          ? 'Dont ${Formatters.money(list[i].creditAmount, currency: currency)} à crédit'
                          : 'Payée',
                    ),
                    trailing: JpAmount(list[i].total, currency: currency, style: JpTypography.label),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
