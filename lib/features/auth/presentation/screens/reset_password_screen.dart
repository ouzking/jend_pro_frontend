import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/errors/app_failure.dart';
import '../../application/auth_session.dart';
import '../../data/auth_repository.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/new_password_fields.dart';

/// Ouvert par le lien « mot de passe oublié » (session de récupération).
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
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
      await ref.read(authRepositoryProvider).updatePassword(_password.text);
      if (!mounted) return;
      JpOverlays.toast(context, 'Mot de passe mis à jour.', tone: JpTone.success);
      ref.read(authSessionProvider.notifier).completePasswordRecovery();
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Nouveau mot de passe',
      subtitle: 'Choisissez un mot de passe que vous n’utilisez pas ailleurs.',
      compactHero: true,
      footer: Center(
        child: TextButton(
          onPressed: _submitting ? null : () => ref.read(authRepositoryProvider).signOut(),
          child: const Text('Annuler et se déconnecter'),
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormErrorBanner(message: _error),
            NewPasswordFields(password: _password, confirm: _confirm, enabled: !_submitting, onSubmitted: _submit),
            const SizedBox(height: JpSpacing.xxl),
            JpButton(label: 'Enregistrer', onPressed: _submit, isLoading: _submitting),
          ],
        ),
      ),
    );
  }
}
