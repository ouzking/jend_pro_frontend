import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../application/settings_providers.dart';
import '../domain/settings_models.dart';

/// Boutiques et dépôts (`settings.manage`). Le nombre d'emplacements actifs
/// est limité par la formule d'abonnement (vérifié en base).
class LocationsScreen extends ConsumerWidget {
  const LocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final locations = ref.watch(locationDetailsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Emplacements')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-location',
        onPressed: () => showLocationSheet(context),
        backgroundColor: p.brand,
        foregroundColor: p.textOnBrand,
        elevation: 2,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text('Emplacement', style: JpTypography.label.copyWith(color: p.textOnBrand)),
      ),
      body: JpConstrained(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(locationDetailsProvider.future).then<void>((_) {}, onError: (_) {}),
          child: JpAsyncView<List<LocationDetail>>(
            value: locations,
            onRetry: () => ref.invalidate(locationDetailsProvider),
            loading: const JpSkeletonList(itemCount: 3),
            data: (list) {
              final active = list.where((l) => !l.archived).toList();
              final archived = list.where((l) => l.archived).toList();
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, 120),
                children: [
                  Text(
                    'Chaque emplacement a son propre stock. Les ventes et les dépenses peuvent y être rattachées.',
                    style: JpTypography.bodySmall.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: JpSpacing.lg),
                  for (final l in active) ...[_LocationCard(location: l), const SizedBox(height: JpSpacing.sm)],
                  if (archived.isNotEmpty) ...[
                    const SizedBox(height: JpSpacing.lg),
                    Text('ARCHIVÉS', style: JpTypography.overline.copyWith(color: p.textMuted)),
                    const SizedBox(height: JpSpacing.sm),
                    for (final l in archived) ...[_LocationCard(location: l), const SizedBox(height: JpSpacing.sm)],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.location});

  final LocationDetail location;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = location;
    return Opacity(
      opacity: l.archived ? 0.6 : 1,
      child: JpCard(
        onTap: () => showLocationSheet(context, location: l),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: p.brandSoft, borderRadius: JpRadius.all(JpRadius.md)),
              child: Icon(
                l.kind == LocationKind.warehouse ? Icons.warehouse_outlined : Icons.storefront_outlined,
                color: p.brand,
              ),
            ),
            const SizedBox(width: JpSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.name, style: JpTypography.bodyStrong.copyWith(color: p.textPrimary)),
                  Text(
                    [l.kind.label, if (l.address != null) l.address!].join(' · '),
                    style: JpTypography.caption.copyWith(color: p.textMuted),
                  ),
                ],
              ),
            ),
            if (l.isDefault) const JpBadge(label: 'Principal', tone: JpTone.accent),
            if (l.archived) const JpBadge(label: 'Archivé'),
          ],
        ),
      ),
    );
  }
}

Future<void> showLocationSheet(BuildContext context, {LocationDetail? location}) => JpOverlays.sheet<void>(
  context,
  title: location == null ? 'Nouvel emplacement' : location.name,
  child: _LocationForm(location: location),
);

class _LocationForm extends ConsumerStatefulWidget {
  const _LocationForm({this.location});

  final LocationDetail? location;

  @override
  ConsumerState<_LocationForm> createState() => _LocationFormState();
}

class _LocationFormState extends ConsumerState<_LocationForm> {
  late final _name = TextEditingController(text: widget.location?.name);
  late final _address = TextEditingController(text: widget.location?.address);
  late LocationKind _kind = widget.location?.kind ?? LocationKind.store;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  String _message(AppFailure f) => switch (f.code) {
    'PLAN_LIMIT_REACHED' =>
      'Votre formule ne permet pas d’emplacement supplémentaire. Passez à une formule supérieure.',
    'LOCATION_HAS_STOCK' =>
      'Cet emplacement contient encore du stock : transférez-le ou mettez-le à zéro avant d’archiver.',
    'UNIQUE_VIOLATION' => 'Un emplacement porte déjà ce nom.',
    _ => f.message,
  };

  Future<void> _run(Future<void> Function(SettingsActions a) action, String success) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(settingsActionsProvider));
      if (!mounted) return;
      Navigator.of(context).pop();
      JpOverlays.toast(context, success, tone: JpTone.success);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = _message(f));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Donnez un nom à l’emplacement.');
      return Future.value();
    }
    final l = widget.location;
    return l == null
        ? _run((a) => a.createLocation(name: _name.text, kind: _kind, address: _address.text), 'Emplacement ajouté.')
        : _run(
            (a) => a.updateLocation(l.id, name: _name.text, kind: _kind, address: _address.text),
            'Emplacement mis à jour.',
          );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.location;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormErrorBanner(message: _error),
        JpTextField(
          label: 'Nom',
          hint: 'Ex. Boutique Marché Sandaga, Dépôt Pikine',
          controller: _name,
          autofocus: l == null,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          enabled: !_busy,
        ),
        const SizedBox(height: JpSpacing.md),
        SegmentedButton<LocationKind>(
          segments: [
            for (final k in LocationKind.values)
              ButtonSegment(
                value: k,
                label: Text(k.label),
                icon: Icon(k == LocationKind.warehouse ? Icons.warehouse_outlined : Icons.storefront_outlined),
              ),
          ],
          selected: {_kind},
          onSelectionChanged: _busy ? null : (v) => setState(() => _kind = v.single),
        ),
        const SizedBox(height: JpSpacing.lg),
        JpTextField(label: 'Adresse', hint: 'Facultatif', controller: _address, enabled: !_busy),
        const SizedBox(height: JpSpacing.xl),
        JpButton(label: l == null ? 'Ajouter' : 'Enregistrer', isLoading: _busy, onPressed: _save),
        if (l != null && !l.isDefault) ...[
          const SizedBox(height: JpSpacing.sm),
          JpButton.ghost(
            label: l.archived ? 'Réactiver' : 'Archiver',
            icon: l.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
            onPressed: _busy
                ? null
                : () => _run(
                    (a) => a.setLocationArchived(l.id, archived: !l.archived),
                    l.archived ? 'Emplacement réactivé.' : 'Emplacement archivé.',
                  ),
          ),
        ],
        if (l?.isDefault ?? false) ...[
          const SizedBox(height: JpSpacing.md),
          const JpBanner(
            icon: Icons.info_outline_rounded,
            message: 'L’emplacement principal ne peut pas être archivé.',
          ),
        ],
      ],
    );
  }
}
