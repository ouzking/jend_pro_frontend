import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../domain/workspace.dart';

/// Ligne « entreprise » : avatar, nom, ville, rôle.
class BusinessTile extends StatelessWidget {
  const BusinessTile({super.key, required this.membership, this.onTap, this.selected = false, this.loading = false});

  final BusinessMembership membership;
  final VoidCallback? onTap;
  final bool selected;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return JpCard(
      onTap: onTap,
      borderColor: selected ? p.brand : null,
      padding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.md),
      child: Row(
        children: [
          JpAvatar(name: membership.businessName, size: JpSize.avatarMd + 4),
          const SizedBox(width: JpSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  membership.businessName,
                  style: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: JpSpacing.xxs),
                Text(
                  [membership.roleName, if (membership.city != null) membership.city!].join(' · '),
                  style: JpTypography.bodySmall.copyWith(color: p.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: JpSpacing.sm),
          if (loading)
            const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
          else if (selected)
            Icon(Icons.check_circle_rounded, color: p.brand)
          else
            Icon(Icons.chevron_right_rounded, color: p.textMuted),
        ],
      ),
    );
  }
}
