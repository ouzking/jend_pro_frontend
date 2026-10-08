import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/errors/app_failure.dart';
import '../../application/catalog_providers.dart';
import '../../domain/catalog_models.dart';

/// Gestion des catégories (`categories.manage`) : ajouter, renommer, archiver.
Future<void> showCategoriesSheet(BuildContext context) =>
    JpOverlays.sheet<void>(context, title: 'Catégories', child: const _CategoriesManager());

/// Choix d'une catégorie pour un produit ; peut en créer une à la volée.
/// Renvoie la catégorie choisie, ou `null` si annulé. Le choix « Aucune »
/// renvoie [Category] avec un identifiant vide.
Future<Category?> pickCategory(BuildContext context, {String? selectedId, bool canCreate = false}) =>
    JpOverlays.sheet<Category>(
      context,
      title: 'Catégorie',
      child: _CategoryPicker(selectedId: selectedId, canCreate: canCreate),
    );

const noCategory = Category(id: '', name: 'Aucune');

class _CategoryPicker extends ConsumerStatefulWidget {
  const _CategoryPicker({required this.selectedId, required this.canCreate});

  final String? selectedId;
  final bool canCreate;

  @override
  ConsumerState<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends ConsumerState<_CategoryPicker> {
  final _name = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _creating = true);
    try {
      final category = await ref.read(productActionsProvider).createCategory(_name.text);
      if (mounted) Navigator.of(context).pop(category);
    } on AppFailure catch (f) {
      if (mounted) {
        JpOverlays.toast(
          context,
          f.code == 'UNIQUE_VIOLATION' ? 'Cette catégorie existe déjà.' : f.message,
          tone: JpTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final categories = ref.watch(categoriesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JpAsyncView<List<Category>>(
          value: categories,
          onRetry: () => ref.invalidate(categoriesProvider),
          loading: const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          data: (list) => Column(
            children: [
              for (final c in [noCategory, ...list])
                ListTile(
                  title: Text(c.name, style: TextStyle(color: c.id.isEmpty ? p.textMuted : null)),
                  trailing: (widget.selectedId ?? '') == c.id ? Icon(Icons.check_rounded, color: p.brand) : null,
                  onTap: () => Navigator.of(context).pop(c),
                ),
            ],
          ),
        ),
        if (widget.canCreate) ...[
          const SizedBox(height: JpSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: JpTextField(
                  hint: 'Nouvelle catégorie',
                  controller: _name,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _create(),
                  enabled: !_creating,
                ),
              ),
              const SizedBox(width: JpSpacing.sm),
              SizedBox(
                height: JpSize.input,
                child: JpButton(
                  label: 'Créer',
                  size: JpButtonSize.medium,
                  expand: false,
                  isLoading: _creating,
                  onPressed: _create,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CategoriesManager extends ConsumerStatefulWidget {
  const _CategoriesManager();

  @override
  ConsumerState<_CategoriesManager> createState() => _CategoriesManagerState();
}

class _CategoriesManagerState extends ConsumerState<_CategoriesManager> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && success != null) JpOverlays.toast(context, success, tone: JpTone.success);
    } on AppFailure catch (f) {
      if (mounted) {
        JpOverlays.toast(
          context,
          f.code == 'UNIQUE_VIOLATION' ? 'Une catégorie porte déjà ce nom.' : f.message,
          tone: JpTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(Category c) async {
    final controller = TextEditingController(text: c.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renommer'),
        content: JpTextField(controller: controller, autofocus: true, maxLength: 80),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == c.name) return;
    await _run(() => ref.read(productActionsProvider).renameCategory(c, name), success: 'Catégorie renommée.');
  }

  Future<void> _archive(Category c) async {
    final ok = await JpOverlays.confirm(
      context,
      title: 'Archiver « ${c.name} » ?',
      message: 'Les produits restent intacts ; la catégorie n’est simplement plus proposée.',
      confirmLabel: 'Archiver',
      destructive: true,
    );
    if (ok) await _run(() => ref.read(productActionsProvider).archiveCategory(c), success: 'Catégorie archivée.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final categories = ref.watch(categoriesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: JpTextField(
                hint: 'Nouvelle catégorie',
                controller: _name,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                enabled: !_busy,
              ),
            ),
            const SizedBox(width: JpSpacing.sm),
            SizedBox(
              height: JpSize.input,
              child: JpButton(
                label: 'Ajouter',
                size: JpButtonSize.medium,
                expand: false,
                onPressed: _busy
                    ? null
                    : () {
                        final name = _name.text.trim();
                        if (name.isEmpty) return;
                        _run(() async {
                          await ref.read(productActionsProvider).createCategory(name);
                          _name.clear();
                        });
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: JpSpacing.md),
        JpAsyncView<List<Category>>(
          value: categories,
          onRetry: () => ref.invalidate(categoriesProvider),
          loading: const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(JpSpacing.xl),
                  child: Text(
                    'Aucune catégorie. Elles aident à retrouver vos produits plus vite.',
                    textAlign: TextAlign.center,
                    style: JpTypography.bodySmall.copyWith(color: p.textMuted),
                  ),
                )
              : Column(
                  children: [
                    for (final c in list)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.label_outline_rounded, color: p.textMuted),
                        title: Text(c.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Renommer',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: _busy ? null : () => _rename(c),
                            ),
                            IconButton(
                              tooltip: 'Archiver',
                              icon: Icon(Icons.archive_outlined, color: p.danger),
                              onPressed: _busy ? null : () => _archive(c),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
