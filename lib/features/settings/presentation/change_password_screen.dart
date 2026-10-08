import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/widgets/new_password_fields.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
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
      await ref
          .read(authRepositoryProvider)
          .changePassword(currentPassword: _current.text, newPassword: _password.text);
      if (!mounted) return;
      JpOverlays.toast(context, 'Mot de passe modifié.', tone: JpTone.success);
      Navigator.of(context).pop();
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(JpSpacing.gutter),
          child: JpConstrained(
            maxWidth: JpSpacing.maxFormWidth,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormErrorBanner(message: _error),
                  JpTextField(
                    label: 'Mot de passe actuel',
                    controller: _current,
                    prefixIcon: Icons.lock_outline_rounded,
                    obscure: true,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.password],
                    validator: (v) => (v == null || v.isEmpty) ? 'Saisissez votre mot de passe actuel.' : null,
                    enabled: !_submitting,
                  ),
                  const SizedBox(height: JpSpacing.xxl),
                  NewPasswordFields(
                    password: _password,
                    confirm: _confirm,
                    enabled: !_submitting,
                    onSubmitted: _submit,
                  ),
                  const SizedBox(height: JpSpacing.xxl),
                  JpButton(label: 'Mettre à jour', onPressed: _submit, isLoading: _submitting),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
