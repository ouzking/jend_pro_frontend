import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/validation/validators.dart';
import '../../auth/application/auth_session.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/widgets/auth_scaffold.dart';
import '../../business/application/workspace_controller.dart';
import '../../business/presentation/widgets/invitation_card.dart';

/// Première étape de l'onboarding : rejoindre une entreprise (invitation) ou
/// créer la sienne via la RPC `create_business`.
///
/// Les étapes suivantes (type de commerce, logo, premiers produits, stock
/// initial) seront ajoutées en phase 5.
class CreateBusinessScreen extends ConsumerStatefulWidget {
  const CreateBusinessScreen({super.key});

  @override
  ConsumerState<CreateBusinessScreen> createState() => _CreateBusinessScreenState();
}

class _CreateBusinessScreenState extends ConsumerState<CreateBusinessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _city.dispose();
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
          .read(workspaceProvider.notifier)
          .createBusiness(name: _name.text, phone: Validators.normalizePhone(_phone.text), city: _city.text);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final firstName = ref.watch(userProfileProvider).value?.firstName;
    final invitations = ref.watch(workspaceProvider.select((w) => w.value?.invitations ?? const []));

    return AuthScaffold(
      title: firstName == null ? 'Bienvenue !' : 'Bienvenue, $firstName !',
      subtitle: 'Créons l’espace de votre commerce. Vous pourrez tout modifier plus tard.',
      compactHero: true,
      footer: Center(
        child: TextButton(
          onPressed: _submitting ? null : () => ref.read(authRepositoryProvider).signOut(),
          child: const Text('Se déconnecter'),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (invitations.isNotEmpty) ...[
            Text('Vous avez été invité', style: JpTypography.titleSmall.copyWith(color: p.textPrimary)),
            const SizedBox(height: JpSpacing.md),
            for (final invitation in invitations) ...[
              InvitationCard(invitation: invitation),
              const SizedBox(height: JpSpacing.md),
            ],
            const SizedBox(height: JpSpacing.lg),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: JpSpacing.md),
                  child: Text('ou créez votre entreprise', style: JpTypography.caption.copyWith(color: p.textMuted)),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: JpSpacing.xxl),
          ],
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FormErrorBanner(message: _error),
                JpTextField(
                  label: 'Nom du commerce',
                  hint: 'Boutique Keur Awa',
                  controller: _name,
                  prefixIcon: Icons.storefront_outlined,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: Validators.businessName,
                  enabled: !_submitting,
                ),
                const SizedBox(height: JpSpacing.lg),
                JpTextField(
                  label: 'Téléphone (facultatif)',
                  hint: '77 123 45 67',
                  controller: _phone,
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  validator: Validators.optionalPhone,
                  enabled: !_submitting,
                ),
                const SizedBox(height: JpSpacing.lg),
                JpTextField(
                  label: 'Ville (facultatif)',
                  hint: 'Dakar',
                  controller: _city,
                  prefixIcon: Icons.location_on_outlined,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.addressCity],
                  onSubmitted: (_) => _submit(),
                  enabled: !_submitting,
                ),
                const SizedBox(height: JpSpacing.lg),
                const JpBanner(
                  tone: JpTone.brand,
                  icon: Icons.workspace_premium_outlined,
                  message: '14 jours d’essai PRO offerts, sans engagement.',
                ),
                const SizedBox(height: JpSpacing.xxl),
                JpButton(
                  label: 'Créer mon commerce',
                  trailingIcon: Icons.arrow_forward_rounded,
                  onPressed: _submit,
                  isLoading: _submitting,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
