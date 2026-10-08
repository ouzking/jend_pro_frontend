import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/formatting/input_formatters.dart';
import '../../../core/media/image_picking.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/scanner/barcode_scanner_screen.dart';
import '../../business/application/workspace_controller.dart';
import '../../onboarding/domain/business_templates.dart';
import '../application/catalog_providers.dart';
import '../domain/catalog_models.dart';
import 'widgets/categories_sheet.dart';
import 'widgets/product_form_fields.dart';

/// Création (`productId == null`) ou modification d'un produit.
class ProductFormScreen extends ConsumerWidget {
  const ProductFormScreen({super.key, this.productId, this.initialBarcode});

  final String? productId;
  final String? initialBarcode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (productId == null) return _ProductForm(initialBarcode: initialBarcode);
    final product = ref.watch(productDetailProvider(productId!));
    return product.when(
      data: (p) => _ProductForm(product: p),
      loading: () => Scaffold(appBar: AppBar(), body: const JpSkeletonList(itemCount: 5)),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: JpErrorState(error: e, onRetry: () => ref.invalidate(productDetailProvider(productId!))),
      ),
    );
  }
}

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({this.product, this.initialBarcode});

  final Product? product;
  final String? initialBarcode;

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late final Product? _initial = widget.product;
  late final _name = TextEditingController(text: _initial?.name);
  late final _description = TextEditingController(text: _initial?.description);
  late final _price = TextEditingController(
    text: _initial == null ? '' : AmountInputFormatter.format(_initial.salePrice),
  );
  late final _cost = TextEditingController(
    text: (_initial?.costPrice ?? 0) > 0 ? AmountInputFormatter.format(_initial!.costPrice!) : '',
  );
  late final _barcode = TextEditingController(text: _initial?.barcode ?? widget.initialBarcode);
  late final _sku = TextEditingController(text: _initial?.sku);
  late final _minStock = TextEditingController(
    text: (_initial?.minStockLevel ?? 0) > 0 ? Formatters.quantity(_initial!.minStockLevel) : '',
  );
  final _initialStock = TextEditingController();
  late String _unit = _initial?.unit ?? 'pièce';
  late Category? _category = _initial?.categoryId == null
      ? null
      : Category(id: _initial!.categoryId!, name: _initial.categoryName ?? '');
  late bool _trackStock = _initial?.trackStock ?? true;
  late bool _fractional = _initial?.allowsFractionalQuantity ?? false;
  PickedImage? _image;
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => _initial != null;

  @override
  void dispose() {
    for (final c in [_name, _description, _price, _cost, _barcode, _sku, _minStock, _initialStock]) {
      c.dispose();
    }
    super.dispose();
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _scanBarcode() async {
    final code = await scanBarcode(context, title: 'Code-barres du produit');
    if (code == null) return;
    setState(() {
      _barcode.text = code;
      _dirty = true;
    });
  }

  Future<void> _chooseCategory() async {
    final permissions = ref.read(permissionsProvider);
    final picked = await pickCategory(
      context,
      selectedId: _category?.id,
      canCreate: permissions.can(Permission.categoriesManage),
    );
    if (picked == null) return;
    setState(() {
      _category = picked.id.isEmpty ? null : picked;
      _dirty = true;
    });
  }

  Future<void> _choosePhoto() async {
    final image = await pickImage(context, maxBytes: 2 * 1024 * 1024, title: 'Photo du produit');
    if (image != null) {
      setState(() {
        _image = image;
        _dirty = true;
      });
    }
  }

  String? _clean(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final permissions = ref.read(permissionsProvider);
    final canSetCost = permissions.can(Permission.productsReadCost) && permissions.can(Permission.productsUpdate);
    final price = AmountInputFormatter.parse(_price.text) ?? 0;
    final cost = canSetCost ? AmountInputFormatter.parse(_cost.text) : null;
    final minStock = QuantityInputFormatter.parse(_minStock.text) ?? 0;
    final actions = ref.read(productActionsProvider);

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        final p = _initial!;
        final next = <String, Object?>{
          'name': _name.text.trim(),
          'description': _clean(_description),
          'sale_price': price,
          'unit': _unit,
          'category_id': _category?.id,
          'barcode': _clean(_barcode),
          'sku': _clean(_sku),
          'allows_fractional_quantity': _fractional,
          'min_stock_level': minStock,
        };
        final before = <String, Object?>{
          'name': p.name,
          'description': p.description,
          'sale_price': p.salePrice,
          'unit': p.unit,
          'category_id': p.categoryId,
          'barcode': p.barcode,
          'sku': p.sku,
          'allows_fractional_quantity': p.allowsFractionalQuantity,
          'min_stock_level': p.minStockLevel,
        };
        final changes = {
          for (final e in next.entries)
            if (e.value != before[e.key]) e.key: e.value,
        };
        final updated = await actions.update(p, changes, costPrice: cost);
        if (_image != null) await actions.uploadImage(updated, _image!.bytes, _image!.mimeType);
        if (!mounted) return;
        JpOverlays.toast(context, 'Produit mis à jour.', tone: JpTone.success);
        Navigator.of(context).pop();
      } else {
        final created = await actions.create(
          NewProduct(
            name: _name.text,
            description: _clean(_description),
            salePrice: price,
            costPrice: cost,
            unit: _unit,
            categoryId: _category?.id,
            barcode: _clean(_barcode),
            sku: _clean(_sku),
            trackStock: _trackStock,
            allowsFractionalQuantity: _fractional,
            minStockLevel: _trackStock ? minStock : null,
          ),
          initialStock: QuantityInputFormatter.parse(_initialStock.text),
          image: _image?.bytes,
          imageMime: _image?.mimeType,
        );
        if (!mounted) return;
        JpOverlays.toast(context, '« ${created.name} » ajouté au catalogue.', tone: JpTone.success);
        context.pushReplacement(Routes.productDetail(created.id));
      }
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = _messageFor(f));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _messageFor(AppFailure f) => switch (f.code) {
    'UNIQUE_VIOLATION' => 'Ce code-barres ou ce SKU est déjà utilisé par un autre produit.',
    'PLAN_LIMIT_REACHED' => 'Votre abonnement a atteint sa limite de produits actifs.',
    _ => f.message,
  };

  Future<bool> _confirmDiscard() => JpOverlays.confirm(
    context,
    title: 'Abandonner les modifications ?',
    message: 'Les informations saisies seront perdues.',
    confirmLabel: 'Abandonner',
    cancelLabel: 'Continuer',
    destructive: true,
  );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final permissions = ref.watch(permissionsProvider);
    final canSetCost = permissions.can(Permission.productsReadCost) && permissions.can(Permission.productsUpdate);
    final canSetStock = !_isEdit && _trackStock && permissions.can(Permission.inventoryAdjust);
    final enabled = !_saving;

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_isEdit ? 'Modifier le produit' : 'Nouveau produit')),
        body: Form(
          key: _formKey,
          onChanged: _touch,
          child: Column(
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
                          _PhotoPicker(
                            image: _image,
                            existingPath: _initial?.imagePath,
                            name: _name.text,
                            onTap: enabled ? _choosePhoto : null,
                          ),
                          const SizedBox(height: JpSpacing.xl),
                          JpTextField(
                            label: 'Nom du produit',
                            hint: 'Ex. Bissap 1 L',
                            controller: _name,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.next,
                            maxLength: 150,
                            enabled: enabled,
                            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Donnez un nom au produit.' : null,
                          ),
                          const SizedBox(height: JpSpacing.lg),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: AmountField(
                                  label: 'Prix de vente',
                                  controller: _price,
                                  enabled: enabled,
                                  validator: (v) =>
                                      AmountInputFormatter.parse(v ?? '') == null ? 'Indiquez un prix.' : null,
                                ),
                              ),
                              if (canSetCost) ...[
                                const SizedBox(width: JpSpacing.md),
                                Expanded(
                                  child: AmountField(
                                    label: 'Coût d’achat',
                                    controller: _cost,
                                    enabled: enabled,
                                    optional: true,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (canSetCost) _MarginHint(price: _price, cost: _cost),
                          const SizedBox(height: JpSpacing.xl),
                          Text('Unité de vente', style: JpTypography.label.copyWith(color: p.textPrimary)),
                          const SizedBox(height: JpSpacing.sm),
                          UnitSelector(
                            value: _unit,
                            enabled: enabled,
                            onChanged: (u) => setState(() {
                              _unit = u;
                              _dirty = true;
                              if (!_isEdit && BusinessTemplate.fractionalUnits.contains(u)) _fractional = true;
                            }),
                          ),
                          const SizedBox(height: JpSpacing.xl),
                          Text('Catégorie', style: JpTypography.label.copyWith(color: p.textPrimary)),
                          const SizedBox(height: JpSpacing.sm),
                          JpCard(
                            onTap: enabled ? _chooseCategory : null,
                            padding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.md),
                            child: Row(
                              children: [
                                Icon(Icons.label_outline_rounded, color: p.textMuted),
                                const SizedBox(width: JpSpacing.md),
                                Expanded(
                                  child: Text(
                                    _category?.name ?? 'Aucune catégorie',
                                    style: JpTypography.body.copyWith(
                                      color: _category == null ? p.textMuted : p.textPrimary,
                                    ),
                                  ),
                                ),
                                Icon(Icons.expand_more_rounded, color: p.textMuted),
                              ],
                            ),
                          ),
                          const SizedBox(height: JpSpacing.xl),
                          JpTextField(
                            label: 'Code-barres',
                            hint: 'Scannez ou saisissez',
                            controller: _barcode,
                            keyboardType: TextInputType.number,
                            maxLength: 64,
                            enabled: enabled,
                            suffix: IconButton(
                              tooltip: 'Scanner',
                              icon: Icon(Icons.qr_code_scanner_rounded, color: p.brand),
                              onPressed: enabled ? _scanBarcode : null,
                            ),
                          ),
                          const SizedBox(height: JpSpacing.lg),
                          JpTextField(
                            label: 'Référence interne (SKU)',
                            hint: 'Facultatif',
                            controller: _sku,
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 64,
                            enabled: enabled,
                          ),
                          const SizedBox(height: JpSpacing.lg),
                          JpTextField(
                            label: 'Description',
                            hint: 'Facultatif',
                            controller: _description,
                            maxLines: 3,
                            maxLength: 2000,
                            textCapitalization: TextCapitalization.sentences,
                            enabled: enabled,
                          ),
                          const SizedBox(height: JpSpacing.xl),
                          const JpSectionHeader(title: 'Stock'),
                          if (_isEdit)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: JpSpacing.sm),
                              child: JpBanner(
                                tone: JpTone.neutral,
                                icon: Icons.lock_outline_rounded,
                                message: _trackStock
                                    ? 'Le suivi du stock est activé. Ce choix ne peut plus être modifié.'
                                    : 'Article non stocké (service). Ce choix ne peut plus être modifié.',
                              ),
                            )
                          else
                            LabeledSwitch(
                              title: 'Suivre le stock',
                              subtitle: _trackStock
                                  ? 'Désactivez pour un service. Ce choix ne pourra plus être modifié.'
                                  : 'Service ou article non stocké : aucun suivi de quantité.',
                              value: _trackStock,
                              onChanged: enabled ? (v) => setState(() => _trackStock = v) : null,
                            ),
                          LabeledSwitch(
                            title: 'Vente au détail',
                            subtitle: 'Quantités décimales (ex. 2,5 kg).',
                            value: _fractional,
                            onChanged: enabled ? (v) => setState(() => _fractional = v) : null,
                          ),
                          if (_trackStock) ...[
                            const SizedBox(height: JpSpacing.md),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: JpTextField(
                                    label: 'Seuil d’alerte',
                                    hint: '0',
                                    helper: 'Alerte « stock faible » à ce niveau.',
                                    controller: _minStock,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [QuantityInputFormatter(allowDecimals: true)],
                                    enabled: enabled,
                                  ),
                                ),
                                if (canSetStock) ...[
                                  const SizedBox(width: JpSpacing.md),
                                  Expanded(
                                    child: JpTextField(
                                      label: 'Stock actuel',
                                      hint: '0',
                                      helper: 'Quantité en boutique aujourd’hui.',
                                      controller: _initialStock,
                                      keyboardType: TextInputType.numberWithOptions(decimal: _fractional),
                                      inputFormatters: [QuantityInputFormatter(allowDecimals: _fractional)],
                                      enabled: enabled,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
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
                      maxWidth: JpSpacing.maxFormWidth + 80,
                      child: JpButton(
                        label: _isEdit ? 'Enregistrer' : 'Ajouter au catalogue',
                        icon: _isEdit ? Icons.check_rounded : Icons.add_rounded,
                        isLoading: _saving,
                        onPressed: _save,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marge en direct sous les prix (aide à fixer le bon prix).
class _MarginHint extends StatelessWidget {
  const _MarginHint({required this.price, required this.cost});

  final TextEditingController price;
  final TextEditingController cost;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([price, cost]),
      builder: (context, _) {
        final p = context.palette;
        final sale = AmountInputFormatter.parse(price.text);
        final buy = AmountInputFormatter.parse(cost.text);
        if (sale == null || buy == null || buy == 0) return const SizedBox.shrink();
        final margin = sale - buy;
        final negative = margin < 0;
        return Padding(
          padding: const EdgeInsets.only(top: JpSpacing.sm, left: JpSpacing.xxs),
          child: Text(
            negative
                ? 'Attention : prix inférieur au coût (${Formatters.money(margin)}).'
                : 'Marge : ${Formatters.money(margin)}${sale > 0 ? ' · ${(margin / sale * 100).round()} %' : ''}',
            style: JpTypography.caption.copyWith(color: negative ? p.warning : p.success, fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }
}

class _PhotoPicker extends ConsumerWidget {
  const _PhotoPicker({required this.image, required this.existingPath, required this.name, this.onTap});

  final PickedImage? image;
  final String? existingPath;
  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    Widget preview;
    if (image != null) {
      preview = Image.memory(image!.bytes, fit: BoxFit.cover, width: 88, height: 88);
    } else if (existingPath != null) {
      preview = Image.network(
        ref.read(productActionsProvider).imageUrl(existingPath!),
        fit: BoxFit.cover,
        width: 88,
        height: 88,
      );
    } else {
      preview = Icon(Icons.add_a_photo_outlined, color: p.textMuted, size: 30);
    }
    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Photo du produit',
          child: InkWell(
            onTap: onTap,
            borderRadius: JpRadius.all(JpRadius.lg),
            child: Container(
              width: 88,
              height: 88,
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.surfaceMuted,
                borderRadius: JpRadius.all(JpRadius.lg),
                border: Border.all(color: p.borderStrong),
              ),
              child: preview,
            ),
          ),
        ),
        const SizedBox(width: JpSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Photo', style: JpTypography.label.copyWith(color: p.textPrimary)),
              const SizedBox(height: JpSpacing.xxs),
              Text(
                'Facultative · aide à reconnaître le produit à la caisse.',
                style: JpTypography.caption.copyWith(color: p.textMuted),
              ),
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                child: Text(image != null || existingPath != null ? 'Changer la photo' : 'Ajouter une photo'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
