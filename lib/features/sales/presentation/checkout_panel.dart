import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/domain/payment_method.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/formatting/input_formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../../products/presentation/widgets/product_form_fields.dart';
import '../application/pos_providers.dart';
import '../domain/cart.dart';
import '../domain/sale_models.dart';
import 'sale_complete_screen.dart';
import 'widgets/customer_picker_sheet.dart';
import 'widgets/pos_widgets.dart';

/// Écran d'encaissement (téléphone).
class CheckoutScreen extends StatelessWidget {
  const CheckoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Encaissement')),
      body: const CheckoutPanel(),
    );
  }
}

/// Moyens proposés à la caisse, dans l'ordre d'usage courant.
const _methods = [
  PaymentMethod.cash,
  PaymentMethod.wave,
  PaymentMethod.orangeMoney,
  PaymentMethod.freeMoney,
  PaymentMethod.card,
  PaymentMethod.other,
];

class _Tender {
  _Tender(this.method) : amount = TextEditingController(), reference = TextEditingController();

  PaymentMethod method;
  final TextEditingController amount;
  final TextEditingController reference;

  int get value => AmountInputFormatter.parse(amount.text) ?? 0;

  bool get isMobileMoney =>
      method == PaymentMethod.wave || method == PaymentMethod.orangeMoney || method == PaymentMethod.freeMoney;

  void dispose() {
    amount.dispose();
    reference.dispose();
  }
}

