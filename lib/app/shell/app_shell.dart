import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_system.dart';
import '../../core/permissions/permission.dart';
import '../../features/business/application/workspace_controller.dart';
import '../router/app_router.dart';
import '../router/routes.dart';

class _Destination {
  const _Destination(this.branch, this.label, this.icon, this.selectedIcon);

  final int branch;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Cadre principal : barre de navigation (téléphone) ou rail (tablette),
/// action « Vendre » toujours à portée de pouce, entrées adaptées au rôle.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionsProvider);
    final restricted = ref.watch(workspaceProvider.select((w) => w.value?.isRestricted ?? false));
    final canSell = permissions.can(Permission.salesCreate);

    final destinations = [
      const _Destination(ShellBranch.home, 'Accueil', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
      if (permissions.can(Permission.productsRead))
        const _Destination(ShellBranch.catalog, 'Catalogue', Icons.inventory_2_outlined, Icons.inventory_2_rounded),
      if (permissions.can(Permission.customersRead))
        const _Destination(ShellBranch.customers, 'Clients', Icons.people_alt_outlined, Icons.people_alt_rounded),
      const _Destination(ShellBranch.more, 'Plus', Icons.widgets_outlined, Icons.widgets_rounded),
    ];

    void goBranch(int branch) {
      HapticFeedback.selectionClick();
      navigationShell.goBranch(branch, initialLocation: branch == navigationShell.currentIndex);
    }

    void openSale() {
      HapticFeedback.mediumImpact();
      context.push(Routes.sale);
    }

    final body = Column(
      children: [
        if (restricted)
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(JpSpacing.lg, JpSpacing.sm, JpSpacing.lg, 0),
              child: const JpBanner(
                tone: JpTone.warning,
                icon: Icons.lock_clock_outlined,
                message: 'Abonnement à renouveler : l’application est en lecture seule. La caisse reste ouverte.',
              ),
            ),
          ),
        Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: restricted, child: navigationShell),
        ),
      ],
    );

    if (JpBreakpoints.isTablet(context)) {
      return Scaffold(
        body: Row(
          children: [
            _SideRail(
              destinations: destinations,
              currentBranch: navigationShell.currentIndex,
              onSelect: goBranch,
              onSale: canSell ? openSale : null,
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: _BottomBar(
        destinations: destinations,
        currentBranch: navigationShell.currentIndex,
        onSelect: goBranch,
        onSale: canSell ? openSale : null,
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.destinations,
    required this.currentBranch,
    required this.onSelect,
    required this.onSale,
  });

  final List<_Destination> destinations;
  final int currentBranch;
  final ValueChanged<int> onSelect;
  final VoidCallback? onSale;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = <Widget>[
      for (final d in destinations)
        Expanded(
          child: _NavItem(destination: d, selected: d.branch == currentBranch, onTap: () => onSelect(d.branch)),
        ),
    ];
    if (onSale != null) {
      items.insert((items.length / 2).ceil(), Expanded(child: _SaleButton(onTap: onSale!)));
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: JpSize.navBar,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.selected, required this.onTap});

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.brandStrong : p.textMuted;
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        highlightShape: BoxShape.rectangle,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: JpMotion.base,
              curve: JpMotion.emphasized,
              width: selected ? 56 : 40,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? p.brandSoft : Colors.transparent,
                borderRadius: JpRadius.all(JpRadius.pill),
              ),
              child: Icon(selected ? destination.selectedIcon : destination.icon, color: color, size: JpSize.iconMd),
            ),
            const SizedBox(height: JpSpacing.xs),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: JpTypography.caption.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleButton extends StatelessWidget {
  const _SaleButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Le bouton est plus haut que les icônes voisines : on le remonte pour
    // que le libellé « Vendre » reste aligné avec les autres libellés.
    return Transform.translate(
      offset: const Offset(0, -6),
      child: Semantics(
        button: true,
        label: 'Nouvelle vente',
        excludeSemantics: true,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: JpRadius.all(JpRadius.lg),
                child: Ink(
                  width: 52,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: JpRadius.all(JpRadius.lg),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [p.brand, p.heroEnd],
                    ),
                    boxShadow: JpShadows.glow(p.brand),
                  ),
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
                ),
              ),
            ),
            ...[
              const SizedBox(height: JpSpacing.xs),
              Text(
                'Vendre',
                style: JpTypography.caption.copyWith(color: p.brandStrong, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.destinations,
    required this.currentBranch,
    required this.onSelect,
    required this.onSale,
  });

  final List<_Destination> destinations;
  final int currentBranch;
  final ValueChanged<int> onSelect;
  final VoidCallback? onSale;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: 96,
          child: Column(
            children: [
              const SizedBox(height: JpSpacing.xl),
              const JpLogoMark(size: 40),
              const SizedBox(height: JpSpacing.xxl),
              if (onSale != null) ...[
                SizedBox(height: 76, child: _SaleButton(onTap: onSale!)),
                const SizedBox(height: JpSpacing.lg),
              ],
              for (final d in destinations)
                SizedBox(
                  height: 72,
                  child: _NavItem(destination: d, selected: d.branch == currentBranch, onTap: () => onSelect(d.branch)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
