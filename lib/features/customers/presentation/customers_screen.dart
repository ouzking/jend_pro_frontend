import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/pagination/paged.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../application/customer_providers.dart';
import '../domain/customer_models.dart';

/// Clients : qui me doit combien, en un coup d'œil.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(customerFilterProvider).query;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => ref.read(customerFilterProvider.notifier).search(v));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final permissions = ref.watch(permissionsProvider);
    final filter = ref.watch(customerFilterProvider);
    final list = ref.watch(customerListProvider);
    final debt = ref.watch(customersDebtProvider).value;
    final currency = ref.watch(activeBusinessProvider)?.currencyCode ?? 'XOF';
    final canCreate = permissions.can(Permission.customersCreate);

    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              heroTag: 'new-customer',
              onPressed: () => context.push(Routes.customerNew),
              backgroundColor: p.brand,
              foregroundColor: p.textOnBrand,
              elevation: 2,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text('Client', style: JpTypography.label.copyWith(color: p.textOnBrand)),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: JpConstrained(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(customersDebtProvider);
              await ref.refresh(customerListProvider.future).then<void>((_) {}, onError: (_) {});
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 500) ref.read(customerListProvider.notifier).loadMore();
                return false;
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.lg, JpSpacing.gutter, JpSpacing.md),
                    sliver: SliverToBoxAdapter(
                      child: Semantics(
                        header: true,
                        child: Text('Clients', style: JpTypography.headline.copyWith(color: p.textPrimary)),
                      ),
                    ),
                  ),
                  if (debt != null)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, 0, JpSpacing.gutter, JpSpacing.md),
                      sliver: SliverToBoxAdapter(
                        child: _DebtCard(
                          amount: debt,
                          currency: currency,
                          onTap: () => ref.read(customerFilterProvider.notifier).segment(CustomerSegment.debtors),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter),
                    sliver: SliverToBoxAdapter(
                      child: JpTextField(
                        controller: _search,
                        hint: 'Nom ou téléphone',
                        prefixIcon: Icons.search_rounded,
                        onChanged: _onSearch,
                        suffix: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Effacer',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _search.clear();
                                  _onSearch('');
                                },
                              ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 60,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.md),
                        children: [
                          for (final (s, label) in const [
                            (CustomerSegment.all, 'Tous'),
                            (CustomerSegment.debtors, 'Me doivent de l’argent'),
                            (CustomerSegment.archived, 'Archivés'),
                          ]) ...[
                            ChoiceChip(
                              label: Text(label),
                              selected: filter.segment == s,
                              onSelected: (_) => ref.read(customerFilterProvider.notifier).segment(s),
                            ),
                            const SizedBox(width: JpSpacing.sm),
                          ],
                        ],
                      ),
                    ),
                  ),
                  ..._list(context, list, filter, currency, canCreate),
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _list(
    BuildContext context,
    AsyncValue<Paged<Customer>> list,
    CustomerFilter filter,
    String currency,
    bool canCreate,
  ) {
    final page = list.value;
    if (page == null) {
      return [
        list.hasError
            ? SliverFillRemaining(
                hasScrollBody: false,
                child: JpErrorState(error: list.error!, onRetry: () => ref.invalidate(customerListProvider)),
              )
            : const SliverToBoxAdapter(child: JpSkeletonList(itemCount: 7)),
      ];
    }
    if (page.items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: filter.query.isNotEmpty
              ? JpEmptyState(
                  icon: Icons.search_off_rounded,
                  tone: JpTone.neutral,
                  title: 'Aucun résultat',
                  message: 'Aucun client ne correspond à « ${filter.query} ».',
                )
              : switch (filter.segment) {
                  CustomerSegment.debtors => const JpEmptyState(
                    icon: Icons.verified_outlined,
                    tone: JpTone.success,
                    title: 'Personne ne vous doit d’argent',
                    message: 'Tous les comptes clients sont à jour.',
                  ),
                  CustomerSegment.archived => const JpEmptyState(
                    icon: Icons.inventory_outlined,
                    tone: JpTone.neutral,
                    title: 'Aucun client archivé',
                  ),
                  CustomerSegment.all => JpEmptyState(
                    icon: Icons.people_alt_outlined,
                    title: 'Votre carnet de clients est vide',
                    message: 'Enregistrez vos clients pour suivre leurs achats et leurs crédits.',
                    actionLabel: canCreate ? 'Ajouter un client' : null,
                    onAction: canCreate ? () => context.push(Routes.customerNew) : null,
                  ),
                },
        ),
      ];
    }
    final p = context.palette;
    return [
      if (list.isLoading) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
      SliverList.separated(
        itemCount: page.items.length,
        separatorBuilder: (_, _) => Divider(indent: JpSpacing.gutter + 56, color: p.border),
        itemBuilder: (context, i) => CustomerTile(
          customer: page.items[i],
          currency: currency,
          onTap: () => context.push(Routes.customerDetail(page.items[i].id)),
        ),
      ),
      if (page.loadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(JpSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
    ];
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({required this.amount, required this.currency, required this.onTap});

  final int amount;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final owed = amount > 0;
    final tone = p.tone(owed ? JpTone.warning : JpTone.success);
    return JpCard(
      onTap: owed ? onTap : null,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: tone.background, borderRadius: JpRadius.all(JpRadius.md)),
            child: Icon(Icons.account_balance_wallet_outlined, color: tone.foreground),
          ),
          const SizedBox(width: JpSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'On vous doit',
                  style: JpTypography.caption.copyWith(color: p.textSecondary, fontWeight: FontWeight.w600),
                ),
                JpAmount(amount, currency: currency, style: JpTypography.title, color: owed ? tone.foreground : null),
              ],
            ),
          ),
          if (owed) Text('Voir', style: JpTypography.label.copyWith(color: p.brand)),
        ],
      ),
    );
  }
}

/// Ligne client : avatar, contact, situation financière.
class CustomerTile extends StatelessWidget {
  const CustomerTile({super.key, required this.customer, required this.currency, this.onTap});

  final Customer customer;
  final String currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = customer;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: JpSpacing.gutter, vertical: JpSpacing.md),
        child: Row(
          children: [
            JpAvatar(name: c.name, size: 44),
            const SizedBox(width: JpSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: JpTypography.bodyStrong.copyWith(
                      color: c.archived ? p.textMuted : p.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    [
                      if (c.phone != null) Formatters.phone(c.phone!),
                      if (c.unlimitedCredit)
                        'Crédit illimité'
                      else if (c.creditLimit! > 0)
                        'Plafond ${Formatters.money(c.creditLimit!, currency: currency)}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: JpTypography.caption.copyWith(color: p.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: JpSpacing.sm),
            if (c.owes)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Doit', style: JpTypography.caption.copyWith(color: p.warning)),
                  JpAmount(c.balance, currency: currency, style: JpTypography.label, color: p.warning),
                ],
              )
            else
              const JpBadge(label: 'À jour', tone: JpTone.success, dot: true),
          ],
        ),
      ),
    );
  }
}
