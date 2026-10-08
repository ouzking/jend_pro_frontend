import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/contact/contact_links.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/validation/validators.dart';
import '../../auth/application/auth_session.dart';
import '../../business/application/workspace_controller.dart';
import '../application/team_providers.dart';
import '../domain/team_models.dart';

/// Membres de l'entreprise : accès à l'application et rôles.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final members = ref.watch(teamMembersProvider);
    final canManage = ref.watch(permissionsProvider).can(Permission.membersManage);
    final me = ref.watch(authSessionProvider).userId;
    // Précharge les rôles pour les feuilles.
    ref.watch(teamRolesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Équipe et accès')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              heroTag: 'invite-member',
              onPressed: () => showInviteSheet(context),
              backgroundColor: p.brand,
              foregroundColor: p.textOnBrand,
              elevation: 2,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text('Inviter', style: JpTypography.label.copyWith(color: p.textOnBrand)),
            )
          : null,
      body: JpConstrained(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(teamMembersProvider.future).then<void>((_) {}, onError: (_) {}),
          child: JpAsyncView<List<TeamMember>>(
            value: members,
            onRetry: () => ref.invalidate(teamMembersProvider),
            loading: const JpSkeletonList(itemCount: 5),
            data: (list) {
              final groups = [
                ('Invitations en attente', list.where((m) => m.status == MemberStatus.invited).toList()),
                ('Membres actifs', list.where((m) => m.status == MemberStatus.active).toList()),
                ('Accès suspendus', list.where((m) => m.status == MemberStatus.suspended).toList()),
              ];
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, 120),
                children: [
                  if (list.length <= 1 && canManage)
                    Padding(
                      padding: const EdgeInsets.only(bottom: JpSpacing.lg),
                      child: JpBanner(
                        icon: Icons.groups_2_outlined,
                        tone: JpTone.info,
                        message:
                            'Invitez vos caissiers, gérants ou magasiniers : chacun se connecte avec son propre compte et ne voit que ce que son rôle autorise.',
                      ),
                    ),
                  for (final (title, items) in groups)
                    if (items.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: JpSpacing.md, bottom: JpSpacing.sm),
                        child: Text(
                          '${title.toUpperCase()} · ${items.length}',
                          style: JpTypography.overline.copyWith(color: p.textMuted),
                        ),
                      ),
                      JpCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (final (i, m) in items.indexed) ...[
                              if (i > 0) Divider(height: 1, indent: 72, color: p.border),
                              _MemberTile(
                                member: m,
                                isMe: m.userId == me,
                                onTap: canManage && m.userId != me ? () => _openMember(context, m) : null,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _openMember(BuildContext context, TeamMember m) =>
      JpOverlays.sheet<void>(context, child: _MemberSheet(member: m));
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.isMe, this.onTap});

  final TeamMember member;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final m = member;
    final subtitle = switch (m.status) {
      MemberStatus.invited => m.email ?? 'En attente d’acceptation',
      _ when m.joinedAt != null =>
        '${m.email ?? ''}${m.email != null ? ' · ' : ''}depuis ${Formatters.date(m.joinedAt!)}',
      _ => m.email ?? '',
    };
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.xs),
      leading: Opacity(
        opacity: m.status == MemberStatus.active ? 1 : 0.55,
        child: JpAvatar(name: m.displayName),
      ),
      title: Text(isMe ? '${m.displayName} (vous)' : m.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: JpBadge(
        label: m.roleName,
        tone: switch (m.status) {
          MemberStatus.suspended => JpTone.danger,
          MemberStatus.invited => JpTone.warning,
          _ => m.roleCode == 'OWNER' ? JpTone.accent : JpTone.brand,
        },
      ),
      titleTextStyle: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
    );
  }
}

/// Choix d'un rôle : liste de cartes avec résumé des droits.
class RolePicker extends StatelessWidget {
  const RolePicker({super.key, required this.roles, required this.selected, required this.onChanged});

