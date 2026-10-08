import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/widgets/auth_scaffold.dart';
import '../application/workspace_controller.dart';
import 'widgets/business_tile.dart';
import 'widgets/invitation_card.dart';

/// Choix de l'entreprise quand l'utilisateur en a plusieurs.
class SelectBusinessScreen extends ConsumerStatefulWidget {
  const SelectBusinessScreen({super.key});

  @override
  ConsumerState<SelectBusinessScreen> createState() => _SelectBusinessScreenState();
}

class _SelectBusinessScreenState extends ConsumerState<SelectBusinessScreen> {
  String? _loadingId;

  Future<void> _select(String businessId) async {
    setState(() => _loadingId = businessId);
    try {
      await ref.read(workspaceProvider.notifier).selectBusiness(businessId);
    } on AppFailure catch (f) {
      if (mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    } finally {
      if (mounted) setState(() => _loadingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final workspace = ref.watch(workspaceProvider).value;
    final memberships = workspace?.memberships ?? const [];
    final invitations = workspace?.invitations ?? const [];

    return AuthScaffold(
      title: 'Choisissez un commerce',
      subtitle: 'Vous pourrez en changer à tout moment depuis « Plus ».',
      compactHero: true,
      footer: Center(
        child: TextButton(
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
          child: const Text('Se déconnecter'),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in memberships) ...[
            BusinessTile(
              membership: m,
              loading: _loadingId == m.businessId,
              onTap: _loadingId == null ? () => _select(m.businessId) : null,
            ),
            const SizedBox(height: JpSpacing.md),
          ],
          if (invitations.isNotEmpty) ...[
            const SizedBox(height: JpSpacing.lg),
            Text('Invitations en attente', style: JpTypography.titleSmall.copyWith(color: p.textPrimary)),
            const SizedBox(height: JpSpacing.md),
            for (final inv in invitations) ...[InvitationCard(invitation: inv), const SizedBox(height: JpSpacing.md)],
          ],
        ],
      ),
    );
  }
}