/// Panier + paiement. [embedded] : colonne de droite sur tablette.
class CheckoutPanel extends ConsumerStatefulWidget {
  const CheckoutPanel({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<CheckoutPanel> createState() => _CheckoutPanelState();
}

class _CheckoutPanelState extends ConsumerState<CheckoutPanel> {
  late final List<_Tender> _tenders = [_newTender(PaymentMethod.cash)];

  /// Chaque saisie de montant recalcule monnaie à rendre et reste dû.
  _Tender _newTender(PaymentMethod method) => _Tender(method)..amount.addListener(_onAmount);

  void _onAmount() {
    if (mounted) setState(() {});
  }

  /// Montant non saisi = paiement exact (cas le plus fréquent).
  bool _exactCash = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    for (final t in _tenders) {
      t.dispose();
    }
    super.dispose();
  }

  List<PaymentEntry> _tendered(int total) {
    if (_tenders.length == 1 && _tenders.first.amount.text.isEmpty && _exactCash) {
      return [PaymentEntry(method: _tenders.first.method, amount: total)];
    }
    return [
      for (final t in _tenders) PaymentEntry(method: t.method, amount: t.value, externalReference: t.reference.text),
    ];
  }

  Future<void> _submit(Cart cart, Settlement settlement) async {
    final permissions = ref.read(permissionsProvider);
    final customer = cart.customer;
    if (settlement.isCredit) {
      if (!permissions.can(Permission.salesCredit)) {
        setState(() => _error = 'Votre rôle ne permet pas la vente à crédit : encaissez la totalité.');
        return;
      }
      if (customer == null) {
        setState(() => _error = 'Choisissez un client pour laisser ${Formatters.money(settlement.credit)} à crédit.');
        return;
      }
      final available = customer.creditAvailable;
      if (!customer.creditAllowed || (available != null && settlement.credit > available)) {
        setState(
          () => _error = customer.creditAllowed
              ? 'Crédit disponible pour ${customer.name} : ${Formatters.money(available!)}.'
              : '${customer.name} n’a pas de crédit autorisé (plafond à définir dans sa fiche).',
        );
        return;
      }
    }
    final locationId = ref.read(posLocationProvider);
    if (locationId == null) {
      setState(() => _error = 'Emplacement de vente introuvable. Réessayez dans un instant.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final outcome = await ref
          .read(saleSubmitterProvider)
          .submit(cart: cart, settlement: settlement, locationId: locationId);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      final route = MaterialPageRoute<void>(
        builder: (_) => SaleCompleteScreen(outcome: outcome, customer: customer),
      );
      if (widget.embedded) {
        await Navigator.of(context).push(route);
      } else {
        await Navigator.of(context).pushReplacement(route);
      }
      for (final t in _tenders.skip(1)) {
        t.dispose();
      }
      if (mounted) {
        setState(() {
          _tenders.removeRange(1, _tenders.length);
          _tenders.first
            ..method = PaymentMethod.cash
            ..amount.clear()
            ..reference.clear();
          _exactCash = true;
        });
      }
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = _messageFor(f));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _messageFor(AppFailure f) => switch (f.code) {
    'INSUFFICIENT_STOCK' when f.detail?['available'] != null =>
      'Stock insuffisant : ${Formatters.quantity(num.parse('${f.detail!['available']}'))} disponible(s) pour un article du panier.',
    'CREDIT_LIMIT_EXCEEDED' => 'Le plafond de crédit du client serait dépassé.',
    _ => f.message,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cart = ref.watch(cartProvider);
    final permissions = ref.watch(permissionsProvider);
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final canDiscount = permissions.can(Permission.salesDiscount);
    final canPickCustomer = permissions.canAny(const [Permission.customersRead, Permission.customersCreate]);

    if (cart.isEmpty) {
      return const JpEmptyState(
        icon: Icons.shopping_basket_outlined,
        title: 'Panier vide',
        message: 'Touchez un article pour l’ajouter.',
      );
    }

    final settlement = Settlement.compute(total: cart.total, tendered: _tendered(cart.total));

    return Column(
      children: [
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.md, JpSpacing.gutter, JpSpacing.xl),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Panier · ${cart.lines.length} article${cart.lines.length > 1 ? 's' : ''}',
                      style: JpTypography.titleSmall.copyWith(color: p.textPrimary),
                    ),
                  ),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () async {
                            final ok = await JpOverlays.confirm(
                              context,
                              title: 'Vider le panier ?',
                              message: 'Tous les articles seront retirés.',
                              confirmLabel: 'Vider',
                              destructive: true,
                            );
                            if (ok) ref.read(cartProvider.notifier).clear();
                          },
                    child: const Text('Vider'),
                  ),
                ],
              ),
              JpCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < cart.lines.length; i++) ...[
                      if (i > 0) Divider(color: p.border, height: 1),
                      _CartLineTile(line: cart.lines[i], currency: currency, canDiscount: canDiscount),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: JpSpacing.lg),
              if (canPickCustomer) _CustomerTile(customer: cart.customer),
              if (canDiscount) ...[
                const SizedBox(height: JpSpacing.sm),
                _GlobalDiscountTile(cart: cart, currency: currency),
              ],
              const SizedBox(height: JpSpacing.lg),
              _Totals(cart: cart, currency: currency),
              const SizedBox(height: JpSpacing.xl),
              Text('Paiement', style: JpTypography.titleSmall.copyWith(color: p.textPrimary)),
              const SizedBox(height: JpSpacing.sm),
              for (var i = 0; i < _tenders.length; i++)
                _TenderEditor(
                  key: ObjectKey(_tenders[i]),
                  tender: _tenders[i],
                  total: cart.total,
                  exact: i == 0 && _tenders.length == 1 && _exactCash,
                  onExactChanged: (v) => setState(() => _exactCash = v),
                  onChanged: () => setState(() {}),
                  onRemove: i == 0
                      ? null
                      : () => setState(() {
                          _tenders.removeAt(i).dispose();
                        }),
                ),
              if (_tenders.length < 4)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _exactCash = false;
                      _tenders.add(_newTender(PaymentMethod.wave));
                    }),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Ajouter un autre paiement'),
                  ),
                ),
              const SizedBox(height: JpSpacing.md),
              _SettlementSummary(settlement: settlement, currency: currency, customer: cart.customer),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: p.background,
            border: Border(top: BorderSide(color: p.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.md, JpSpacing.gutter, JpSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormErrorBanner(message: _error),
                  JpButton(
                    label: 'Valider · ${Formatters.money(cart.total, currency: currency)}',
                    icon: Icons.check_rounded,
                    isLoading: _submitting,
                    onPressed: () => _submit(cart, settlement),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({required this.line, required this.currency, required this.canDiscount});

  final CartLine line;
  final String currency;
  final bool canDiscount;

  Future<void> _discount(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: line.discount > 0 ? AmountInputFormatter.format(line.discount) : '');
    final value = await JpOverlays.sheet<int>(
      context,
      title: 'Remise sur la ligne',
      subtitle: '${line.product.name} · ${Formatters.money(line.gross, currency: currency)}',
      child: Builder(
        builder: (sheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AmountField(label: 'Montant de la remise', controller: controller, enabled: true, optional: true),
            const SizedBox(height: JpSpacing.lg),
            JpButton(
              label: 'Appliquer',
              onPressed: () => Navigator.of(sheet).pop(AmountInputFormatter.parse(controller.text) ?? 0),
            ),
          ],
        ),
      ),
    );
    if (value != null) ref.read(cartProvider.notifier).setLineDiscount(line.product.id, value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final notifier = ref.read(cartProvider.notifier);
    final step = line.product.allowsFractional ? 0.5 : 1;
    return Dismissible(
      key: ValueKey(line.product.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: JpSpacing.xl),
        color: p.dangerSoft,
        child: Icon(Icons.delete_outline_rounded, color: p.danger),
      ),
      onDismissed: (_) => notifier.remove(line.product.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(JpSpacing.lg, JpSpacing.md, JpSpacing.md, JpSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Rangée 1 : article et montant de la ligne.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    line.product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: JpTypography.bodyStrong.copyWith(color: p.textPrimary, fontSize: 15),
                  ),
                ),
                const SizedBox(width: JpSpacing.md),
                JpAmount(line.total, currency: currency, style: JpTypography.bodyStrong),
              ],
            ),
            // Rangée 2 : prix unitaire / remise, puis quantité.
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${Formatters.money(line.product.salePrice, currency: currency)} / ${line.product.unit}'
                        '${line.discount > 0 ? ' · remise −${Formatters.money(line.discount, currency: currency)}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: JpTypography.caption.copyWith(color: line.discount > 0 ? p.accent : p.textMuted),
                      ),
                      if (canDiscount)
                        InkWell(
                          onTap: () => _discount(context, ref),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: JpSpacing.xs),
                            child: Text(
                              line.discount > 0 ? 'Modifier la remise' : '+ Remise',
                              style: JpTypography.caption.copyWith(color: p.brand, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _Stepper(
                  quantity: line.quantity,
                  onMinus: () => notifier.setQuantity(line.product.id, line.quantity - step),
                  onPlus: () => notifier.setQuantity(line.product.id, line.quantity + step),
                  onTapValue: () async {
                    final q = await askQuantity(context, line.product, initial: line.quantity);
                    if (q != null) notifier.setQuantity(line.product.id, q);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.quantity, required this.onMinus, required this.onPlus, required this.onTapValue});

  final num quantity;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onTapValue;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget button(IconData icon, VoidCallback onTap, String label) => IconButton(
      tooltip: label,
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        backgroundColor: p.surfaceMuted,
        minimumSize: const Size.square(36),
        fixedSize: const Size.square(36),
        padding: EdgeInsets.zero,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(quantity <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, onMinus, 'Diminuer'),
        InkWell(
          onTap: onTapValue,
          borderRadius: JpRadius.all(JpRadius.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            child: Center(
              child: Text(
                Formatters.quantity(quantity),
                style: JpTypography.numeric(JpTypography.bodyStrong).copyWith(color: p.textPrimary),
              ),
            ),
          ),
        ),
        button(Icons.add_rounded, onPlus, 'Augmenter'),
      ],
    );
  }
}

