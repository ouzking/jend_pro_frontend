import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/design_system/design_system.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/validation/validators.dart';
import '../../data/auth_repository.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/email_sent_panel.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _awaitingConfirmation = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final needsConfirmation = await ref
          .read(authRepositoryProvider)
          .signUp(fullName: _name.text, email: _email.text, password: _password.text);
      // Sans confirmation, la session est ouverte et le routeur enchaîne
      // sur la création de l'entreprise.
      if (mounted && needsConfirmation) setState(() => _awaitingConfirmation = true);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    if (_awaitingConfirmation) {
      return AuthScaffold(
        title: 'Confirmez votre e-mail',
        showBack: true,
        compactHero: true,
        child: EmailSentPanel(
          email: _email.text.trim(),
          message: 'Ouvrez le lien reçu pour activer votre compte, puis connectez-vous.',
          onDone: () => context.go(Routes.login),
        ),
      );
    }

    return AuthScaffold(
      title: 'Créez votre compte',
      subtitle: 'Quelques secondes suffisent. Votre commerce vous attend.',
      showBack: true,
      compactHero: true,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text('Déjà inscrit ?', style: JpTypography.body.copyWith(color: p.textSecondary)),
          ),
          TextButton(onPressed: () => context.go(Routes.login), child: const Text('Se connecter')),
        ],
      ),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormErrorBanner(message: _error),
              JpTextField(
                label: 'Nom complet',
                hint: 'Awa Ndiaye',
                controller: _name,
                prefixIcon: Icons.person_outline_rounded,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: Validators.fullName,
                enabled: !_submitting,
              ),
              const SizedBox(height: JpSpacing.lg),
              JpTextField(
                label: 'Adresse e-mail',
                hint: 'vous@exemple.sn',
                controller: _email,
                prefixIcon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: Validators.email,
                enabled: !_submitting,
              ),
              const SizedBox(height: JpSpacing.lg),
              JpTextField(
                label: 'Mot de passe',
                helper: '${Validators.minPasswordLength} caractères minimum.',
                controller: _password,
                prefixIcon: Icons.lock_outline_rounded,
                obscure: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                validator: Validators.password,
                onSubmitted: (_) => _submit(),
                enabled: !_submitting,
              ),
              const SizedBox(height: JpSpacing.xxl),
              JpButton(label: 'Créer mon compte', onPressed: _submit, isLoading: _submitting),
            ],
          ),
        ),
      ),
    );
  }
}
