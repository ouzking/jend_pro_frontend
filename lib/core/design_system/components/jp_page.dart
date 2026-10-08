import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../tokens/jp_metrics.dart';
import '../tokens/jp_typography.dart';

/// Page d'onglet standard : grand titre, sous-titre, actions, contenu en
/// slivers (listes paginées performantes), largeur limitée sur tablette.
class JpPage extends StatelessWidget {
  const JpPage({
    super.key,
    required this.title,
    required this.slivers,
    this.subtitle,
    this.actions = const [],
    this.onRefresh,
    this.floatingActionButton,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> slivers;
  final Future<void> Function()? onRefresh;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverSafeArea(
          bottom: false,
          sliver: SliverPadding(
            padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.lg, JpSpacing.sm, JpSpacing.lg),
            sliver: SliverToBoxAdapter(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: JpSpacing.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(title, style: JpTypography.headline.copyWith(color: p.textPrimary)),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: JpSpacing.xxs),
                            Text(subtitle!, style: JpTypography.body.copyWith(color: p.textSecondary)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          ),
        ),
        ...slivers,
        const SliverToBoxAdapter(child: SizedBox(height: JpSpacing.huge)),
      ],
    );
    if (onRefresh != null) {
      scroll = RefreshIndicator(onRefresh: onRefresh!, child: scroll);
    }
    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: JpSpacing.maxContentWidth),
          child: scroll,
        ),
      ),
    );
  }
}

/// Contenu non-sliver avec la marge latérale standard.
class JpSliverBox extends StatelessWidget {
  const JpSliverBox({super.key, required this.child, this.bottom = 0});

  final Widget child;
  final double bottom;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: EdgeInsets.fromLTRB(JpSpacing.gutter, 0, JpSpacing.gutter, bottom),
    sliver: SliverToBoxAdapter(child: child),
  );
}