class _CustomerTile extends ConsumerWidget {
  const _CustomerTile({required this.customer});

  final SaleCustomer? customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final c = customer;
    return JpCard(
      onTap: () async {
        final picked = await pickSaleCustomer(context);
        if (picked != null) ref.read(cartProvider.notifier).setCustomer(picked);
      },
      padding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.md),
      child: Row(
        children: [
          if (c == null)
            Icon(Icons.person_add_alt_1_outlined, color: p.textMuted)
          else
            JpAvatar(name: c.name, size: JpSize.avatarSm),
          const SizedBox(width: JpSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c?.name ?? 'Ajouter un client',
                  style: JpTypography.bodyStrong.copyWith(color: c == null ? p.textSecondary : p.textPrimary),
                ),
                Text(
                  c == null
                      ? 'Facultatif · obligatoire pour une vente à crédit'
                      : c.balance > 0
                      ? 'Doit déjà ${Formatters.money(c.balance)}'
                      : (c.creditAllowed ? 'Aucune dette' : 'Crédit non autorisé'),
                  style: JpTypography.caption.copyWith(color: c != null && c.balance > 0 ? p.warning : p.textMuted),
                ),
              ],
            ),
          ),
          if (c != null)
            IconButton(
              tooltip: 'Retirer le client',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => ref.read(cartProvider.notifier).setCustomer(null),
            )
          else
            Icon(Icons.chevron_right_rounded, color: p.textMuted),
        ],
      ),
    );
  }
}

