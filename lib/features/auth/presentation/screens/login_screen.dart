import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/design_system/design_system.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/validation/validators.dart';
import '../../data/auth_repository.dart';
import '../widgets/auth_scaffold.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
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
      await ref.read(authRepositoryProvider).signIn(email: _email.text, password: _password.text);
      // La redirection est pilotée par le routeur (session → contexte).
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AuthScaffold(
      title: 'Content de vous revoir',
      subtitle: 'Connectez-vous pour retrouver votre commerce.',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text('Pas encore de compte ?', style: JpTypography.body.copyWith(color: p.textSecondary)),
          ),
          TextButton(onPressed: () => context.push(Routes.register), child: const Text('Créer un compte')),
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
                label: 'Adresse e-mail',
                hint: 'vous@exemple.sn',
                controller: _email,
                prefixIcon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email, AutofillHints.username],
                validator: Validators.email,
                enabled: !_submitting,
              ),
              const SizedBox(height: JpSpacing.lg),
              JpTextField(
                label: 'Mot de passe',
                controller: _password,
                prefixIcon: Icons.lock_outline_rounded,
                obscure: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                validator: (v) => (v == null || v.isEmpty) ? 'Saisissez votre mot de passe.' : null,
                onSubmitted: (_) => _submit(),
                enabled: !_submitting,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _submitting ? null : () => context.push(Routes.forgotPassword),
                  child: const Text('Mot de passe oublié ?'),
                ),
              ),
              const SizedBox(height: JpSpacing.sm),
              JpButton(label: 'Se connecter', onPressed: _submit, isLoading: _submitting),
            ],
          ),
        ),
      ),
    );
  }
}
