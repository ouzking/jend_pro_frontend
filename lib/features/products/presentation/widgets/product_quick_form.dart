import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/formatting/input_formatters.dart';
import '../../../onboarding/domain/business_templates.dart';
import '../../domain/catalog_models.dart';
import 'product_form_fields.dart';

/// Formulaire court de création de produit (onboarding, ajout rapide).
///
/// Ne connaît pas Supabase : il construit un [NewProduct] et délègue
/// l'enregistrement à [onSubmit], dont il affiche l'éventuelle erreur.
class ProductQuickForm extends StatefulWidget {
  const ProductQuickForm({
    super.key,
    required this.onSubmit,
    required this.units,
    this.categories = const [],
    this.canSetCost = false,
    this.nameHint,
  });

  final Future<void> Function(NewProduct product) onSubmit;
  final List<String> units;
  final List<Category> categories;

  /// `products.read_cost` + `products.update` : sinon le coût est masqué.
  final bool canSetCost;
  final String? nameHint;

  @override
  State<ProductQuickForm> createState() => _ProductQuickFormState();
}

class _ProductQuickFormState extends State<ProductQuickForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _customUnit = TextEditingController();
  late String _unit = widget.units.isEmpty ? 'pièce' : widget.units.first;
  String? _categoryId;
  bool _trackStock = true;
  late bool _fractional = BusinessTemplate.fractionalUnits.contains(_unit);
  bool _customUnitMode = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _cost.dispose();
    _customUnit.dispose();
    super.dispose();
  }

  void _selectUnit(String unit) => setState(() {
    _unit = unit;
    _customUnitMode = false;
    _fractional = BusinessTemplate.fractionalUnits.contains(unit);
  });

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final unit = _customUnitMode ? _customUnit.text.trim() : _unit;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        NewProduct(
          name: _name.text,
          salePrice: AmountInputFormatter.parse(_price.text) ?? 0,
          costPrice: widget.canSetCost ? AmountInputFormatter.parse(_cost.text) : null,
          unit: unit,
          categoryId: _categoryId,
          trackStock: _trackStock,
          allowsFractionalQuantity: _fractional,
        ),
      );
    } on AppFailure catch (f) {
      if (mounted) {
        setState(
          () => _error = f.code == 'PLAN_LIMIT_REACHED'
              ? 'Votre abonnement a atteint sa limite de produits actifs.'
              : f.message,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final units = {...widget.units, if (!_customUnitMode) _unit}.toList();

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormErrorBanner(message: _error),
          JpTextField(
            label: 'Nom du produit',
            hint: widget.nameHint ?? 'Ex. Bissap 1 L',
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            maxLength: 150,
            autofocus: true,
            enabled: !_submitting,
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
                  enabled: !_submitting,
                  validator: (v) => AmountInputFormatter.parse(v ?? '') == null ? 'Indiquez un prix.' : null,
                ),
              ),
              if (widget.canSetCost) ...[
                const SizedBox(width: JpSpacing.md),
                Expanded(
                  child: AmountField(label: 'Coût d’achat', controller: _cost, enabled: !_submitting, optional: true),
                ),
              ],
            ],
          ),
          const SizedBox(height: JpSpacing.xl),
          Text('Unité de vente', style: JpTypography.label.copyWith(color: p.textPrimary)),
          const SizedBox(height: JpSpacing.sm),
          Wrap(
            spacing: JpSpacing.sm,
            runSpacing: JpSpacing.sm,
            children: [
              for (final u in units)
                ChoiceChip(
                  label: Text(u),
                  selected: !_customUnitMode && u == _unit,
                  onSelected: _submitting ? null : (_) => _selectUnit(u),
                ),
              ChoiceChip(
                label: const Text('Autre…'),
                selected: _customUnitMode,
                onSelected: _submitting ? null : (_) => setState(() => _customUnitMode = true),
              ),
            ],
          ),
          if (_customUnitMode) ...[
            const SizedBox(height: JpSpacing.md),
            JpTextField(
              hint: 'Ex. sachet, rouleau…',
              controller: _customUnit,
              maxLength: 20,
              enabled: !_submitting,
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Précisez l’unité.' : null,
            ),
          ],
          if (widget.categories.isNotEmpty) ...[
            const SizedBox(height: JpSpacing.xl),
            Text('Catégorie', style: JpTypography.label.copyWith(color: p.textPrimary)),
            const SizedBox(height: JpSpacing.sm),
            Wrap(
              spacing: JpSpacing.sm,
              runSpacing: JpSpacing.sm,
              children: [
                for (final c in widget.categories)
                  ChoiceChip(
                    label: Text(c.name),
                    selected: c.id == _categoryId,
                    onSelected: _submitting ? null : (s) => setState(() => _categoryId = s ? c.id : null),
                  ),
              ],
            ),
          ],
          const SizedBox(height: JpSpacing.lg),
          LabeledSwitch(
            title: 'Vente au détail',
            subtitle: 'Quantités décimales (ex. 2,5 kg).',
            value: _fractional,
            onChanged: _submitting ? null : (v) => setState(() => _fractional = v),
          ),
          LabeledSwitch(
            title: 'Suivre le stock',
            subtitle: _trackStock
                ? 'Désactivez pour un service. Ce choix ne pourra plus être modifié.'
                : 'Service ou article non stocké : aucun suivi de quantité.',
            value: _trackStock,
            onChanged: _submitting ? null : (v) => setState(() => _trackStock = v),
          ),
          const SizedBox(height: JpSpacing.xl),
          JpButton(label: 'Ajouter le produit', icon: Icons.add_rounded, onPressed: _submit, isLoading: _submitting),
        ],
      ),
    );
  }
}
