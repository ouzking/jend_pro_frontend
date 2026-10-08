import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/formatting/input_formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../../inventory/application/inventory_providers.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/catalog_models.dart';
import '../../products/presentation/widgets/product_form_fields.dart';
import '../../products/presentation/widgets/product_visuals.dart';
import '../../suppliers/application/supplier_providers.dart';
import '../../suppliers/data/suppliers_repository.dart';
import '../../suppliers/domain/supplier_models.dart';
import '../application/purchase_providers.dart';
import '../domain/purchase_models.dart';

/// Saisie d'un achat : nouveau, ou modification d'un brouillon / commande.
class PurchaseEditorScreen extends ConsumerWidget {
  const PurchaseEditorScreen({super.key, this.purchaseId, this.supplierId});

  final String? purchaseId;
  final String? supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (purchaseId != null) {
      return ref
          .watch(purchaseDetailProvider(purchaseId!))
          .when(
            data: (p) => _Editor(
              initial: PurchaseDraft(
                purchaseId: p.id,
                supplier: p.supplierId == null
                    ? null
                    : Supplier(id: p.supplierId!, name: p.supplierName ?? '', archived: false),
                locationId: p.locationId,
                lines: [for (final l in p.lines) DraftLine.fromLine(l)],
                discount: p.discount,
                supplierReference: p.supplierReference,
                notes: p.notes,
              ),
              title: 'Modifier ${p.number}',
            ),
            loading: () => Scaffold(appBar: AppBar(), body: const JpSkeletonList(itemCount: 4)),
            error: (e, _) => Scaffold(
              appBar: AppBar(),
              body: JpErrorState(error: e),
            ),
          );
    }
    final supplier = ref.watch(supplierForNewPurchaseProvider(supplierId));
    return supplier.when(
      data: (s) => _Editor(
        initial: PurchaseDraft(supplier: s),
        title: 'Nouvel achat',
      ),
      loading: () => Scaffold(appBar: AppBar(), body: const JpSkeletonList(itemCount: 4)),
      error: (_, _) => const _Editor(initial: PurchaseDraft(), title: 'Nouvel achat'),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.initial, required this.title});

  final PurchaseDraft initial;
  final String title;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late PurchaseDraft _draft = widget.initial;
  late final _discount = TextEditingController(
    text: widget.initial.discount > 0 ? AmountInputFormatter.format(widget.initial.discount) : '',
  );
  late final _reference = TextEditingController(text: widget.initial.supplierReference);
  late final _notes = TextEditingController(text: widget.initial.notes);
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _discount.addListener(
      () => setState(() => _draft = _draft.copyWith(discount: AmountInputFormatter.parse(_discount.text) ?? 0)),
    );
  }

  @override
  void dispose() {
    _discount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? get _locationId => _draft.locationId ?? ref.read(locationsProvider).value?.firstOrNull?.id;

  Future<void> _pickSupplier() async {
    final picked = await JpOverlays.sheet<Supplier>(context, title: 'Fournisseur', child: const _SupplierPicker());
    if (picked != null) setState(() => _draft = _draft.copyWith(supplier: () => picked.id.isEmpty ? null : picked));
  }

  Future<void> _addLine() async {
    final pick = await JpOverlays.sheet<(String, String, String, bool, int?)>(
      context,
      title: 'Ajouter un article',
      child: _ProductPicker(supplierId: _draft.supplier?.id, excluded: {for (final l in _draft.lines) l.productId}),
    );
    if (pick == null || !mounted) return;
    final (id, name, unit, fractional, cost) = pick;
    await _editLine(
      DraftLine(
        productId: id,
        productName: name,
        unit: unit,
        allowsFractional: fractional,
        quantity: 1,
        unitCost: cost ?? 0,
      ),
      isNew: true,
    );
  }

  Future<void> _editLine(DraftLine line, {bool isNew = false}) async {
    final qty = TextEditingController(text: isNew ? '' : Formatters.quantity(line.quantity));
    final cost = TextEditingController(text: line.unitCost > 0 ? AmountInputFormatter.format(line.unitCost) : '');
    final result = await JpOverlays.sheet<DraftLine>(
      context,
      title: line.productName,
      child: Builder(
        builder: (sheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            JpTextField(
              label: 'Quantité reçue / commandée',
              controller: qty,
              autofocus: true,
              hint: '0',
              suffixText: line.unit,
              keyboardType: TextInputType.numberWithOptions(decimal: line.allowsFractional),
              inputFormatters: [QuantityInputFormatter(allowDecimals: line.allowsFractional)],
            ),
            const SizedBox(height: JpSpacing.lg),
            AmountField(label: 'Coût unitaire', controller: cost, enabled: true),
            const SizedBox(height: JpSpacing.xl),
            JpButton(
              label: isNew ? 'Ajouter' : 'Mettre à jour',
              onPressed: () {
                final q = QuantityInputFormatter.parse(qty.text);
                final c = AmountInputFormatter.parse(cost.text);
                if (q == null || q <= 0 || c == null) {
                  JpOverlays.toast(sheet, 'Indiquez la quantité et le coût unitaire.', tone: JpTone.warning);
                  return;
                }
                Navigator.of(sheet).pop(line.copyWith(quantity: q, unitCost: c));
              },
            ),
          ],
        ),
      ),
    );
    if (result != null) setState(() => _draft = _draft.upsertLine(result));
  }

  Future<void> _save({required bool receive}) async {
    if (_draft.lines.isEmpty) {
      setState(() => _error = 'Ajoutez au moins un article.');
      return;
    }
    final locationId = _locationId;
    if (locationId == null) {
      setState(() => _error = 'Emplacement de réception introuvable.');
      return;
    }
    if (receive) {
      final ok = await JpOverlays.confirm(
        context,
        title: 'Réceptionner maintenant ?',
        message:
            'Le stock sera augmenté et les coûts d’achat mis à jour. Un achat réceptionné ne peut plus être modifié.',
        confirmLabel: 'Réceptionner',
        icon: Icons.inventory_2_outlined,
      );
      if (!ok || !mounted) return;
    }
    final draft = _draft.copyWith(
      locationId: locationId,
      supplierReference: () => _reference.text,
      notes: () => _notes.text,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await ref.read(purchaseActionsProvider).save(draft, receive: receive);
      if (!mounted) return;
      JpOverlays.toast(
        context,
        receive ? 'Achat réceptionné : stock mis à jour.' : 'Achat enregistré.',
        tone: JpTone.success,
      );
      if (draft.purchaseId == null) {
        context.pushReplacement(Routes.purchaseDetail(id));
      } else {
        Navigator.of(context).pop();
      }
    } on AppFailure catch (f) {
      if (mounted) {
        setState(
          () => _error = f.code == 'TOTAL_BELOW_AMOUNT_PAID'
              ? 'Le nouveau total est inférieur aux acomptes déjà versés.'
              : f.message,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final locations = ref.watch(locationsProvider).value ?? const [];
    final canReceive = ref.watch(permissionsProvider).can(Permission.purchasesReceive);
    final enabled = !_saving;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, JpSpacing.xxl),
              children: [
                JpConstrained(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FormErrorBanner(message: _error),
                      JpCard(
                        onTap: enabled ? _pickSupplier : null,
                        padding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.md),
                        child: Row(
                          children: [
                            Icon(Icons.local_shipping_outlined, color: p.textMuted),
                            const SizedBox(width: JpSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Fournisseur', style: JpTypography.caption.copyWith(color: p.textMuted)),
                                  Text(
                                    _draft.supplier?.name ?? 'Sans fournisseur',
                                    style: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.expand_more_rounded, color: p.textMuted),
                          ],
                        ),
                      ),
                      if (locations.length > 1) ...[
                        const SizedBox(height: JpSpacing.md),
                        Wrap(
                          spacing: JpSpacing.sm,
                          children: [
                            for (final l in locations)
                              ChoiceChip(
                                avatar: Icon(
                                  l.isWarehouse ? Icons.warehouse_outlined : Icons.storefront_outlined,
                                  size: 16,
                                ),
                                label: Text(l.name),
                                selected: (_draft.locationId ?? locations.first.id) == l.id,
                                onSelected: enabled
                                    ? (_) => setState(() => _draft = _draft.copyWith(locationId: l.id))
                                    : null,
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: JpSpacing.xl),
                      JpSectionHeader(title: 'Articles', actionLabel: enabled ? 'Ajouter' : null, onAction: _addLine),
                      if (_draft.lines.isEmpty)
                        JpCard(
                          onTap: enabled ? _addLine : null,
                          color: p.surfaceMuted,
                          child: Row(
                            children: [
                              Icon(Icons.add_circle_outline_rounded, color: p.brand),
                              const SizedBox(width: JpSpacing.md),
                              Expanded(
                                child: Text(
                                  'Ajoutez les articles reçus ou commandés',
                                  style: JpTypography.body.copyWith(color: p.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        JpCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (var i = 0; i < _draft.lines.length; i++) ...[
                                if (i > 0) Divider(color: p.border, height: 1),
                                Dismissible(
                                  key: ValueKey(_draft.lines[i].productId),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: JpSpacing.xl),
                                    color: p.dangerSoft,
                                    child: Icon(Icons.delete_outline_rounded, color: p.danger),
                                  ),
                                  onDismissed: (_) =>
                                      setState(() => _draft = _draft.removeLine(_draft.lines[i].productId)),
                                  child: ListTile(
                                    onTap: enabled ? () => _editLine(_draft.lines[i]) : null,
                                    title: Text(_draft.lines[i].productName),
                                    subtitle: Text(
                                      '${Formatters.quantity(_draft.lines[i].quantity)} ${_draft.lines[i].unit} × '
                                      '${Formatters.money(_draft.lines[i].unitCost, currency: currency)}',
                                    ),
                                    trailing: JpAmount(
                                      _draft.lines[i].total,
                                      currency: currency,
                                      style: JpTypography.label,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      const SizedBox(height: JpSpacing.xl),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AmountField(
                              label: 'Remise obtenue',
                              controller: _discount,
                              enabled: enabled,
                              optional: true,
                            ),
                          ),
                          const SizedBox(width: JpSpacing.md),
                          Expanded(
                            child: JpTextField(
                              label: 'N° facture',
                              hint: 'Facultatif',
                              controller: _reference,
                              enabled: enabled,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: JpSpacing.lg),
                      JpTextField(
                        label: 'Notes',
                        hint: 'Facultatif',
                        controller: _notes,
                        maxLines: 2,
                        enabled: enabled,
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
                padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.md, JpSpacing.gutter, JpSpacing.md),
                child: JpConstrained(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Total', style: JpTypography.titleSmall.copyWith(color: p.textPrimary)),
                          ),
                          JpAmount(_draft.total, currency: currency, style: JpTypography.title),
                        ],
                      ),
                      const SizedBox(height: JpSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: JpButton.outline(
                              label: 'Enregistrer',
                              size: JpButtonSize.medium,
                              isLoading: _saving,
                              onPressed: () => _save(receive: false),
                            ),
                          ),
                          if (canReceive) ...[
                            const SizedBox(width: JpSpacing.sm),
                            Expanded(
                              child: JpButton(
                                label: 'Réceptionner',
                                icon: Icons.inventory_2_outlined,
                                size: JpButtonSize.medium,
                                isLoading: _saving,
                                onPressed: () => _save(receive: true),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
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

class _SupplierPicker extends ConsumerStatefulWidget {
  const _SupplierPicker();

  @override
  ConsumerState<_SupplierPicker> createState() => _SupplierPickerState();
}

class _SupplierPickerState extends ConsumerState<_SupplierPicker> {
  Timer? _debounce;
  List<Supplier>? _results;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final businessId = ref.read(activeBusinessProvider)!.businessId;
    final r = await ref.read(suppliersRepositoryProvider).fetchSuppliers(businessId, query: q, offset: 0, limit: 30);
    if (mounted) setState(() => _results = r);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JpTextField(
          hint: 'Rechercher un fournisseur',
          prefixIcon: Icons.search_rounded,
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 250), () => _load(v));
          },
        ),
        const SizedBox(height: JpSpacing.sm),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.block_rounded),
          title: const Text('Sans fournisseur'),
          onTap: () => Navigator.of(context).pop(const Supplier(id: '', name: '', archived: false)),
        ),
        if (_results == null)
          const Padding(
            padding: EdgeInsets.all(JpSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final s in _results!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: JpAvatar(name: s.name),
              title: Text(s.name),
              subtitle: s.contactName == null ? null : Text(s.contactName!),
              onTap: () => Navigator.of(context).pop(s),
            ),
      ],
    );
  }
}

/// Choix d'un article : produits du fournisseur d'abord (dernier coût), puis
/// tout le catalogue. Renvoie (id, nom, unité, fractionnable, coût suggéré).
class _ProductPicker extends ConsumerStatefulWidget {
  const _ProductPicker({required this.supplierId, required this.excluded});

  final String? supplierId;
  final Set<String> excluded;

  @override
  ConsumerState<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<_ProductPicker> {
  Timer? _debounce;
  String _query = '';
  List<Product>? _results;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final businessId = ref.read(activeBusinessProvider)!.businessId;
    final r = await ref
        .read(productsRepositoryProvider)
        .fetchProducts(businessId, ProductFilter(query: q), offset: 0, limit: 40);
    if (mounted) {
      setState(() {
        _query = q;
        _results = r.where((x) => !widget.excluded.contains(x.id)).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final supplierProducts = widget.supplierId == null
        ? const <SupplierProduct>[]
        : (ref.watch(supplierProductsProvider(widget.supplierId!)).value ?? const [])
              .where((x) => !widget.excluded.contains(x.productId))
              .where((x) => _query.isEmpty || x.productName.toLowerCase().contains(_query.toLowerCase()))
              .toList();
    final supplierIds = {for (final x in supplierProducts) x.productId};
    final others = (_results ?? const <Product>[]).where((x) => !supplierIds.contains(x.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JpTextField(
          hint: 'Rechercher un produit',
          prefixIcon: Icons.search_rounded,
          autofocus: true,
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 250), () => _load(v));
          },
        ),
        const SizedBox(height: JpSpacing.md),
        if (supplierProducts.isNotEmpty) ...[
          Text('CHEZ CE FOURNISSEUR', style: JpTypography.overline.copyWith(color: p.textMuted)),
          for (final x in supplierProducts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ProductThumb(name: x.productName, imagePath: x.imagePath, size: 40),
              title: Text(x.productName),
              subtitle: x.lastCost == null ? null : Text('Dernier coût ${Formatters.money(x.lastCost!)}'),
              onTap: () =>
                  Navigator.of(context).pop((x.productId, x.productName, x.unit, x.allowsFractional, x.lastCost)),
            ),
          const SizedBox(height: JpSpacing.md),
          Text('TOUT LE CATALOGUE', style: JpTypography.overline.copyWith(color: p.textMuted)),
        ],
        if (_results == null)
          const Padding(
            padding: EdgeInsets.all(JpSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (others.isEmpty && supplierProducts.isEmpty)
          Padding(
            padding: const EdgeInsets.all(JpSpacing.lg),
            child: Text(
              'Aucun produit trouvé.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textMuted),
            ),
          )
        else
          for (final x in others)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ProductThumb(name: x.name, imagePath: x.imagePath, size: 40),
              title: Text(x.name),
              subtitle: Text(x.categoryName ?? x.unit),
              onTap: () => Navigator.of(
                context,
              ).pop((x.id, x.name, x.unit, x.allowsFractionalQuantity, (x.costPrice ?? 0) > 0 ? x.costPrice : null)),
            ),
      ],
    );
  }
}
