import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/config/env.dart';
import '../../../core/contact/contact_links.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/validation/validators.dart';
import '../../auth/application/auth_session.dart';
import '../../auth/domain/user_profile.dart';
import '../application/settings_providers.dart';

/// Profil de l'utilisateur connecté (nom affiché à l'équipe, téléphone).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(userProfileProvider)
      .when(
        data: (p) => p == null ? const SizedBox.shrink() : _Form(profile: p),
        loading: () => Scaffold(appBar: AppBar(), body: const JpSkeletonList(itemCount: 3)),
        error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: JpErrorState(error: e, onRetry: () => ref.invalidate(userProfileProvider)),
        ),
      );
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.fullName);
  late final _phone = TextEditingController(text: widget.profile.phone);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
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
      await ref
          .read(settingsActionsProvider)
          .updateMyProfile(
            fullName: _name.text,
            phone: _phone.text.trim().isEmpty ? null : Validators.normalizePhone(_phone.text),
          );
      if (!mounted) return;
      JpOverlays.toast(context, 'Profil mis à jour.', tone: JpTone.success);
      Navigator.of(context).pop();
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(JpSpacing.gutter),
          children: [
            JpConstrained(
              maxWidth: JpSpacing.maxFormWidth + 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: JpAvatar(name: widget.profile.displayName, size: JpSize.avatarLg),
                  ),
                  const SizedBox(height: JpSpacing.xl),
                  FormErrorBanner(message: _error),
                  JpTextField(
                    label: 'Nom complet',
                    controller: _name,
                    prefixIcon: Icons.person_outline_rounded,
                    textCapitalization: TextCapitalization.words,
                    enabled: !_saving,
                    validator: Validators.fullName,
                  ),
                  const SizedBox(height: JpSpacing.lg),
                  JpTextField(
                    label: 'Téléphone',
                    hint: '77 123 45 67',
                    controller: _phone,
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    enabled: !_saving,
                    validator: Validators.optionalPhone,
                  ),
                  const SizedBox(height: JpSpacing.lg),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'E-mail de connexion',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                    child: Text(widget.profile.email, style: JpTypography.body.copyWith(color: p.textSecondary)),
                  ),
                  const SizedBox(height: JpSpacing.xl),
                  JpButton(label: 'Enregistrer', isLoading: _saving, onPressed: _save),
                  const SizedBox(height: JpSpacing.sm),
                  JpButton.ghost(
                    label: 'Changer le mot de passe',
                    icon: Icons.password_rounded,
                    onPressed: () => context.push(Routes.changePassword),
                  ),
                  if (Env.supportEmail.isNotEmpty) ...[
                    const SizedBox(height: JpSpacing.xxl),
                    _DeleteAccount(email: widget.profile.email),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Choix du thème (clair, sombre, comme le téléphone).
Future<void> showAppearanceSheet(BuildContext context) => JpOverlays.sheet<void>(
  context,
  title: 'Apparence',
  child: Consumer(
    builder: (context, ref, _) {
      final mode = ref.watch(themeModeProvider);
      return RadioGroup<ThemeMode>(
        groupValue: mode,
        onChanged: (m) {
          if (m != null) ref.read(themeModeProvider.notifier).set(m);
        },
        child: const Column(
          children: [
            RadioListTile(value: ThemeMode.system, title: Text('Comme le téléphone'), contentPadding: EdgeInsets.zero),
            RadioListTile(value: ThemeMode.light, title: Text('Clair'), contentPadding: EdgeInsets.zero),
            RadioListTile(value: ThemeMode.dark, title: Text('Sombre'), contentPadding: EdgeInsets.zero),
          ],
        ),
      );
    },
  ),
);

/// Demande de suppression du compte (exigence Google Play / App Store) :
/// le backend n'expose pas de suppression en libre-service ; la demande est
/// envoyée au support, qui la traite.
class _DeleteAccount extends StatelessWidget {
  const _DeleteAccount({required this.email});

  final String email;

  Future<void> _request(BuildContext context) async {
    final ok = await JpOverlays.confirm(
      context,
      title: 'Supprimer votre compte ?',
      message:
          'Votre compte et vos données personnelles seront supprimés après vérification par l’équipe JËND PRO. '
          'Si vous êtes le seul propriétaire d’un commerce, ses données seront aussi supprimées. '
          'Votre application e-mail va s’ouvrir avec la demande pré-remplie : il suffit de l’envoyer.',
      confirmLabel: 'Préparer la demande',
      destructive: true,
      icon: Icons.person_remove_outlined,
    );
    if (!ok || !context.mounted) return;
    final opened = await ContactLinks.email(
      Env.supportEmail,
      subject: 'Demande de suppression de compte JËND PRO',
      body:
          'Bonjour,\n\nJe demande la suppression de mon compte JËND PRO et des données personnelles associées.\n\n'
          'Adresse e-mail du compte : $email\n\nMerci.',
    );
    if (!opened && context.mounted) {
      JpOverlays.toast(
        context,
        'Aucune application e-mail trouvée. Écrivez à ${Env.supportEmail} depuis l’adresse de votre compte.',
        tone: JpTone.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(color: p.border),
        const SizedBox(height: JpSpacing.sm),
        JpButton.ghost(
          label: 'Supprimer mon compte',
          icon: Icons.delete_forever_outlined,
          onPressed: () => _request(context),
        ),
      ],
    );
  }
}
