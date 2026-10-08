import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../auth/application/auth_session.dart';
import '../../auth/data/auth_repository.dart';
import '../../business/application/workspace_controller.dart';
import '../../business/domain/workspace.dart';
import '../../business/presentation/business_switcher_sheet.dart';

/// « Plus » : compte, commerce, sécurité, déconnexion. Les modules
/// secondaires (fournisseurs, achats, dépenses, employés…) s'y ajouteront.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await JpOverlays.confirm(
      context,
      title: 'Se déconnecter ?',
      message: 'Vous devrez saisir à nouveau votre e-mail et votre mot de passe.',
      confirmLabel: 'Déconnexion',
      icon: Icons.logout_rounded,
    );
    if (!confirmed) return;
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on AppFailure catch (f) {
      if (context.mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final profile = ref.watch(userProfileProvider).value;
    final workspace = ref.watch(workspaceProvider).value;
    final business = workspace?.active;
    final subscription = workspace?.subscription;
    final permissions = ref.watch(permissionsProvider);
    final canSwitch = (workspace?.memberships.length ?? 0) > 1;

    return JpPage(
      title: 'Plus',
      onRefresh: () => ref.read(workspaceProvider.notifier).refreshContext(),
      slivers: [
        JpSliverBox(
          bottom: JpSpacing.xxl,
          child: JpCard(
            child: Row(
              children: [
                JpAvatar(name: profile?.displayName, size: JpSize.avatarLg),
                const SizedBox(width: JpSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.displayName ?? '—',
                        style: JpTypography.titleSmall.copyWith(color: p.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: JpSpacing.xxs),
                      Text(
                        profile?.email ?? '',
                        style: JpTypography.bodySmall.copyWith(color: p.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (business != null) ...[
                        const SizedBox(height: JpSpacing.sm),
                        JpBadge(label: business.roleName, tone: JpTone.brand, icon: Icons.verified_user_outlined),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (business != null)
          JpSliverBox(
            bottom: JpSpacing.xxl,
            child: _Section(
              title: 'Commerce',
              children: [
                _MenuRow(
                  icon: Icons.storefront_outlined,
                  title: business.businessName,
                  subtitle: business.city ?? 'Commerce actif',
                  trailing: canSwitch ? Text('Changer', style: JpTypography.label.copyWith(color: p.brand)) : null,
                  onTap: canSwitch ? () => showBusinessSwitcher(context) : null,
                ),
                if (subscription != null) _SubscriptionRow(subscription: subscription),
              ],
            ),
          ),
        if (permissions.canAny(const [Permission.suppliersRead, Permission.purchasesRead]))
          JpSliverBox(
            bottom: JpSpacing.xxl,
            child: _Section(
              title: 'Gestion',
              children: [
                if (permissions.can(Permission.purchasesRead))
                  _MenuRow(
                    icon: Icons.add_shopping_cart_rounded,
                    title: 'Achats',
                    subtitle: 'Commandes, réceptions, paiements fournisseurs',
                    onTap: () => context.push(Routes.purchases),
                  ),
                if (permissions.can(Permission.suppliersRead))
                  _MenuRow(
                    icon: Icons.local_shipping_outlined,
                    title: 'Fournisseurs',
                    subtitle: 'Contacts, produits fournis, dettes',
                    onTap: () => context.push(Routes.suppliers),
                  ),
              ],
            ),
          ),
        JpSliverBox(
          bottom: JpSpacing.xxl,
          child: _Section(
            title: 'Sécurité',
            children: [
              _MenuRow(
                icon: Icons.password_rounded,
                title: 'Changer le mot de passe',
                onTap: () => context.push(Routes.changePassword),
              ),
            ],
          ),
        ),
        JpSliverBox(
          child: _Section(
            children: [
              _MenuRow(
                icon: Icons.logout_rounded,
                title: 'Se déconnecter',
                destructive: true,
                onTap: () => _signOut(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow({required this.subscription});

  final SubscriptionStatus subscription;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (subscription.status) {
      _ when subscription.isRestricted => ('Restreint', JpTone.danger),
      'TRIALING' => ('Essai', JpTone.accent),
      'ACTIVE' => ('Actif', JpTone.success),
      'PAST_DUE' => ('Paiement en retard', JpTone.warning),
      _ => ('Expiré', JpTone.danger),
    };
    final end = subscription.isTrial ? subscription.trialEndsAt : subscription.currentPeriodEnd;
    return _MenuRow(
      icon: Icons.workspace_premium_outlined,
      title: 'Abonnement ${subscription.planName}',
      subtitle: end == null ? null : '${subscription.isTrial ? 'Essai jusqu’au' : 'Jusqu’au'} ${Formatters.date(end)}',
      trailing: JpBadge(label: label, tone: tone, dot: true),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children, this.title});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: JpSpacing.xs, bottom: JpSpacing.sm),
            child: Text(title!.toUpperCase(), style: JpTypography.overline.copyWith(color: p.textMuted)),
          ),
        JpCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(indent: 64, color: p.border),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = p.tone(destructive ? JpTone.danger : JpTone.neutral);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.md),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: tone.background, borderRadius: JpRadius.all(JpRadius.sm)),
                child: Icon(icon, size: 20, color: destructive ? p.danger : p.textSecondary),
              ),
              const SizedBox(width: JpSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: JpTypography.bodyStrong.copyWith(color: destructive ? p.danger : p.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) Text(subtitle!, style: JpTypography.bodySmall.copyWith(color: p.textMuted)),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: JpSpacing.sm),
                trailing!,
              ] else if (onTap != null && !destructive)
                Icon(Icons.chevron_right_rounded, color: p.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
