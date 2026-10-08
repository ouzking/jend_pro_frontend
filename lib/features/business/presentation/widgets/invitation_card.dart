import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/formatting/formatters.dart';
import '../../application/workspace_controller.dart';
import '../../domain/workspace.dart';

/// Invitation en attente : accepter ou refuser.
class InvitationCard extends ConsumerStatefulWidget {
  const InvitationCard({super.key, required this.invitation});

  final PendingInvitation invitation;

  @override
  ConsumerState<InvitationCard> createState() => _InvitationCardState();
}

class _InvitationCardState extends ConsumerState<InvitationCard> {
  bool? _accepting;

  Future<void> _respond({required bool accept}) async {
    setState(() => _accepting = accept);
    final controller = ref.read(workspaceProvider.notifier);
    try {
      if (accept) {
        await controller.acceptInvitation(widget.invitation.businessId);
      } else {
        await controller.declineInvitation(widget.invitation.businessId);
      }
    } on AppFailure catch (f) {
      if (mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    } finally {
      if (mounted) setState(() => _accepting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final inv = widget.invitation;
    final busy = _accepting != null;
    return JpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              JpAvatar(name: inv.businessName),
              const SizedBox(width: JpSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(inv.businessName, style: JpTypography.bodyStrong.copyWith(color: p.textPrimary)),
                    Text(
                      'Invité ${Formatters.relative(inv.invitedAt)}',
                      style: JpTypography.bodySmall.copyWith(color: p.textMuted),
                    ),
                  ],
                ),
              ),
              JpBadge(label: inv.roleName, tone: JpTone.brand),
            ],
          ),
          const SizedBox(height: JpSpacing.lg),
          Row(
            children: [
              Expanded(
                child: JpButton.outline(
                  label: 'Refuser',
                  size: JpButtonSize.medium,
                  isLoading: _accepting == false,
                  onPressed: busy ? null : () => _respond(accept: false),
                ),
              ),
              const SizedBox(width: JpSpacing.md),
              Expanded(
                child: JpButton(
                  label: 'Rejoindre',
                  size: JpButtonSize.medium,
                  isLoading: _accepting == true,
                  onPressed: busy ? null : () => _respond(accept: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