class _GlobalDiscountTile extends ConsumerWidget {
  const _GlobalDiscountTile({required this.cart, required this.currency});

  final Cart cart;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return JpCard(
      onTap: () async {
        final controller = TextEditingController(
          text: cart.globalDiscount > 0 ? AmountInputFormatter.format(cart.globalDiscount) : '',
        );
        final value = await JpOverlays.sheet<int>(
          context,
          title: 'Remise sur la vente',
          subtitle: 'Sous-total ${Formatters.money(cart.subtotal, currency: currency)}',
          child: Builder(
            builder: (sheet) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AmountField(label: 'Montant de la remise', controller: controller, enabled: true, optional: true),
                const SizedBox(height: JpSpacing.lg),
                JpButton(
                  label: 'Appliquer',
                  onPressed: () => Navigator.of(sheet).pop(AmountInputFormatter.parse(controller.text) ?? 0),
                ),
              ],
            ),
          ),
        );
        if (value != null) ref.read(cartProvider.notifier).setGlobalDiscount(value);
      },
      padding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.md),
      child: Row(
        children: [
          Icon(Icons.local_offer_outlined, color: p.textMuted),
          const SizedBox(width: JpSpacing.md),
          Expanded(
            child: Text(
              cart.globalDiscount > 0
                  ? 'Remise : −${Formatters.money(cart.globalDiscount, currency: currency)}'
                  : 'Ajouter une remise globale',
              style: JpTypography.bodyStrong.copyWith(color: cart.globalDiscount > 0 ? p.accent : p.textSecondary),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.textMuted),
        ],
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.cart, required this.currency});

  final Cart cart;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget row(String label, int amount, {bool strong = false, bool negative = false}) => Padding(
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
            negative ? -amount : amount,
            currency: currency,
            style: strong ? JpTypography.headline : JpTypography.bodyStrong,
            color: negative ? p.accent : null,
          ),
        ],
      ),
    );
    return Column(
      children: [
        if (cart.hasDiscount) ...[
          row('Sous-total', cart.subtotal + cart.lineDiscounts),
          if (cart.lineDiscounts > 0) row('Remises sur lignes', cart.lineDiscounts, negative: true),
          if (cart.globalDiscount > 0) row('Remise globale', cart.globalDiscount, negative: true),
          Divider(color: p.border),
        ],
        row('Total', cart.total, strong: true),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Montant confirmé par le serveur à la validation',
            style: JpTypography.caption.copyWith(color: p.textMuted),
          ),
        ),
      ],
    );
  }
}

class _TenderEditor extends StatelessWidget {
  const _TenderEditor({
    super.key,
    required this.tender,
    required this.total,
    required this.exact,
    required this.onExactChanged,
    required this.onChanged,
    this.onRemove,
  });

