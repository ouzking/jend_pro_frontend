import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/domain/payment_method.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/business_time.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/formatting/input_formatters.dart';
import '../../../core/media/image_picking.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../application/expense_providers.dart';
import '../domain/expense_models.dart';

/// Saisie rapide d'une dépense (création ou modification).
class ExpenseFormScreen extends ConsumerWidget {
  const ExpenseFormScreen({super.key, this.expenseId});

  final String? expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (expenseId == null) return const _Form();
    return ref
        .watch(expenseDetailProvider(expenseId!))
        .when(
          data: (e) => _Form(expense: e),
          loading: () => Scaffold(appBar: AppBar(), body: const JpSkeletonList(itemCount: 4)),
          error: (e, _) => Scaffold(
            appBar: AppBar(),
            body: JpErrorState(error: e),
          ),
        );
  }
}

const _methods = [
  PaymentMethod.cash,
  PaymentMethod.wave,
  PaymentMethod.orangeMoney,
  PaymentMethod.bankTransfer,
  PaymentMethod.card,
  PaymentMethod.cheque,
];

class _Form extends ConsumerStatefulWidget {
  const _Form({this.expense});

  final Expense? expense;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final _amount = TextEditingController(
    text: widget.expense == null ? '' : AmountInputFormatter.format(widget.expense!.amount),
  );
  late final _description = TextEditingController(text: widget.expense?.description);
  late String? _categoryId = widget.expense?.categoryId;
  late DateTime _date =
      widget.expense?.spentOn ?? BusinessTime.today(ref.read(activeBusinessProvider)?.timezone ?? 'Africa/Dakar');
  late PaymentMethod _method = widget.expense?.method ?? PaymentMethod.cash;
  late String? _receiptPath = widget.expense?.receiptPath;
  PickedImage? _newReceipt;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = BusinessTime.today(ref.read(activeBusinessProvider)?.timezone ?? 'Africa/Dakar');
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year - 2),
      lastDate: today,
      helpText: 'Date de la dépense',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickReceipt() async {
    final image = await pickImage(context, maxBytes: 5 * 1024 * 1024, maxDimension: 1600, title: 'Justificatif');
    if (image != null) setState(() => _newReceipt = image);
  }

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final name = await JpOverlays.sheet<String>(
      context,
      title: 'Nouvelle catégorie',
      child: Builder(
        builder: (sheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            JpTextField(controller: controller, hint: 'Ex. Marketing', autofocus: true, maxLength: 80),
            const SizedBox(height: JpSpacing.lg),
            JpButton(label: 'Créer', onPressed: () => Navigator.of(sheet).pop(controller.text.trim())),
          ],
        ),
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final c = await ref.read(expenseActionsProvider).createCategory(name);
      if (mounted) setState(() => _categoryId = c.id);
    } on AppFailure catch (f) {
      if (mounted) {
        JpOverlays.toast(
          context,
          f.code == 'UNIQUE_VIOLATION' ? 'Cette catégorie existe déjà.' : f.message,
          tone: JpTone.danger,
        );
      }
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final amount = AmountInputFormatter.parse(_amount.text) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Indiquez le montant.');
      return;
    }
    if (_categoryId == null) {
      setState(() => _error = 'Choisissez une catégorie.');
      return;
    }
    final actions = ref.read(expenseActionsProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var receipt = _receiptPath;
      if (_newReceipt != null) receipt = await actions.uploadReceipt(_newReceipt!.bytes, _newReceipt!.mimeType);
      final input = ExpenseInput(
        categoryId: _categoryId!,
        amount: amount,
        spentOn: _date,
        method: _method,
        description: _description.text,
        locationId: widget.expense?.locationId,
        receiptPath: receipt,
      );
      if (widget.expense == null) {
        await actions.create(input);
      } else {
        await actions.update(widget.expense!, input);
      }
      if (!mounted) return;
      HapticFeedback.lightImpact();
      JpOverlays.toast(context, 'Dépense de ${Formatters.money(amount)} enregistrée.', tone: JpTone.success);
      Navigator.of(context).pop();
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final categories = ref.watch(expenseCategoriesProvider);
    final canManage = ref.watch(permissionsProvider).can(Permission.expensesManage);
    final today = BusinessTime.today(ref.read(activeBusinessProvider)?.timezone ?? 'Africa/Dakar');
    final dateLabel = _date == today
        ? 'Aujourd’hui'
        : _date == today.subtract(const Duration(days: 1))
        ? 'Hier'
        : Formatters.date(_date);

    return Scaffold(
      appBar: AppBar(title: Text(widget.expense == null ? 'Nouvelle dépense' : 'Modifier la dépense')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, JpSpacing.xxl),
              children: [
                JpConstrained(
                  maxWidth: JpSpacing.maxFormWidth + 80,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FormErrorBanner(message: _error),
                      // Montant en grand : c'est l'information principale.
                      TextField(
                        controller: _amount,
                        autofocus: widget.expense == null,
                        keyboardType: TextInputType.number,
                        inputFormatters: [AmountInputFormatter()],
                        textAlign: TextAlign.center,
                        style: JpTypography.numeric(JpTypography.display).copyWith(color: p.textPrimary),
                        decoration: InputDecoration(
                          hintText: '0',
                          suffixText: 'FCFA',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintStyle: JpTypography.display.copyWith(color: p.textMuted),
                        ),
                      ),
                      const SizedBox(height: JpSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Catégorie', style: JpTypography.label.copyWith(color: p.textPrimary)),
                          ),
                          if (canManage) TextButton(onPressed: _addCategory, child: const Text('Nouvelle')),
                        ],
                      ),
                      JpAsyncView<List<ExpenseCategory>>(
                        value: categories,
                        onRetry: () => ref.invalidate(expenseCategoriesProvider),
                        loading: const SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
                        data: (list) => Wrap(
                          spacing: JpSpacing.sm,
                          runSpacing: JpSpacing.sm,
                          children: [
                            for (final c in list)
                              ChoiceChip(
                                avatar: Icon(c.icon, size: 16),
                                label: Text(c.name),
                                selected: _categoryId == c.id,
                                onSelected: _saving ? null : (_) => setState(() => _categoryId = c.id),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: JpSpacing.xl),
                      Text('Payée par', style: JpTypography.label.copyWith(color: p.textPrimary)),
                      const SizedBox(height: JpSpacing.sm),
                      Wrap(
                        spacing: JpSpacing.sm,
                        runSpacing: JpSpacing.sm,
                        children: [
                          for (final m in _methods)
                            ChoiceChip(
                              avatar: Icon(m.icon, size: 16),
                              label: Text(m.label),
                              selected: _method == m,
                              onSelected: _saving ? null : (_) => setState(() => _method = m),
                            ),
                        ],
                      ),
                      const SizedBox(height: JpSpacing.xl),
                      JpCard(
                        onTap: _saving ? null : _pickDate,
                        padding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.md),
                        child: Row(
                          children: [
                            Icon(Icons.event_outlined, color: p.textMuted),
                            const SizedBox(width: JpSpacing.md),
                            Expanded(
                              child: Text(dateLabel, style: JpTypography.bodyStrong.copyWith(color: p.textPrimary)),
                            ),
                            Text('Changer', style: JpTypography.label.copyWith(color: p.brand)),
                          ],
                        ),
                      ),
                      const SizedBox(height: JpSpacing.lg),
                      JpTextField(
                        label: 'Description (facultatif)',
                        hint: 'Ex. Facture Senelec septembre',
                        controller: _description,
                        maxLength: 300,
                        textCapitalization: TextCapitalization.sentences,
                        enabled: !_saving,
                      ),
                      const SizedBox(height: JpSpacing.lg),
                      _ReceiptField(
                        existingPath: _receiptPath,
                        picked: _newReceipt,
                        onPick: _saving ? null : _pickReceipt,
                        onRemove: _saving
                            ? null
                            : () => setState(() {
                                _newReceipt = null;
                                _receiptPath = null;
                              }),
                      ),
                    ],
                  ),
                ),
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
                padding: const EdgeInsets.all(JpSpacing.gutter),
                child: JpConstrained(
                  maxWidth: JpSpacing.maxFormWidth + 80,
                  child: JpButton(
                    label: 'Enregistrer',
                    icon: Icons.check_rounded,
                    isLoading: _saving,
                    onPressed: _save,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptField extends ConsumerWidget {
  const _ReceiptField({required this.existingPath, required this.picked, this.onPick, this.onRemove});

  final String? existingPath;
  final PickedImage? picked;
  final VoidCallback? onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final hasReceipt = picked != null || existingPath != null;
    Widget? preview;
    if (picked != null) {
      preview = Image.memory(picked!.bytes, fit: BoxFit.cover);
    } else if (existingPath != null && !existingPath!.endsWith('.pdf')) {
      preview = ref
          .watch(receiptUrlProvider(existingPath!))
          .when(
            data: (url) => Image.network(url, fit: BoxFit.cover),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Icon(Icons.broken_image_outlined, color: p.textMuted),
          );
    }
    return JpCard(
      onTap: hasReceipt ? null : onPick,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: p.surfaceMuted, borderRadius: JpRadius.all(JpRadius.sm)),
            child: preview ?? Icon(Icons.receipt_long_outlined, color: p.textMuted),
          ),
          const SizedBox(width: JpSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasReceipt ? 'Justificatif joint' : 'Ajouter un justificatif',
                  style: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
                ),
                Text(
                  'Photo de la facture ou du reçu · stockage privé',
                  style: JpTypography.caption.copyWith(color: p.textMuted),
                ),
              ],
            ),
          ),
          if (hasReceipt)
            IconButton(tooltip: 'Retirer le justificatif', icon: const Icon(Icons.close_rounded), onPressed: onRemove)
          else
            Icon(Icons.add_a_photo_outlined, color: p.brand),
        ],
      ),
    );
  }
}
