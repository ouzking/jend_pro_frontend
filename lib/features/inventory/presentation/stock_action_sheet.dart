import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/formatting/input_formatters.dart';
import '../../products/domain/catalog_models.dart';
import '../application/inventory_providers.dart';
import '../domain/inventory_models.dart';

/// Opérations de stock proposées à l'utilisateur.
enum StockAction {
  add('Ajouter du stock', 'Ajouter', Icons.add_circle_outline_rounded),
  remove('Retirer du stock', 'Retirer', Icons.remove_circle_outline_rounded),
  count('Inventaire physique', 'Inventaire', Icons.fact_check_outlined),
  transfer('Transférer', 'Transférer', Icons.swap_horiz_rounded);

  const StockAction(this.label, this.shortLabel, this.icon);

  final String label;

  /// Libellé de bouton (grille 2 colonnes, petits écrans).
  final String shortLabel;
  final IconData icon;
}

/// Feuille d'opération de stock. Renvoie `true` si l'opération a réussi.
Future<bool> showStockActionSheet(
  BuildContext context, {
  required StockAction action,
  required Product product,
  required List<LocationStock> stock,
  String? initialLocationId,
}) async {
  final done = await JpOverlays.sheet<bool>(
    context,
    title: action.label,
    subtitle: product.name,
    child: _StockActionForm(action: action, product: product, stock: stock, initialLocationId: initialLocationId),
  );
  return done ?? false;
}

/// Motifs de sortie : type de mouvement côté base.
enum _RemoveKind {
  loss(MovementType.loss, 'Perte / vol'),
  damage(MovementType.damage, 'Casse / périmé'),
  correction(MovementType.adjustment, 'Correction');

  const _RemoveKind(this.type, this.label);

  final MovementType type;
  final String label;
}

class _StockActionForm extends ConsumerStatefulWidget {
  const _StockActionForm({
    required this.action,
    required this.product,
    required this.stock,
    required this.initialLocationId,
  });

  final StockAction action;
  final Product product;
  final List<LocationStock> stock;
  final String? initialLocationId;

  @override
  ConsumerState<_StockActionForm> createState() => _StockActionFormState();
}