  final _Tender tender;
  final int total;
  final bool exact;
  final ValueChanged<bool> onExactChanged;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  /// Billets usuels au-dessus du total (rendu monnaie en un geste).
  List<int> _quickAmounts() {
    const bills = [500, 1000, 2000, 5000, 10000];
    final out = <int>{};
    for (final b in bills) {
      final rounded = ((total + b - 1) ~/ b) * b;
      if (rounded > total) out.add(rounded);
      if (out.length == 3) break;
    }
    return out.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isCash = tender.method == PaymentMethod.cash;
    return Padding(
      padding: const EdgeInsets.only(bottom: JpSpacing.md),
      child: JpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final m in _methods) ...[
                          ChoiceChip(
                            avatar: Icon(m.icon, size: 16),
                            label: Text(m.label),
                            selected: tender.method == m,
                            onSelected: (_) {
                              tender.method = m;
                              onChanged();
                            },
                          ),
                          const SizedBox(width: JpSpacing.xs),
                        ],
                      ],
                    ),
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Retirer ce paiement',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onRemove,
                  ),
              ],
            ),
            const SizedBox(height: JpSpacing.md),
            if (exact)
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: p.success, size: 20),
                  const SizedBox(width: JpSpacing.sm),
                  Expanded(
                    child: Text(
                      'Montant exact : ${Formatters.money(total)}',
                      style: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      onExactChanged(false);
                      onChanged();
                    },
                    child: Text(isCash ? 'Autre montant' : 'Modifier'),
                  ),
                ],
              )
            else ...[
              AmountField(
                label: isCash ? 'Montant reçu' : 'Montant payé',
                controller: tender.amount,
                enabled: true,
                optional: true,
              ),
              if (isCash)
                Padding(
                  padding: const EdgeInsets.only(top: JpSpacing.sm),
                  child: Wrap(
                    spacing: JpSpacing.sm,
                    children: [
                      for (final a in _quickAmounts())
                        ActionChip(
                          label: Text(Formatters.money(a)),
                          onPressed: () {
                            tender.amount.text = AmountInputFormatter.format(a);
                            onChanged();
                          },
                        ),
                    ],
                  ),
                ),
            ],
            if (tender.isMobileMoney && !exact) ...[
              const SizedBox(height: JpSpacing.md),
              JpTextField(
                label: 'Référence de transaction (facultatif)',
                hint: 'Évite les doublons',
                controller: tender.reference,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettlementSummary extends StatelessWidget {
  const _SettlementSummary({required this.settlement, required this.currency, required this.customer});

  final Settlement settlement;
  final String currency;
  final SaleCustomer? customer;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (settlement.change > 0) {
      return _Highlight(
        tone: p.tone(JpTone.success),
        icon: Icons.payments_outlined,
        label: 'Monnaie à rendre',
        amount: settlement.change,
        currency: currency,
      );
    }
    if (settlement.isCredit) {
      return _Highlight(
        tone: p.tone(JpTone.warning),
        icon: Icons.account_balance_wallet_outlined,
        label: customer == null
            ? 'Reste à payer (choisir un client pour le crédit)'
            : 'Reste à crédit · ${customer!.name}',
        amount: settlement.credit,
        currency: currency,
      );
    }
    return const SizedBox.shrink();
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight({
    required this.tone,
    required this.icon,
    required this.label,
    required this.amount,
    required this.currency,
  });

  final JpToneColors tone;
  final IconData icon;
  final String label;
  final int amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(JpSpacing.lg),
        decoration: BoxDecoration(color: tone.background, borderRadius: JpRadius.all(JpRadius.md)),
        child: Row(
          children: [
            Icon(icon, color: tone.foreground),
            const SizedBox(width: JpSpacing.md),
            Expanded(
              child: Text(label, style: JpTypography.bodyStrong.copyWith(color: tone.foreground)),
            ),
            JpAmount(amount, currency: currency, style: JpTypography.title, color: tone.foreground),
          ],
        ),
      ),
    );
  }
}
