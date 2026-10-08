import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../application/workspace_controller.dart';
import 'widgets/business_tile.dart';

/// Changement rapide d'entreprise depuis le shell.
Future<void> showBusinessSwitcher(BuildContext context) =>
    JpOverlays.sheet<void>(context, title: 'Changer de commerce', child: const _BusinessSwitcher());

class _BusinessSwitcher extends ConsumerStatefulWidget {
  const _BusinessSwitcher();

  @override
  ConsumerState<_BusinessSwitcher> createState() => _BusinessSwitcherState();
}

class _BusinessSwitcherState extends ConsumerState<_BusinessSwitcher> {
  String? _loadingId;

  Future<void> _select(String businessId) async {
    setState(() => _loadingId = businessId);
    try {
      await ref.read(workspaceProvider.notifier).selectBusiness(businessId);
      if (mounted) Navigator.of(context).pop();
    } on AppFailure catch (f) {
      if (mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    } finally {
      if (mounted) setState(() => _loadingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider).value;
    final activeId = workspace?.active?.businessId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in workspace?.memberships ?? const []) ...[
          BusinessTile(
            membership: m,
            selected: m.businessId == activeId,
            loading: _loadingId == m.businessId,
            onTap: _loadingId == null && m.businessId != activeId ? () => _select(m.businessId) : null,
          ),
          const SizedBox(height: JpSpacing.md),
        ],
      ],
    );
  }
}
