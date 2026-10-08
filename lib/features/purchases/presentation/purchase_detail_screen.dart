import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/domain/payment_method.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/formatting/input_formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../../products/presentation/widgets/product_form_fields.dart';
import '../application/purchase_providers.dart';
import '../domain/purchase_models.dart';

class PurchaseDetailScreen extends ConsumerWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchase = ref.watch(purchaseDetailProvider(purchaseId));
    return Scaffold(
      appBar: AppBar(title: Text(purchase.value?.number ?? 'Achat')),
      body: JpAsyncView<Purchase>(
        value: purchase,
        onRetry: () => ref.invalidate(purchaseDetailProvider(purchaseId)),
        data: (p) => _Body(purchase: p),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.purchase});

  final Purchase purchase;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;

  Purchase get p => widget.purchase;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) JpOverlays.toast(context, success, tone: JpTone.success);
    } on AppFailure catch (f) {
      if (mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _receive() async {
    final ok = await JpOverlays.confirm(
      context,
      title: 'Réceptionner ${p.number} ?',
      message: 'Le stock sera augmenté et les coûts d’achat recalculés (coût moyen). Cette action est définitive.',
      confirmLabel: 'Réceptionner',
      icon: Icons.inventory_2_outlined,
    );
    if (ok) await _run(() => ref.read(purchaseActionsProvider).receive(p), 'Achat réceptionné : stock mis à jour.');
  }

  Future<void> _cancel() async {
    final controller = TextEditingController();
    final reason = await JpOverlays.sheet<String>(
      context,
      title: 'Annuler ${p.number}',
      subtitle: 'Possible tant que l’achat n’est ni réceptionné ni payé.',
      child: Builder(
        builder: (sheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            JpTextField(label: 'Motif', controller: controller, autofocus: true, maxLength: 300),
            const SizedBox(height: JpSpacing.xl),
            JpButton(
              label: 'Annuler l’achat',
              variant: JpButtonVariant.danger,
              onPressed: () {
                if (controller.text.trim().isNotEmpty) Navigator.of(sheet).pop(controller.text.trim());
              },
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (reason != null) await _run(() => ref.read(purchaseActionsProvider).cancel(p, reason), 'Achat annulé.');
  }

  Future<void> _pay() async {
    final amount = TextEditingController(text: AmountInputFormatter.format(p.remaining));
    final reference = TextEditingController();
    var method = PaymentMethod.cash;
    final result = await JpOverlays.sheet<(int, PaymentMethod, String)>(
      context,
      title: p.status == PurchaseStatus.received ? 'Payer le fournisseur' : 'Verser un acompte',
      subtitle: 'Reste à payer : ${Formatters.money(p.remaining)}',
      child: StatefulBuilder(
        builder: (sheet, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AmountField(label: 'Montant', controller: amount, enabled: true),
            const SizedBox(height: JpSpacing.lg),
            Wrap(
              spacing: JpSpacing.sm,
              runSpacing: JpSpacing.sm,
              children: [
                for (final m in const [
                  PaymentMethod.cash,
                  PaymentMethod.wave,
                  PaymentMethod.orangeMoney,
                  PaymentMethod.bankTransfer,
                  PaymentMethod.cheque,
                ])
                  ChoiceChip(
                    avatar: Icon(m.icon, size: 16),
                    label: Text(m.label),
                    selected: method == m,
                    onSelected: (_) => setSheet(() => method = m),
                  ),
              ],
            ),
            const SizedBox(height: JpSpacing.lg),
            JpTextField(label: 'Référence (facultatif)', controller: reference),
            const SizedBox(height: JpSpacing.xl),
            JpButton(
              label: 'Enregistrer le paiement',
              onPressed: () {
                final a = AmountInputFormatter.parse(amount.text) ?? 0;
                if (a <= 0 || a > p.remaining) {
                  JpOverlays.toast(sheet, 'Montant entre 1 et ${Formatters.money(p.remaining)}.', tone: JpTone.warning);
                  return;
                }
                Navigator.of(sheet).pop((a, method, reference.text));
              },
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    reference.dispose();
    if (result == null) return;
    final (a, m, ref_) = result;
    await _run(
      () => ref.read(purchaseActionsProvider).pay(p, amount: a, method: m, reference: ref_),
      'Paiement de ${Formatters.money(a)} enregistré.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final permissions = ref.watch(permissionsProvider);
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final tone = switch (p.status) {
      PurchaseStatus.draft => JpTone.neutral,
      PurchaseStatus.ordered => JpTone.info,
      PurchaseStatus.received => JpTone.success,
      PurchaseStatus.cancelled => JpTone.danger,
    };
    final editable = p.status.editable && permissions.can(Permission.purchasesCreate);
    final canReceive = p.status.editable && permissions.can(Permission.purchasesReceive);
    final canPay =
        p.status != PurchaseStatus.cancelled && p.remaining > 0 && permissions.can(Permission.purchasesPayments);
    final canCancel = p.status.editable && p.amountPaid == 0 && permissions.can(Permission.purchasesCancel);

    return ListView(
      padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, JpSpacing.huge),
      children: [
        JpConstrained(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.supplierName ?? 'Sans fournisseur',
                          style: JpTypography.title.copyWith(color: palette.textPrimary),
                        ),
                        Text(
                          [
                            'Créé le ${Formatters.date(p.createdAt)}',
                            if (p.receivedAt != null) 'reçu le ${Formatters.date(p.receivedAt!)}',
                            if (p.supplierReference != null) 'facture ${p.supplierReference}',
                          ].join(' · '),
                          style: JpTypography.bodySmall.copyWith(color: palette.textMuted),
                        ),
                      ],
                    ),
                  ),
                  JpBadge(label: p.status.label, tone: tone, dot: true),
                ],
              ),
              if (p.status == PurchaseStatus.cancelled && p.cancelReason != null) ...[
                const SizedBox(height: JpSpacing.md),
                JpBanner(message: 'Annulé : ${p.cancelReason}', tone: JpTone.danger, icon: Icons.block_rounded),
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: JpSpacing.md),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: JpSpacing.xl),
              JpCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < p.lines.length; i++) ...[
                      if (i > 0) Divider(color: palette.border, height: 1),
                      ListTile(
                        title: Text(p.lines[i].productName),
                        subtitle: Text(
                          '${Formatters.quantity(p.lines[i].quantity)} ${p.lines[i].unit} × '
                          '${Formatters.money(p.lines[i].unitCost, currency: currency)}',
                        ),
                        trailing: JpAmount(p.lines[i].lineTotal, currency: currency, style: JpTypography.label),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: JpSpacing.md),
              JpCard(
                child: Column(
                  children: [
                    if (p.discount > 0) ...[
                      _Line('Sous-total', p.subtotal, currency),
                      _Line('Remise', -p.discount, currency),
                    ],
                    _Line('Total', p.total, currency, strong: true),
                    _Line('Payé', p.amountPaid, currency),
                    if (p.status != PurchaseStatus.cancelled)
                      _Line(
                        'Reste à payer',
                        p.remaining,
                        currency,
                        color: p.remaining > 0 ? palette.danger : palette.success,
                      ),
                  ],
                ),
              ),
              if (p.payments.isNotEmpty) ...[
                const SizedBox(height: JpSpacing.xl),
                const JpSectionHeader(title: 'Paiements'),
                for (final pay in p.payments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(pay.method.icon, color: palette.textMuted),
                    title: Text(pay.method.label),
                    subtitle: Text(Formatters.dateTime(pay.paidAt)),
                    trailing: JpAmount(pay.amount, currency: currency, style: JpTypography.label),
                  ),
              ],
              const SizedBox(height: JpSpacing.xxl),
              if (canReceive)
                JpButton(
                  label: 'Réceptionner la marchandise',
                  icon: Icons.inventory_2_outlined,
                  onPressed: _busy ? null : _receive,
                ),
              if (canPay) ...[
                const SizedBox(height: JpSpacing.sm),
                JpButton(
                  label: p.status == PurchaseStatus.received ? 'Payer le fournisseur' : 'Verser un acompte',
                  variant: canReceive ? JpButtonVariant.secondary : JpButtonVariant.primary,
                  icon: Icons.payments_outlined,
                  onPressed: _busy ? null : _pay,
                ),
              ],
              if (editable || (p.status == PurchaseStatus.draft && permissions.can(Permission.purchasesCreate)))
                const SizedBox(height: JpSpacing.sm),
              Row(
                children: [
                  if (editable)
                    Expanded(
                      child: JpButton.outline(
                        label: 'Modifier',
                        icon: Icons.edit_outlined,
                        size: JpButtonSize.medium,
                        onPressed: _busy ? null : () => context.push(Routes.purchaseEdit(p.id)),
                      ),
                    ),
                  if (p.status == PurchaseStatus.draft && permissions.can(Permission.purchasesCreate)) ...[
                    const SizedBox(width: JpSpacing.sm),
                    Expanded(
                      child: JpButton.outline(
                        label: 'Commander',
                        icon: Icons.send_outlined,
                        size: JpButtonSize.medium,
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () => ref.read(purchaseActionsProvider).order(p),
                                'Achat marqué comme commandé.',
                              ),
                      ),
                    ),
                  ],
                ],
              ),
              if (canCancel)
                Padding(
                  padding: const EdgeInsets.only(top: JpSpacing.md),
                  child: Center(
                    child: TextButton(
                      onPressed: _busy ? null : _cancel,
                      style: TextButton.styleFrom(foregroundColor: palette.danger),
                      child: const Text('Annuler cet achat'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.amount, this.currency, {this.strong = false, this.color});

  final String label;
  final int amount;
  final String currency;
  final bool strong;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: (strong ? JpTypography.titleSmall : JpTypography.body).copyWith(
                color: strong ? p.textPrimary : p.textSecondary,
              ),
            ),
          ),
          JpAmount(
            amount,
            currency: currency,
            style: strong ? JpTypography.title : JpTypography.bodyStrong,
            color: color,
          ),
        ],
      ),
    );
  }
}
