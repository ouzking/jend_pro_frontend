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

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _submitting = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
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
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: _sent ? 'Vérifiez vos e-mails' : 'Mot de passe oublié',
      subtitle: _sent
          ? null
          : 'Saisissez votre e-mail : nous vous enverrons un lien pour choisir un nouveau mot de passe.',
      showBack: true,
      compactHero: true,
      child: _sent
          ? EmailSentPanel(
              email: _email.text.trim(),
              message: 'Ouvrez le lien depuis ce téléphone pour choisir un nouveau mot de passe.',
              onDone: () => context.go(Routes.login),
            )
          : Form(
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
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    validator: Validators.email,
                    onSubmitted: (_) => _submit(),
                    enabled: !_submitting,
                    autofocus: true,
                  ),
                  const SizedBox(height: JpSpacing.xxl),
                  JpButton(label: 'Envoyer le lien', onPressed: _submit, isLoading: _submitting),
                ],
              ),
            ),
    );
  }
}
