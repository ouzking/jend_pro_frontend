import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/domain/payment_method.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../../dashboard/application/dashboard_controller.dart';
import '../../documents/presentation/receipt_actions.dart';
import '../../inventory/application/inventory_providers.dart';
import '../../products/application/catalog_providers.dart';
import '../application/pos_providers.dart';
import '../data/sales_repository.dart';
import '../domain/sale_models.dart';

/// Reçu d'une vente (valeurs figées par le serveur) : impression, partage,
/// annulation.
class SaleDetailScreen extends ConsumerWidget {
  const SaleDetailScreen({super.key, required this.saleId});

  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sale = ref.watch(saleDetailProvider(saleId));
    return Scaffold(
      appBar: AppBar(title: Text(sale.value?.number ?? 'Vente')),
      body: JpAsyncView<Sale>(
        value: sale,
        onRetry: () => ref.invalidate(saleDetailProvider(saleId)),
        data: (s) => _Receipt(sale: s),
      ),
    );
  }
}

class _Receipt extends ConsumerWidget {
  const _Receipt({required this.sale});

  final Sale sale;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final result = await JpOverlays.sheet<bool>(
      context,
      title: 'Annuler la vente ${sale.number}',
      subtitle: 'Le stock est remis en place et le client remboursé. Cette action est définitive.',
      child: _CancelForm(sale: sale),
    );
    if (result == true && context.mounted) {
      JpOverlays.toast(context, 'Vente annulée.', tone: JpTone.success);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final business = ref.watch(activeBusinessProvider);
    final currency = business?.currencyCode ?? 'XOF';
    final canCancel = ref.watch(permissionsProvider).can(Permission.salesCancel) && !sale.cancelled;
    final incoming = sale.payments.where((x) => x.incoming).toList();
    final refunds = sale.payments.where((x) => !x.incoming).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, JpSpacing.huge),
      children: [
        JpConstrained(
          maxWidth: JpSpacing.maxFormWidth + 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sale.cancelled)
                Padding(
                  padding: const EdgeInsets.only(bottom: JpSpacing.lg),
                  child: JpBanner(
                    tone: JpTone.danger,
                    icon: Icons.block_rounded,
                    message:
                        'Vente annulée${sale.cancelledAt == null ? '' : ' le ${Formatters.dateTime(sale.cancelledAt!)}'}'
                        '${sale.cancelReason == null ? '' : ' · ${sale.cancelReason}'}',
                  ),
                ),
              JpCard(
                padding: const EdgeInsets.all(JpSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: JpLogo(size: 26)),
                    const SizedBox(height: JpSpacing.sm),
                    Text(
                      business?.businessName ?? '',
                      textAlign: TextAlign.center,
                      style: JpTypography.titleSmall.copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: JpSpacing.xs),
                    Text(
                      '${sale.number} · ${Formatters.dateTime(sale.soldAt)}',
                      textAlign: TextAlign.center,
                      style: JpTypography.caption.copyWith(color: p.textMuted),
                    ),
                    if (sale.customerName != null)
                      Text(
                        'Client : ${sale.customerName}',
                        textAlign: TextAlign.center,
                        style: JpTypography.caption.copyWith(color: p.textSecondary),
                      ),
                    const SizedBox(height: JpSpacing.lg),
                    _Dashed(color: p.borderStrong),
                    const SizedBox(height: JpSpacing.md),
                    for (final l in sale.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: JpSpacing.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.productName,
                                    style: JpTypography.bodyStrong.copyWith(color: p.textPrimary, fontSize: 14),
                                  ),
                                  Text(
                                    '${Formatters.quantity(l.quantity)} × ${Formatters.money(l.unitPrice, currency: currency)}'
                                    '${l.discount > 0 ? ' · remise ${Formatters.money(l.discount, currency: currency)}' : ''}',
                                    style: JpTypography.caption.copyWith(color: p.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            JpAmount(l.lineTotal, currency: currency, style: JpTypography.label),
                          ],
                        ),
                      ),
                    const SizedBox(height: JpSpacing.md),
                    _Dashed(color: p.borderStrong),
                    const SizedBox(height: JpSpacing.md),
                    if (sale.discount > 0) ...[
                      _Line('Sous-total', sale.subtotal, currency),
                      _Line('Remise', -sale.discount, currency),
                    ],
                    _Line('Total', sale.total, currency, strong: true),
                    const SizedBox(height: JpSpacing.sm),
                    for (final pay in incoming) _Line(pay.method.label, pay.amount, currency, muted: true),
                    if (sale.creditAmount > 0) _Line('À crédit', sale.creditAmount, currency, muted: true),
                    for (final r in refunds) _Line('Remboursé (${r.method.label})', -r.amount, currency, muted: true),
                    const SizedBox(height: JpSpacing.lg),
                    Text(
                      'Merci de votre visite !',
                      textAlign: TextAlign.center,
                      style: JpTypography.caption.copyWith(color: p.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: JpSpacing.lg),
              ReceiptActions(sale: sale),
              if (canCancel) ...[
                const SizedBox(height: JpSpacing.xxl),
                JpButton.outline(
                  label: 'Annuler la vente',
                  icon: Icons.undo_rounded,
                  onPressed: () => _cancel(context, ref),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.amount, this.currency, {this.strong = false, this.muted = false});

  final String label;
  final int amount;
  final String currency;
  final bool strong;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: (strong ? JpTypography.titleSmall : JpTypography.bodySmall).copyWith(
                color: muted ? p.textMuted : p.textPrimary,
              ),
            ),
          ),
          JpAmount(
            amount,
            currency: currency,
            style: strong ? JpTypography.title : JpTypography.bodySmall,
            color: muted ? p.textMuted : null,
          ),
        ],
      ),
    );
  }
}

