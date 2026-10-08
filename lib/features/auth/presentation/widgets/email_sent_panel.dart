import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';

/// Confirmation « e-mail envoyé », réutilisée par l'inscription et la
/// récupération de mot de passe.
class EmailSentPanel extends StatelessWidget {
  const EmailSentPanel({super.key, required this.email, required this.message, required this.onDone});

  final String email;
  final String message;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: JpIllustratedIcon(icon: Icons.mark_email_read_outlined, tone: JpTone.success),
        ),
        const SizedBox(height: JpSpacing.xxl),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Un e-mail a été envoyé à '),
              TextSpan(
                text: email,
                style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
              ),
              TextSpan(text: '. $message'),
            ],
          ),
          textAlign: TextAlign.center,
          style: JpTypography.body.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: JpSpacing.sm),
        Text(
          'Pensez à vérifier vos courriers indésirables.',
          textAlign: TextAlign.center,
          style: JpTypography.bodySmall.copyWith(color: p.textMuted),
        ),
        const SizedBox(height: JpSpacing.xxl),
        JpButton(label: 'Retour à la connexion', onPressed: onDone),
      ],
    );
  }
}
