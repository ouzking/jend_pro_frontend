import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/domain/payment_method.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/formatting/formatters.dart';
import '../../../../core/formatting/input_formatters.dart';
import '../../../products/presentation/widgets/product_form_fields.dart';
import '../../application/customer_providers.dart';
import '../../domain/customer_models.dart';

/// Encaisser un règlement de dette.
Future<bool> showPaymentSheet(BuildContext context, Customer customer) async =>
    await JpOverlays.sheet<bool>(
      context,
      title: 'Encaisser un règlement',
      subtitle: '${customer.name} doit ${Formatters.money(customer.balance)}',
      child: _PaymentForm(customer: customer),
    ) ??
    false;

/// Définir le plafond de crédit.
Future<bool> showCreditLimitSheet(BuildContext context, Customer customer) async =>
    await JpOverlays.sheet<bool>(
      context,
      title: 'Plafond de crédit',
      subtitle: 'Montant maximum que ${customer.name} peut vous devoir.',
      child: _CreditLimitForm(customer: customer),
    ) ??
    false;

/// Corriger le solde (reprise du cahier, erreur…).
Future<bool> showAdjustSheet(BuildContext context, Customer customer) async =>
    await JpOverlays.sheet<bool>(
      context,
      title: 'Ajuster le solde',
      subtitle: 'Solde actuel : ${Formatters.money(customer.balance)}',
      child: _AdjustForm(customer: customer),
    ) ??
    false;

abstract class _SheetState<T extends ConsumerStatefulWidget> extends ConsumerState<T> {
  bool saving = false;
  String? error;

  Future<void> run(Future<void> Function() action, String success) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      JpOverlays.toast(context, success, tone: JpTone.success);
    } on AppFailure catch (f) {
      if (mounted) setState(() => error = f.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _PaymentForm extends ConsumerStatefulWidget {
  const _PaymentForm({required this.customer});

  final Customer customer;

  @override
  ConsumerState<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends _SheetState<_PaymentForm> {
  late final _amount = TextEditingController(text: AmountInputFormatter.format(widget.customer.balance));
  final _reference = TextEditingController();
  final _note = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = AmountInputFormatter.parse(_amount.text) ?? 0;
    if (amount <= 0) {
      setState(() => error = 'Indiquez un montant.');
      return;
    }
    if (amount > widget.customer.balance) {
      setState(
        () => error = 'Le règlement ne peut pas dépasser la dette (${Formatters.money(widget.customer.balance)}).',
      );
      return;
    }
    run(
      () => ref
          .read(customerActionsProvider)
          .recordPayment(
            widget.customer,
            amount: amount,
            method: _method,
            reference: _reference.text,
            note: _note.text,
          ),
      'Règlement de ${Formatters.money(amount)} enregistré.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final amount = AmountInputFormatter.parse(_amount.text) ?? 0;
    final remaining = widget.customer.balance - amount;
    final mobile = {PaymentMethod.wave, PaymentMethod.orangeMoney, PaymentMethod.freeMoney}.contains(_method);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormErrorBanner(message: error),
        AmountField(label: 'Montant reçu', controller: _amount, enabled: !saving),
        const SizedBox(height: JpSpacing.sm),
        Text(
          remaining <= 0 ? 'La dette sera entièrement réglée.' : 'Restera dû : ${Formatters.money(remaining)}',
          style: JpTypography.caption.copyWith(color: remaining <= 0 ? p.success : p.textSecondary),
        ),
        const SizedBox(height: JpSpacing.lg),
        Wrap(
          spacing: JpSpacing.sm,
          runSpacing: JpSpacing.sm,
          children: [
            for (final m in const [
              PaymentMethod.cash,
              PaymentMethod.wave,
              PaymentMethod.orangeMoney,
              PaymentMethod.freeMoney,
              PaymentMethod.bankTransfer,
            ])
              ChoiceChip(
                avatar: Icon(m.icon, size: 16),
                label: Text(m.label),
                selected: _method == m,
                onSelected: saving ? null : (_) => setState(() => _method = m),
              ),
          ],
        ),
        if (mobile) ...[
          const SizedBox(height: JpSpacing.lg),
          JpTextField(
            label: 'Référence de transaction (facultatif)',
            hint: 'Évite les doublons',
            controller: _reference,
            enabled: !saving,
          ),
        ],
        const SizedBox(height: JpSpacing.lg),
        JpTextField(label: 'Note (facultatif)', controller: _note, maxLength: 300, enabled: !saving),
        const SizedBox(height: JpSpacing.xxl),
        JpButton(label: 'Encaisser', icon: Icons.check_rounded, isLoading: saving, onPressed: _submit),
      ],
    );
  }
}

enum _LimitMode { none, capped, unlimited }

class _CreditLimitForm extends ConsumerStatefulWidget {
  const _CreditLimitForm({required this.customer});

  final Customer customer;

  @override
  ConsumerState<_CreditLimitForm> createState() => _CreditLimitFormState();
}

class _CreditLimitFormState extends _SheetState<_CreditLimitForm> {
  late _LimitMode _mode = widget.customer.unlimitedCredit
      ? _LimitMode.unlimited
      : (widget.customer.creditLimit! > 0 ? _LimitMode.capped : _LimitMode.none);
  late final _amount = TextEditingController(
    text: (widget.customer.creditLimit ?? 0) > 0 ? AmountInputFormatter.format(widget.customer.creditLimit!) : '',
  );

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final int? limit = switch (_mode) {
      _LimitMode.none => 0,
      _LimitMode.unlimited => null,
      _LimitMode.capped => AmountInputFormatter.parse(_amount.text),
    };
    if (_mode == _LimitMode.capped && (limit == null || limit <= 0)) {
      setState(() => error = 'Indiquez le plafond.');
      return;
    }
    run(() => ref.read(customerActionsProvider).setCreditLimit(widget.customer, limit), 'Plafond mis à jour.');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormErrorBanner(message: error),
        RadioGroup<_LimitMode>(
          groupValue: _mode,
          onChanged: (v) {
            if (!saving && v != null) setState(() => _mode = v);
          },
          child: const Column(
            children: [
              RadioListTile(
                value: _LimitMode.none,
                title: Text('Pas de crédit'),
                subtitle: Text('Paiement comptant uniquement'),
              ),
              RadioListTile(value: _LimitMode.capped, title: Text('Crédit plafonné')),
              RadioListTile(
                value: _LimitMode.unlimited,
                title: Text('Sans plafond'),
                subtitle: Text('À réserver aux clients de confiance'),
              ),
            ],
          ),
        ),
        if (_mode == _LimitMode.capped) ...[
          const SizedBox(height: JpSpacing.sm),
          AmountField(label: 'Plafond', controller: _amount, enabled: !saving),
        ],
        const SizedBox(height: JpSpacing.xxl),
        JpButton(label: 'Enregistrer', isLoading: saving, onPressed: _submit),
      ],
    );
  }
}