class _StockActionFormState extends ConsumerState<_StockActionForm> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  late String _locationId = widget.initialLocationId ?? widget.stock.first.location.id;
  String? _targetId;
  _RemoveKind _removeKind = _RemoveKind.loss;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final others = widget.stock.where((s) => s.location.id != _locationId);
    _targetId = others.isEmpty ? null : others.first.location.id;
    _quantity.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  LocationStock get _current => widget.stock.firstWhere((s) => s.location.id == _locationId);

  /// Aucun mouvement encore à cet emplacement : un ajout devient le stock
  /// initial (le moteur exige INITIAL pour la première entrée).
  bool get _isInitial => widget.action == StockAction.add && _current.quantity == null;

  bool get _reasonRequired => switch (widget.action) {
    StockAction.add => !_isInitial,
    StockAction.remove => true,
    StockAction.count || StockAction.transfer => false,
  };

  String get _unit => widget.product.unit;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final qty = QuantityInputFormatter.parse(_quantity.text)!;
    final reason = _reason.text.trim().isEmpty ? null : _reason.text.trim();
    final actions = ref.read(inventoryActionsProvider);
    final productId = widget.product.id;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      switch (widget.action) {
        case StockAction.add:
          await actions.adjust(
            productId: productId,
            locationId: _locationId,
            type: _isInitial ? MovementType.initial : MovementType.adjustment,
            quantity: qty,
            reason: reason,
          );
        case StockAction.remove:
          await actions.adjust(
            productId: productId,
            locationId: _locationId,
            type: _removeKind.type,
            quantity: -qty,
            reason: reason,
          );
        case StockAction.count:
          await actions.count(productId: productId, locationId: _locationId, counted: qty, reason: reason);
        case StockAction.transfer:
          await actions.transfer(
            productId: productId,
            fromLocationId: _locationId,
            toLocationId: _targetId!,
            quantity: qty,
            reason: reason,
          );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      JpOverlays.toast(context, 'Stock mis à jour.', tone: JpTone.success);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = _messageFor(f));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _messageFor(AppFailure f) {
    if (f.code == 'INSUFFICIENT_STOCK') {
      final available = f.detail?['available'];
      return available == null
          ? f.message
          : 'Stock insuffisant : ${Formatters.quantity(num.parse('$available'))} $_unit disponible(s).';
    }
    return f.message;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fractional = widget.product.allowsFractionalQuantity;
    final multiLocation = widget.stock.length > 1;
    final current = _current.quantity;
    final typed = QuantityInputFormatter.parse(_quantity.text);

    String? preview;
    if (typed != null) {
      final base = current ?? 0;
      preview = switch (widget.action) {
        StockAction.add => 'Nouveau stock : ${Formatters.quantity(base + typed)} $_unit',
        StockAction.remove => 'Nouveau stock : ${Formatters.quantity(base - typed)} $_unit',
        StockAction.count =>
          'Écart : ${typed - base >= 0 ? '+' : '−'}${Formatters.quantity((typed - base).abs())} $_unit',
        StockAction.transfer => 'Reste ici : ${Formatters.quantity(base - typed)} $_unit',
      };
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormErrorBanner(message: _error),
          if (multiLocation) ...[
            Text(
              widget.action == StockAction.transfer ? 'Depuis' : 'Emplacement',
              style: JpTypography.label.copyWith(color: p.textPrimary),
            ),
            const SizedBox(height: JpSpacing.sm),
            Wrap(
              spacing: JpSpacing.sm,
              runSpacing: JpSpacing.sm,
              children: [
                for (final s in widget.stock)
                  ChoiceChip(
                    label: Text('${s.location.name} · ${s.quantity == null ? '—' : Formatters.quantity(s.quantity!)}'),
                    selected: s.location.id == _locationId,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() {
                            _locationId = s.location.id;
                            if (_targetId == _locationId) {
                              _targetId = widget.stock.where((o) => o.location.id != _locationId).first.location.id;
                            }
                          }),
                  ),
              ],
            ),
            const SizedBox(height: JpSpacing.lg),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: JpSpacing.lg),
              child: Text(
                current == null
                    ? 'Aucun stock enregistré pour l’instant.'
                    : 'Stock actuel : ${Formatters.quantity(current)} $_unit',
                style: JpTypography.body.copyWith(color: p.textSecondary),
              ),
            ),
          if (widget.action == StockAction.transfer) ...[
            Text('Vers', style: JpTypography.label.copyWith(color: p.textPrimary)),
            const SizedBox(height: JpSpacing.sm),
            Wrap(
              spacing: JpSpacing.sm,
              runSpacing: JpSpacing.sm,
              children: [
                for (final s in widget.stock.where((s) => s.location.id != _locationId))
                  ChoiceChip(
                    label: Text(s.location.name),
                    selected: s.location.id == _targetId,
                    onSelected: _saving ? null : (_) => setState(() => _targetId = s.location.id),
                  ),
              ],
            ),
            const SizedBox(height: JpSpacing.lg),
          ],
          if (widget.action == StockAction.remove) ...[
            Text('Motif de la sortie', style: JpTypography.label.copyWith(color: p.textPrimary)),
            const SizedBox(height: JpSpacing.sm),
            Wrap(
              spacing: JpSpacing.sm,
              children: [
                for (final k in _RemoveKind.values)
                  ChoiceChip(
                    label: Text(k.label),
                    selected: k == _removeKind,
                    onSelected: _saving ? null : (_) => setState(() => _removeKind = k),
                  ),
              ],
            ),
            const SizedBox(height: JpSpacing.lg),
          ],
          if (_isInitial)
            const Padding(
              padding: EdgeInsets.only(bottom: JpSpacing.lg),
              child: JpBanner(
                tone: JpTone.info,
                icon: Icons.flag_outlined,
                message: 'Première saisie à cet emplacement : elle sera enregistrée comme stock initial.',
              ),
            ),
          JpTextField(
            label: widget.action == StockAction.count ? 'Quantité comptée' : 'Quantité',
            hint: '0',
            controller: _quantity,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(decimal: fractional),
            inputFormatters: [QuantityInputFormatter(allowDecimals: fractional)],
            suffixText: _unit,
            enabled: !_saving,
            validator: (v) {
              final q = QuantityInputFormatter.parse(v ?? '');
              if (q == null) return 'Indiquez une quantité.';
              if (widget.action != StockAction.count && q <= 0) return 'La quantité doit être positive.';
              if (q < 0) return 'Quantité invalide.';
              return null;
            },
          ),
          if (preview != null)
            Padding(
              padding: const EdgeInsets.only(top: JpSpacing.sm, left: JpSpacing.xxs),
              child: Text(preview, style: JpTypography.caption.copyWith(color: p.textSecondary)),
            ),
          const SizedBox(height: JpSpacing.lg),
          JpTextField(
            label: _reasonRequired ? 'Motif' : 'Motif (facultatif)',
            hint: switch (widget.action) {
              StockAction.add => 'Ex. réassort, retour fournisseur…',
              StockAction.remove => 'Ex. sac percé, produit périmé…',
              StockAction.count => 'Ex. inventaire mensuel',
              StockAction.transfer => 'Ex. réassort boutique',
            },
            controller: _reason,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            enabled: !_saving,
            validator: (v) => _reasonRequired && (v?.trim().isEmpty ?? true) ? 'Le motif est obligatoire.' : null,
          ),
          const SizedBox(height: JpSpacing.xxl),
          JpButton(
            label: widget.action == StockAction.count ? 'Enregistrer le comptage' : 'Valider',
            icon: widget.action.icon,
            isLoading: _saving,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
