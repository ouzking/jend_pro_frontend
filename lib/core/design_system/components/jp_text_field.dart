import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../tokens/jp_metrics.dart';
import '../tokens/jp_typography.dart';

/// Champ de saisie avec libellé **au-dessus** (plus lisible qu'un libellé
/// flottant pour un public non technique), aide, erreur et mot de passe.
class JpTextField extends StatefulWidget {
  const JpTextField({
    super.key,
    this.label,
    this.hint,
    this.helper,
    this.controller,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffix,
    this.suffixText,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.inputFormatters,
    this.obscure = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.maxLength,
    this.focusNode,
    this.initialValue,
  });

  final String? label;
  final String? hint;
  final String? helper;
  final TextEditingController? controller;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;
  final Widget? suffix;

  /// Unité affichée dans le champ (ex. « FCFA »), alignée sur la saisie.
  final String? suffixText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;

  /// Champ mot de passe : masqué, avec bouton afficher / masquer.
  final bool obscure;
  final bool enabled;
  final bool autofocus;
  final int maxLines;
  final int? maxLength;
  final FocusNode? focusNode;
  final String? initialValue;

  @override
  State<JpTextField> createState() => _JpTextFieldState();
}

class _JpTextFieldState extends State<JpTextField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget? suffix = widget.suffix;
    if (suffix == null && widget.suffixText != null) {
      // Toujours visible (le `suffixText` natif disparaît quand le champ est vide).
      suffix = Padding(
        padding: const EdgeInsets.only(right: JpSpacing.lg),
        child: Center(
          widthFactor: 1,
          child: Text(widget.suffixText!, style: JpTypography.label.copyWith(color: p.textMuted)),
        ),
      );
    }
    if (widget.obscure) {
      suffix = IconButton(
        tooltip: _hidden ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
        icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        onPressed: () => setState(() => _hidden = !_hidden),
      );
    }

    final field = TextFormField(
      controller: widget.controller,
      initialValue: widget.initialValue,
      focusNode: widget.focusNode,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      autofillHints: widget.enabled ? widget.autofillHints : null,
      inputFormatters: widget.inputFormatters,
      obscureText: _hidden,
      enableSuggestions: !widget.obscure,
      autocorrect: !widget.obscure,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      maxLines: widget.obscure ? 1 : widget.maxLines,
      maxLength: widget.maxLength,
      autovalidateMode: AutovalidateMode.onUnfocus,
      style: JpTypography.body.copyWith(color: p.textPrimary, fontSize: 16),
      decoration: InputDecoration(
        hintText: widget.hint,
        helperText: widget.helper,
        helperMaxLines: 2,
        errorMaxLines: 3,
        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon, size: JpSize.iconMd),
        suffixIcon: suffix,
        counterText: '',
      ),
    );

    if (widget.label == null) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: JpSpacing.xxs, bottom: JpSpacing.sm),
          child: Text(widget.label!, style: JpTypography.label.copyWith(color: p.textPrimary)),
        ),
        field,
      ],
    );
  }
}
