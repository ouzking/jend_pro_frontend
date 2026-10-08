import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../application/team_providers.dart';
import '../domain/team_models.dart';

/// Fiches employés (RH) : poste, contact, salaire mensuel.
class EmployeesScreen extends ConsumerWidget {
  const EmployeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final archived = ref.watch(employeesArchivedProvider);
    final employees = ref.watch(employeesProvider);
    final canManage = ref.watch(permissionsProvider).can(Permission.employeesManage);
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';

    return Scaffold(
      appBar: AppBar(title: const Text('Employés')),
      floatingActionButton: canManage && !archived
          ? FloatingActionButton.extended(
              heroTag: 'new-employee',
              onPressed: () => context.push(Routes.employeeNew),
              backgroundColor: p.brand,
              foregroundColor: p.textOnBrand,
              elevation: 2,
              icon: const Icon(Icons.add_rounded),
              label: Text('Employé', style: JpTypography.label.copyWith(color: p.textOnBrand)),
            )
          : null,
      body: JpConstrained(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, JpSpacing.md),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('En poste')),
                    ButtonSegment(value: true, label: Text('Archivés')),
                  ],
                  selected: {archived},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => ref.read(employeesArchivedProvider.notifier).set(s.single),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(employeesProvider.future).then<void>((_) {}, onError: (_) {}),
                child: JpAsyncView<List<Employee>>(
                  value: employees,
                  onRetry: () => ref.invalidate(employeesProvider),
                  loading: const JpSkeletonList(itemCount: 5),
                  data: (list) {
                    if (list.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          JpEmptyState(
                            icon: Icons.badge_outlined,
                            title: archived ? 'Aucune fiche archivée' : 'Aucun employé enregistré',
                            message: archived
                                ? 'Les fiches des anciens employés apparaîtront ici.'
                                : 'Gardez le poste, le contact et le salaire de chaque personne qui travaille avec vous.',
                            actionLabel: canManage && !archived ? 'Ajouter un employé' : null,
                            onAction: () => context.push(Routes.employeeNew),
                          ),
                        ],
                      );
                    }
                    final payroll = list.fold<int>(0, (s, e) => s + (e.salaryAmount ?? 0));
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, 0, JpSpacing.gutter, 120),
                      children: [
                        if (!archived && payroll > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: JpSpacing.lg),
                            child: JpCard(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Masse salariale mensuelle',
                                          style: JpTypography.caption.copyWith(color: p.textMuted),
                                        ),
                                        JpAmount(payroll, currency: currency, style: JpTypography.headline),
                                      ],
                                    ),
                                  ),
                                  JpBadge(label: '${list.length} en poste', tone: JpTone.brand),
                                ],
                              ),
                            ),
                          ),
                        JpCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (final (i, e) in list.indexed) ...[
                                if (i > 0) Divider(height: 1, indent: 72, color: p.border),
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: JpSpacing.lg,
                                    vertical: JpSpacing.xs,
                                  ),
                                  leading: JpAvatar(name: e.fullName),
                                  title: Text(e.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  titleTextStyle: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
                                  subtitle: Text(
                                    [
                                      e.position ?? 'Poste non précisé',
                                      if (e.memberId != null) 'accès à l’app',
                                    ].join(' · '),
                                  ),
                                  trailing: e.salaryAmount == null
                                      ? null
                                      : JpAmount(e.salaryAmount!, currency: currency, style: JpTypography.label),
                                  onTap: () => context.push(Routes.employeeDetail(e.id)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
