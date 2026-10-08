import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/validation/validators.dart';
import '../../application/setup_wizard_controller.dart';
import '../setup_wizard_screen.dart';

/// Informations légales et de contact (toutes facultatives) — elles
/// apparaîtront sur les reçus et factures.
class InfoStep extends ConsumerStatefulWidget {
  const InfoStep({super.key});

  @override
  ConsumerState<InfoStep> createState() => _InfoStepState();
}

class _InfoStepState extends ConsumerState<InfoStep> {
  final _formKey = GlobalKey<FormState>();
  final _fields = {
    'legal_name': TextEditingController(),
    'ninea': TextEditingController(),
    'rccm': TextEditingController(),
    'email': TextEditingController(),
    'address': TextEditingController(),
  };
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await ref.read(setupWizardProvider.notifier).loadProfile();
      _fields['legal_name']!.text = profile.legalName ?? '';
      _fields['ninea']!.text = profile.ninea ?? '';
      _fields['rccm']!.text = profile.rccm ?? '';
      _fields['email']!.text = profile.email ?? '';
      _fields['address']!.text = profile.address ?? '';
    } on AppFailure catch (f) {
      _error = f.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(setupWizardProvider.notifier).saveInfo({for (final e in _fields.entries) e.key: e.value.text});
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _maxLength(String? v, int max) => (v?.trim().length ?? 0) > max ? '$max caractères maximum.' : null;

  @override
  Widget build(BuildContext context) {
    final enabled = !_loading && !_saving;
    return SetupStepLayout(
      stepLabel: 'Étape 2 sur 5',
      title: 'Vos informations',
      subtitle: 'Elles figureront sur vos reçus et factures. Tout est facultatif.',
      primary: JpButton(
        label: 'Continuer',
        trailingIcon: Icons.arrow_forward_rounded,
        isLoading: _saving,
        onPressed: enabled ? _save : null,
      ),
      child: _loading
          ? const JpShimmer(
              child: Column(
                children: [
                  JpSkeleton(height: JpSize.input),
                  SizedBox(height: JpSpacing.xl),
                  JpSkeleton(height: JpSize.input),
                  SizedBox(height: JpSpacing.xl),
                  JpSkeleton(height: JpSize.input),
                ],
              ),
            )
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormErrorBanner(message: _error),
                  JpTextField(
                    label: 'Raison sociale',
                    hint: 'Ex. Keur Awa SARL',
                    controller: _fields['legal_name'],
                    prefixIcon: Icons.business_outlined,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    enabled: enabled,
                    validator: (v) => _maxLength(v, 200),
                  ),
                  const SizedBox(height: JpSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: JpTextField(
                          label: 'NINEA',
                          controller: _fields['ninea'],
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.next,
                          enabled: enabled,
                          validator: (v) => _maxLength(v, 30),
                        ),
                      ),
                      const SizedBox(width: JpSpacing.md),
                      Expanded(
                        child: JpTextField(
                          label: 'RCCM',
                          controller: _fields['rccm'],
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.next,
                          enabled: enabled,
                          validator: (v) => _maxLength(v, 50),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: JpSpacing.lg),
                  JpTextField(
                    label: 'E-mail du commerce',
                    hint: 'contact@moncommerce.sn',
                    controller: _fields['email'],
                    prefixIcon: Icons.alternate_email_rounded,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    enabled: enabled,
                    validator: (v) => (v?.trim().isEmpty ?? true) ? null : Validators.email(v),
                  ),
                  const SizedBox(height: JpSpacing.lg),
                  JpTextField(
                    label: 'Adresse',
                    hint: 'Ex. Marché Sandaga, Dakar',
                    controller: _fields['address'],
                    prefixIcon: Icons.place_outlined,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    maxLines: 2,
                    enabled: enabled,
                    validator: (v) => _maxLength(v, 300),
                    onSubmitted: (_) => _save(),
                  ),
                ],
              ),
            ),
    );
  }
}
