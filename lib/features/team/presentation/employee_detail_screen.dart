import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/contact/contact_links.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../application/team_providers.dart';
import '../domain/team_models.dart';

class EmployeeDetailScreen extends ConsumerWidget {
  const EmployeeDetailScreen({super.key, required this.employeeId});

  final String employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(employeeDetailProvider(employeeId));
    final canManage = ref.watch(permissionsProvider).can(Permission.employeesManage);
    final e = employee.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiche employé'),
        actions: [
          if (e != null && canManage)
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push(Routes.employeeEdit(e.id)),
            ),
        ],
      ),
      body: JpAsyncView<Employee>(
        value: employee,
        onRetry: () => ref.invalidate(employeeDetailProvider(employeeId)),
        data: (e) => _Body(employee: e, canManage: canManage),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.employee, required this.canManage});

  final Employee employee;
  final bool canManage;

  Future<void> _toggleArchive(BuildContext context, WidgetRef ref) async {
    final e = employee;
    if (!e.archived) {
      final ok = await JpOverlays.confirm(
        context,
        title: 'Archiver la fiche de ${e.fullName} ?',
        message:
            'À utiliser quand la personne ne travaille plus avec vous. La fiche reste consultable dans « Archivés ».',
        confirmLabel: 'Archiver',
      );
      if (!ok) return;
    }
    try {
      await ref.read(teamActionsProvider).setEmployeeArchived(e, archived: !e.archived);
      if (context.mounted) {
        JpOverlays.toast(context, e.archived ? 'Fiche réactivée.' : 'Fiche archivée.', tone: JpTone.success);
      }
    } on AppFailure catch (f) {
      if (context.mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final e = employee;
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final linked = e.memberId == null ? null : ref.watch(linkableMembersProvider).value?[e.memberId];
    return ListView(
      padding: const EdgeInsets.all(JpSpacing.gutter),
      children: [
        JpConstrained(
          maxWidth: JpSpacing.maxFormWidth + 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: JpAvatar(name: e.fullName, size: JpSize.avatarLg),
              ),
              const SizedBox(height: JpSpacing.md),
              Text(
                e.fullName,
                textAlign: TextAlign.center,
                style: JpTypography.title.copyWith(color: p.textPrimary),
              ),
              Text(
                e.position ?? 'Poste non précisé',
                textAlign: TextAlign.center,
                style: JpTypography.body.copyWith(color: p.textSecondary),
              ),
              if (e.archived) ...[
                const SizedBox(height: JpSpacing.sm),
                const Center(
                  child: JpBadge(label: 'Archivée', tone: JpTone.warning),
                ),
              ],
              if (e.phone != null) ...[
                const SizedBox(height: JpSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: JpButton.outline(
                        label: 'Appeler',
                        icon: Icons.call_outlined,
                        size: JpButtonSize.medium,
                        onPressed: () => ContactLinks.call(e.phone!),
                      ),
                    ),
                    const SizedBox(width: JpSpacing.sm),
                    Expanded(
                      child: JpButton.outline(
                        label: 'WhatsApp',
                        icon: Icons.chat_outlined,
                        size: JpButtonSize.medium,
                        onPressed: () => ContactLinks.whatsApp(e.phone!),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: JpSpacing.xl),
              JpCard(
                child: Column(
                  children: [
                    _Row(
                      label: 'Salaire mensuel',
                      value: e.salaryAmount == null ? '—' : Formatters.money(e.salaryAmount!, currency: currency),
                    ),
                    if (e.phone != null) _Row(label: 'Téléphone', value: Formatters.phone(e.phone!)),
                    _Row(label: 'Embauche', value: e.hiredAt == null ? '—' : Formatters.date(e.hiredAt!)),
                    if (e.endedAt != null) _Row(label: 'Fin de contrat', value: Formatters.date(e.endedAt!)),
                    _Row(
                      label: 'Accès à l’app',
                      value: e.memberId == null ? 'Aucun compte lié' : (linked?.displayName ?? 'Compte lié'),
                    ),
                    if (e.notes != null) _Row(label: 'Notes', value: e.notes!),
                  ],
                ),
              ),
              if (canManage) ...[
                const SizedBox(height: JpSpacing.xl),
                JpButton.ghost(
                  label: e.archived ? 'Réactiver la fiche' : 'Archiver la fiche',
                  icon: e.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                  onPressed: () => _toggleArchive(context, ref),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: JpSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: JpTypography.body.copyWith(color: p.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: JpTypography.bodyStrong.copyWith(color: p.textPrimary)),
          ),
        ],
      ),
    );
  }
}
