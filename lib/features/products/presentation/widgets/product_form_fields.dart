import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/formatting/input_formatters.dart';

/// Unités proposées par défaut (texte libre côté base, ≤ 20 caractères).
const defaultUnits = ['pièce', 'kg', 'litre', 'paquet', 'carton', 'sac', 'bouteille', 'boîte'];

/// Choix d'unité : puces + saisie libre « Autre… ».
class UnitSelector extends StatefulWidget {
  const UnitSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.units = defaultUnits,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final List<String> units;
  final bool enabled;

  @override
  State<UnitSelector> createState() => _UnitSelectorState();
}

class _UnitSelectorState extends State<UnitSelector> {
  late bool _custom = !widget.units.contains(widget.value);
  late final _controller = TextEditingController(text: _custom ? widget.value : '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: JpSpacing.sm,
          runSpacing: JpSpacing.sm,
          children: [
            for (final u in widget.units)
              ChoiceChip(
                label: Text(u),
                selected: !_custom && u == widget.value,
                onSelected: widget.enabled
                    ? (_) {
                        setState(() => _custom = false);
                        widget.onChanged(u);
                      }
                    : null,
              ),
            ChoiceChip(
              label: const Text('Autre…'),
              selected: _custom,
              onSelected: widget.enabled ? (_) => setState(() => _custom = true) : null,
            ),
          ],
        ),
        if (_custom) ...[
          const SizedBox(height: JpSpacing.md),
          JpTextField(
            hint: 'Ex. sachet, rouleau…',
            controller: _controller,
            maxLength: 20,
            enabled: widget.enabled,
            onChanged: (v) => widget.onChanged(v.trim()),
            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Précisez l’unité.' : null,
          ),
        ],
      ],
    );
  }
}

/// Montant entier en FCFA, milliers groupés pendant la saisie.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.label,
    required this.controller,
    required this.enabled,
    this.validator,
    this.optional = false,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final FormFieldValidator<String>? validator;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return JpTextField(
      label: label,
      hint: optional ? 'Facultatif' : '0',
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: [AmountInputFormatter()],
      enabled: enabled,
      validator: validator,
      suffixText: 'FCFA',
    );
  }
}

/// Interrupteur avec titre et explication (toute la ligne est cliquable).
class LabeledSwitch extends StatelessWidget {
  const LabeledSwitch({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        borderRadius: JpRadius.all(JpRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: JpSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: JpTypography.bodyStrong.copyWith(color: p.textPrimary)),
                    Text(subtitle, style: JpTypography.bodySmall.copyWith(color: p.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: JpSpacing.md),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