/// Séparateur pointillé « ticket de caisse ».
class _Dashed extends StatelessWidget {
  const _Dashed({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final count = (c.maxWidth / 8).floor();
      return Row(
        children: List.generate(
          count,
          (_) => Expanded(
            child: Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 2), color: color),
          ),
        ),
      );
    },
  );
}

class _CancelForm extends ConsumerStatefulWidget {
  const _CancelForm({required this.sale});

  final Sale sale;

  @override
  ConsumerState<_CancelForm> createState() => _CancelFormState();
}

class _CancelFormState extends ConsumerState<_CancelForm> {
  final _reason = TextEditingController();
  PaymentMethod _refund = PaymentMethod.cash;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Indiquez le motif de l’annulation.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(salesRepositoryProvider).cancelSale(widget.sale.id, reason: _reason.text, refundMethod: _refund);
      ref
        ..invalidate(saleDetailProvider(widget.sale.id))
        ..invalidate(salesHistoryProvider)
        ..invalidate(dashboardProvider)
        ..invalidate(productListProvider)
        ..invalidate(stockListProvider)
        ..invalidate(posCatalogProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final refundable = widget.sale.amountPaid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormErrorBanner(message: _error),
        JpTextField(
          label: 'Motif',
          hint: 'Ex. erreur de caisse, client a rendu l’article…',
          controller: _reason,
          autofocus: true,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          enabled: !_saving,
        ),
        if (refundable > 0) ...[
          const SizedBox(height: JpSpacing.lg),
          Text(
            'Remboursement de ${Formatters.money(refundable)} par',
            style: JpTypography.label.copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: JpSpacing.sm),
          Wrap(
            spacing: JpSpacing.sm,
            runSpacing: JpSpacing.sm,
            children: [
              for (final m in const [
                PaymentMethod.cash,
                PaymentMethod.wave,
                PaymentMethod.orangeMoney,
                PaymentMethod.other,
              ])
                ChoiceChip(
                  avatar: Icon(m.icon, size: 16),
                  label: Text(m.label),
                  selected: _refund == m,
                  onSelected: _saving ? null : (_) => setState(() => _refund = m),
                ),
            ],
          ),
        ],
        const SizedBox(height: JpSpacing.xxl),
        JpButton(
          label: 'Confirmer l’annulation',
          variant: JpButtonVariant.danger,
          isLoading: _saving,
          onPressed: _submit,
        ),
      ],
    );
  }
}