class _AdjustForm extends ConsumerStatefulWidget {
  const _AdjustForm({required this.customer});

  final Customer customer;

  @override
  ConsumerState<_AdjustForm> createState() => _AdjustFormState();
}

class _AdjustFormState extends _SheetState<_AdjustForm> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _increase = true;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = AmountInputFormatter.parse(_amount.text) ?? 0;
    if (amount <= 0) {
      setState(() => error = 'Indiquez un montant.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => error = 'Le motif est obligatoire.');
      return;
    }
    if (!_increase && amount > widget.customer.balance) {
      setState(() => error = 'Impossible de descendre sous zéro (pas d’avoir client).');
      return;
    }
    run(
      () => ref
          .read(customerActionsProvider)
          .adjustBalance(widget.customer, amount: _increase ? amount : -amount, reason: _reason.text),
      'Solde ajusté.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormErrorBanner(message: error),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: true, label: Text('Ajouter une dette'), icon: Icon(Icons.add_rounded)),
            ButtonSegment(value: false, label: Text('Réduire la dette'), icon: Icon(Icons.remove_rounded)),
          ],
          selected: {_increase},
          onSelectionChanged: saving ? null : (v) => setState(() => _increase = v.first),
        ),
        const SizedBox(height: JpSpacing.lg),
        AmountField(label: 'Montant', controller: _amount, enabled: !saving),
        const SizedBox(height: JpSpacing.lg),
        JpTextField(
          label: 'Motif',
          hint: 'Ex. reprise du cahier de crédit',
          controller: _reason,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          enabled: !saving,
        ),
        const SizedBox(height: JpSpacing.sm),
        Text(
          'Pour un paiement reçu, utilisez plutôt « Encaisser un règlement » : il est compté dans la caisse.',
          style: JpTypography.caption.copyWith(color: context.palette.textMuted),
        ),
        const SizedBox(height: JpSpacing.xxl),
        JpButton(label: 'Enregistrer', isLoading: saving, onPressed: _submit),
      ],
    );
  }
}
