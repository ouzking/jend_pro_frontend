import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/validation/validators.dart';

/// Saisie + confirmation d'un nouveau mot de passe.
class NewPasswordFields extends StatelessWidget {
  const NewPasswordFields({
    super.key,
    required this.password,
    required this.confirm,
    required this.onSubmitted,
    this.enabled = true,
    this.label = 'Nouveau mot de passe',
  });

  final TextEditingController password;
  final TextEditingController confirm;
  final VoidCallback onSubmitted;
  final bool enabled;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JpTextField(
          label: label,
          helper: '${Validators.minPasswordLength} caractères minimum.',
          controller: password,
          prefixIcon: Icons.lock_outline_rounded,
          obscure: true,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          validator: Validators.password,
          enabled: enabled,
        ),
        const SizedBox(height: JpSpacing.lg),
        JpTextField(
          label: 'Confirmer le mot de passe',
          controller: confirm,
          prefixIcon: Icons.lock_reset_rounded,
          obscure: true,
          textInputAction: TextInputAction.done,
          validator: (v) => v != password.text ? 'Les mots de passe ne correspondent pas.' : null,
          onSubmitted: (_) => onSubmitted(),
          enabled: enabled,
        ),
      ],
    );
  }
}