  final List<TeamRole> roles;
  final String? selected;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return RadioGroup<String>(
      groupValue: selected,
      onChanged: (v) {
        if (v != null) onChanged?.call(v);
      },
      child: Column(
        children: [
          for (final r in roles)
            Padding(
              padding: const EdgeInsets.only(bottom: JpSpacing.sm),
              child: JpCard(
                onTap: onChanged == null ? null : () => onChanged!(r.code),
                padding: const EdgeInsets.symmetric(horizontal: JpSpacing.md, vertical: JpSpacing.sm),
                borderColor: selected == r.code ? p.brand : null,
                child: Row(
                  children: [
                    Radio<String>(value: r.code, enabled: onChanged != null),
                    const SizedBox(width: JpSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.name, style: JpTypography.bodyStrong.copyWith(color: p.textPrimary)),
                          if (r.summary.isNotEmpty)
                            Text(r.summary, style: JpTypography.caption.copyWith(color: p.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showInviteSheet(BuildContext context) => JpOverlays.sheet<void>(
  context,
  title: 'Inviter une personne',
  subtitle: 'Elle se connecte avec son propre compte. Sans compte, elle reçoit un e-mail pour le créer.',
  child: const _InviteForm(),
);

class _InviteForm extends ConsumerStatefulWidget {
  const _InviteForm();

  @override
  ConsumerState<_InviteForm> createState() => _InviteFormState();
}

class _InviteFormState extends ConsumerState<_InviteForm> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  String _role = 'CASHIER';
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final email = _email.text.trim().toLowerCase();
    try {
      final r = await ref.read(teamActionsProvider).invite(email, _role);
      if (!mounted) return;
      Navigator.of(context).pop();
      JpOverlays.toast(
        context,
        r.accountCreated
            ? 'Invitation envoyée par e-mail à $email.'
            : '$email verra l’invitation à sa prochaine ouverture de l’application.',
        tone: JpTone.success,
      );
    } on AppFailure catch (f) {
      if (mounted) {
        setState(
          () => _error = f.code == 'PLAN_LIMIT_REACHED'
              ? 'Votre abonnement ne permet pas d’ajouter plus de membres. Changez de formule pour inviter cette personne.'
              : f.message,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(assignableRolesProvider);
    if (roles.isNotEmpty && !roles.any((r) => r.code == _role)) _role = roles.last.code;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormErrorBanner(message: _error),
          JpTextField(
            label: 'E-mail',
            hint: 'prenom@exemple.sn',
            controller: _email,
            prefixIcon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            enabled: !_sending,
            validator: Validators.email,
          ),
          const SizedBox(height: JpSpacing.xl),
          Text('Rôle', style: JpTypography.label.copyWith(color: context.palette.textPrimary)),
          const SizedBox(height: JpSpacing.sm),
          if (ref.watch(teamRolesProvider).isLoading)
            const JpSkeletonList(itemCount: 3, padding: EdgeInsets.zero)
          else
            RolePicker(roles: roles, selected: _role, onChanged: _sending ? null : (v) => setState(() => _role = v)),
          const SizedBox(height: JpSpacing.lg),
          JpButton(
            label: 'Envoyer l’invitation',
            icon: Icons.send_rounded,
            isLoading: _sending,
            onPressed: roles.isEmpty ? null : _send,
          ),
        ],
      ),
    );
  }
}

class _MemberSheet extends ConsumerStatefulWidget {
  const _MemberSheet({required this.member});

  final TeamMember member;

  @override
  ConsumerState<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends ConsumerState<_MemberSheet> {
  late String _role = widget.member.roleCode;
  bool _busy = false;

  TeamMember get m => widget.member;

  Future<void> _run(Future<void> Function(TeamActions a) action, String success) async {
    setState(() => _busy = true);
    try {
      await action(ref.read(teamActionsProvider));
      if (!mounted) return;
      Navigator.of(context).pop();
      JpOverlays.toast(context, success, tone: JpTone.success);
    } on AppFailure catch (f) {
      if (mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final invited = m.status == MemberStatus.invited;
    final ok = await JpOverlays.confirm(
      context,
      title: invited ? 'Annuler l’invitation ?' : 'Retirer ${m.displayName} ?',
      message: invited
          ? 'La personne ne pourra plus rejoindre l’entreprise avec cette invitation.'
          : 'Son accès est coupé immédiatement. Ses ventes et actions passées restent dans l’historique.',
      confirmLabel: invited ? 'Annuler l’invitation' : 'Retirer',
      cancelLabel: 'Garder',
      destructive: true,
    );
    if (ok) await _run((a) => a.remove(m), invited ? 'Invitation annulée.' : '${m.displayName} a été retiré.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final roles = ref.watch(teamRolesProvider).value ?? const <TeamRole>[];
    final mine = ref.watch(permissionsProvider);
    final current = roles.where((r) => r.code == m.roleCode).firstOrNull;
    // Règle du backend : on ne touche qu'à un membre dont le rôle est couvert par le nôtre.
    final manageable = current == null || current.assignableWith(mine);
    final assignable = ref.watch(assignableRolesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            JpAvatar(name: m.displayName, size: JpSize.avatarLg),
            const SizedBox(width: JpSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.displayName, style: JpTypography.title.copyWith(color: p.textPrimary)),
                  if (m.email != null) Text(m.email!, style: JpTypography.body.copyWith(color: p.textSecondary)),
                  const SizedBox(height: JpSpacing.xs),
                  JpBadge(
                    label: m.status.label,
                    dot: true,
                    tone: switch (m.status) {
                      MemberStatus.active => JpTone.success,
                      MemberStatus.invited => JpTone.warning,
                      MemberStatus.suspended => JpTone.danger,
                    },
                  ),
                ],
              ),
            ),
            if (m.phone != null)
              IconButton.filledTonal(
                tooltip: 'Appeler',
                icon: const Icon(Icons.call_outlined),
                onPressed: () => ContactLinks.call(m.phone!),
              ),
          ],
        ),
        const SizedBox(height: JpSpacing.xl),
        if (!manageable)
          const JpBanner(
            icon: Icons.lock_outline_rounded,
            tone: JpTone.warning,
            message: 'Ce membre a un rôle supérieur au vôtre : seul un propriétaire peut le modifier.',
          )
        else ...[
          Text('Rôle', style: JpTypography.label.copyWith(color: p.textPrimary)),
          const SizedBox(height: JpSpacing.sm),
          RolePicker(roles: assignable, selected: _role, onChanged: _busy ? null : (v) => setState(() => _role = v)),
          if (_role != m.roleCode) ...[
            const SizedBox(height: JpSpacing.sm),
            JpButton(
              label: 'Enregistrer le nouveau rôle',
              isLoading: _busy,
              onPressed: () => _run((a) => a.changeRole(m, _role), 'Rôle mis à jour.'),
            ),
          ],
          const SizedBox(height: JpSpacing.xl),
          if (m.status == MemberStatus.active)
            JpButton.outline(
              label: 'Suspendre l’accès',
              icon: Icons.block_rounded,
              onPressed: _busy
                  ? null
                  : () async {
                      final ok = await JpOverlays.confirm(
                        context,
                        title: 'Suspendre ${m.displayName} ?',
                        message: 'Il ne pourra plus utiliser l’application pour cette entreprise jusqu’à réactivation.',
                        confirmLabel: 'Suspendre',
                        destructive: true,
                      );
                      if (ok) await _run((a) => a.setStatus(m, MemberStatus.suspended), 'Accès suspendu.');
                    },
            )
          else if (m.status == MemberStatus.suspended)
            JpButton.outline(
              label: 'Réactiver l’accès',
              icon: Icons.check_circle_outline_rounded,
              onPressed: _busy ? null : () => _run((a) => a.setStatus(m, MemberStatus.active), 'Accès réactivé.'),
            ),
          const SizedBox(height: JpSpacing.sm),
          JpButton.ghost(
            label: m.status == MemberStatus.invited ? 'Annuler l’invitation' : 'Retirer de l’entreprise',
            icon: Icons.person_remove_outlined,
            onPressed: _busy ? null : _remove,
          ),
        ],
      ],
    );
  }
}
