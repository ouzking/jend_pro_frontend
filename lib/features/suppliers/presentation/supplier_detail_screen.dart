import 'dart:async';

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
import '../../products/data/products_repository.dart';
import '../../products/domain/catalog_models.dart';
import '../../products/presentation/widgets/product_visuals.dart';
import '../application/supplier_providers.dart';
import '../domain/supplier_models.dart';

class SupplierDetailScreen extends ConsumerWidget {
  const SupplierDetailScreen({super.key, required this.supplierId});

  final String supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supplier = ref.watch(supplierDetailProvider(supplierId));
    final canManage = ref.watch(permissionsProvider).can(Permission.suppliersManage);
    final s = supplier.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fournisseur'),
        actions: [
          if (s != null && canManage)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') {
                  context.push(Routes.supplierEdit(s.id));
                  return;
                }
                final ok = await JpOverlays.confirm(
                  context,
                  title: s.archived ? 'Réactiver ce fournisseur ?' : 'Archiver ce fournisseur ?',
                  message: s.archived
                      ? 'Il sera de nouveau proposé pour les achats.'
                      : 'Il ne sera plus proposé pour les achats. Son historique est conservé.',
                  confirmLabel: s.archived ? 'Réactiver' : 'Archiver',
                  destructive: !s.archived,
                );
                if (!ok) return;
                try {
                  await ref.read(supplierActionsProvider).setArchived(s, archived: !s.archived);
                } on AppFailure catch (f) {
                  if (context.mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
                }
              },
              itemBuilder: (_) => [
                if (!s.archived) const PopupMenuItem(value: 'edit', child: Text('Modifier la fiche')),
                PopupMenuItem(value: 'archive', child: Text(s.archived ? 'Réactiver' : 'Archiver')),
              ],
            ),
        ],
      ),
      body: JpAsyncView<Supplier>(
        value: supplier,
        onRetry: () => ref.invalidate(supplierDetailProvider(supplierId)),
        data: (s) => _Body(supplier: s),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.supplier});

  final Supplier supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final s = supplier;
    final permissions = ref.watch(permissionsProvider);
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final balance = ref.watch(supplierBalancesProvider).value?[s.id];
    final products = ref.watch(supplierProductsProvider(s.id));
    final purchases = ref.watch(supplierPurchasesProvider(s.id));
    final canManage = permissions.can(Permission.suppliersManage) && !s.archived;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(supplierDetailProvider(s.id));
        ref.invalidate(supplierProductsProvider(s.id));
        ref.invalidate(supplierPurchasesProvider(s.id));
        ref.invalidate(supplierBalancesProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, JpSpacing.huge),
        children: [
          JpConstrained(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    JpAvatar(name: s.name, size: JpSize.avatarLg),
                    const SizedBox(width: JpSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name, style: JpTypography.title.copyWith(color: p.textPrimary)),
                          if (s.contactName != null)
                            Text(s.contactName!, style: JpTypography.body.copyWith(color: p.textSecondary)),
                          if (s.archived) const JpBadge(label: 'Archivé', icon: Icons.archive_outlined),
                        ],
                      ),
                    ),
                  ],
                ),
                if (s.phone != null) ...[
                  const SizedBox(height: JpSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: JpButton.outline(
                          label: Formatters.phone(s.phone!),
                          icon: Icons.call_outlined,
                          size: JpButtonSize.medium,
                          onPressed: () => ContactLinks.call(s.phone!),
                        ),
                      ),
                      const SizedBox(width: JpSpacing.sm),
                      Expanded(
                        child: JpButton.outline(
                          label: 'WhatsApp',
                          icon: Icons.chat_outlined,
                          size: JpButtonSize.medium,
                          onPressed: () => ContactLinks.whatsApp(s.phone!),
                        ),
                      ),
                    ],
                  ),
                ],
                if (permissions.can(Permission.purchasesRead)) ...[
                  const SizedBox(height: JpSpacing.xl),
                  JpCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reste à payer',
                                style: JpTypography.caption.copyWith(
                                  color: p.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: JpSpacing.xs),
                              if ((balance?.amountDue ?? 0) > 0)
                                JpAmount(
                                  balance!.amountDue,
                                  currency: currency,
                                  style: JpTypography.headline,
                                  color: p.danger,
                                )
                              else
                                Text('Rien', style: JpTypography.headline.copyWith(color: p.success)),
                            ],
                          ),
                        ),
                        if ((balance?.advancesPaid ?? 0) > 0)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Acomptes versés', style: JpTypography.caption.copyWith(color: p.textMuted)),
                              JpAmount(balance!.advancesPaid, currency: currency, style: JpTypography.label),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
                if (s.email != null || s.address != null || s.notes != null) ...[
                  const SizedBox(height: JpSpacing.md),
                  JpCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (icon, text) in [
                          if (s.email != null) (Icons.alternate_email_rounded, s.email!),
                          if (s.address != null) (Icons.place_outlined, s.address!),
                          if (s.notes != null) (Icons.sticky_note_2_outlined, s.notes!),
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: JpSpacing.xs),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(icon, size: 18, color: p.textMuted),
                                const SizedBox(width: JpSpacing.md),
                                Expanded(
                                  child: Text(text, style: JpTypography.body.copyWith(color: p.textSecondary)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: JpSpacing.xxl),
                JpSectionHeader(
                  title: 'Produits fournis',
                  actionLabel: canManage ? 'Ajouter' : null,
                  onAction: () => _addProduct(context, ref, s),
                ),
                JpAsyncView<List<SupplierProduct>>(
                  value: products,
                  onRetry: () => ref.invalidate(supplierProductsProvider(s.id)),
                  loading: const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
                  data: (items) => items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: JpSpacing.md),
                          child: Text(
                            'Associez les articles que ce fournisseur vous livre : ils seront proposés en premier lors des achats.',
                            style: JpTypography.bodySmall.copyWith(color: p.textMuted),
                          ),
                        )
                      : JpCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (var i = 0; i < items.length; i++) ...[
                                if (i > 0) Divider(color: p.border, height: 1),
                                ListTile(
                                  leading: ProductThumb(
                                    name: items[i].productName,
                                    imagePath: items[i].imagePath,
                                    size: 40,
                                  ),
                                  title: Text(items[i].productName),
                                  subtitle: Text(
                                    [
                                      if (items[i].supplierSku != null) 'Réf. ${items[i].supplierSku}',
                                      if (items[i].lastCost != null)
                                        'Dernier coût ${Formatters.money(items[i].lastCost!, currency: currency)}',
                                    ].join(' · '),
                                  ),
                                  trailing: canManage
                                      ? IconButton(
                                          tooltip: 'Retirer',
                                          icon: Icon(Icons.link_off_rounded, color: p.textMuted),
                                          onPressed: () async {
                                            try {
                                              await ref
                                                  .read(supplierActionsProvider)
                                                  .unlinkProduct(s.id, items[i].productId);
                                            } on AppFailure catch (f) {
                                              if (context.mounted) {
                                                JpOverlays.toast(context, f.message, tone: JpTone.danger);
                                              }
                                            }
                                          },
                                        )
                                      : null,
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
                if (permissions.can(Permission.purchasesRead)) ...[
                  const SizedBox(height: JpSpacing.xxl),
                  JpSectionHeader(
                    title: 'Achats récents',
                    actionLabel: permissions.can(Permission.purchasesCreate) && !s.archived ? 'Nouvel achat' : null,
                    onAction: () => context.push(Routes.purchaseNew(supplierId: s.id)),
                  ),
                  JpAsyncView<List<PurchaseSummary>>(
                    value: purchases,
                    onRetry: () => ref.invalidate(supplierPurchasesProvider(s.id)),
                    loading: const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
                    data: (items) => items.isEmpty
                        ? Text(
                            'Aucun achat pour l’instant.',
                            style: JpTypography.bodySmall.copyWith(color: p.textMuted),
                          )
                        : JpCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (var i = 0; i < items.length; i++) ...[
                                  if (i > 0) Divider(color: p.border, height: 1),
                                  PurchaseSummaryTile(
                                    purchase: items[i],
                                    currency: currency,
                                    onTap: () => context.push(Routes.purchaseDetail(items[i].id)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addProduct(BuildContext context, WidgetRef ref, Supplier s) async {
    final linked = ref.read(supplierProductsProvider(s.id)).value?.map((x) => x.productId).toSet() ?? {};
    final product = await JpOverlays.sheet<Product>(
      context,
      title: 'Ajouter un produit',
      subtitle: s.name,
      child: _ProductPicker(excluded: linked),
    );
    if (product == null) return;
    try {
      await ref.read(supplierActionsProvider).linkProduct(s.id, product.id);
      if (context.mounted) JpOverlays.toast(context, '« ${product.name} » associé.', tone: JpTone.success);
    } on AppFailure catch (f) {
      if (context.mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    }
  }
}

/// Ligne d'achat (statut + reste à payer).
class PurchaseSummaryTile extends StatelessWidget {
  const PurchaseSummaryTile({
    super.key,
    required this.purchase,
    required this.currency,
    this.onTap,
    this.showSupplier = false,
  });

  final PurchaseSummary purchase;
  final String currency;
  final VoidCallback? onTap;

  /// Liste générale des achats : le fournisseur aide à se repérer.
  final bool showSupplier;

  static (String, JpTone) statusOf(String status) => switch (status) {
    'DRAFT' => ('Brouillon', JpTone.neutral),
    'ORDERED' => ('Commandé', JpTone.info),
    'RECEIVED' => ('Reçu', JpTone.success),
    _ => ('Annulé', JpTone.danger),
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (label, tone) = statusOf(purchase.status);
    final unpaid = purchase.status != 'CANCELLED' && purchase.remaining > 0;
    return ListTile(
      onTap: onTap,
      title: Text(
        showSupplier
            ? '${purchase.supplierName ?? 'Sans fournisseur'} · ${purchase.number}'
            : '${purchase.number} · ${Formatters.date(purchase.createdAt)}',
      ),
      subtitle: Row(
        children: [
          JpBadge(label: label, tone: tone),
          if (unpaid) ...[
            const SizedBox(width: JpSpacing.sm),
            Text(
              'Reste ${Formatters.money(purchase.remaining, currency: currency)}',
              style: JpTypography.caption.copyWith(color: p.danger),
            ),
          ],
        ],
      ),
      trailing: JpAmount(purchase.total, currency: currency, style: JpTypography.label),
    );
  }
}

class _ProductPicker extends ConsumerStatefulWidget {
  const _ProductPicker({required this.excluded});

  final Set<String> excluded;

  @override
  ConsumerState<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<_ProductPicker> {
  Timer? _debounce;
  List<Product>? _results;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final businessId = ref.read(activeBusinessProvider)!.businessId;
    final results = await ref
        .read(productsRepositoryProvider)
        .fetchProducts(businessId, ProductFilter(query: q), offset: 0, limit: 30);
    if (mounted) setState(() => _results = results.where((p) => !widget.excluded.contains(p.id)).toList());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JpTextField(
          hint: 'Rechercher un produit',
          prefixIcon: Icons.search_rounded,
          autofocus: true,
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 250), () => _load(v));
          },
        ),
        const SizedBox(height: JpSpacing.md),
        if (_results == null)
          const Padding(
            padding: EdgeInsets.all(JpSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_results!.isEmpty)
          Padding(
            padding: const EdgeInsets.all(JpSpacing.lg),
            child: Text(
              'Aucun produit à associer.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textMuted),
            ),
          )
        else
          for (final product in _results!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ProductThumb(name: product.name, imagePath: product.imagePath, size: 40),
              title: Text(product.name),
              subtitle: Text(product.categoryName ?? product.unit),
              onTap: () => Navigator.of(context).pop(product),
            ),
      ],
    );
  }
}
