import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/spreadsheet/xlsx.dart';
import '../../business/application/workspace_controller.dart';
import '../../business/data/business_repository.dart';
import '../../exports/application/excel_export.dart';
import '../../exports/domain/export_sheets.dart';
import '../../inventory/data/inventory_repository.dart';
import '../application/catalog_providers.dart';
import '../data/products_repository.dart';
import '../domain/catalog_models.dart';
import '../domain/product_import.dart';

/// Import du catalogue depuis Excel / CSV : modèle à remplir, aperçu des
/// lignes (erreurs et doublons signalés), puis création une à une par les
/// mêmes écritures que le formulaire produit (droits et limites du plan
/// appliqués par la base).
class ProductImportScreen extends ConsumerStatefulWidget {
  const ProductImportScreen({super.key});

  @override
  ConsumerState<ProductImportScreen> createState() => _ProductImportScreenState();
}

enum _Stage { pick, preview, importing, done }

class _ProductImportScreenState extends ConsumerState<ProductImportScreen> {
  _Stage _stage = _Stage.pick;
  bool _reading = false;
  String? _error;
  String? _fileName;
  ImportPreview? _preview;

  int _done = 0;
  int _created = 0;
  final _failures = <(ImportRow, String)>[];
  String? _stopReason;
  bool _cancelled = false;

  String get _businessId => ref.read(activeBusinessProvider)!.businessId;

  Future<void> _downloadTemplate() => ExcelExport.run(
    context,
    fileName: 'Modèle import produits JEND PRO.xlsx',
    subject: 'Modèle d’import des produits',
    build: () async => Xlsx.write([ExportSheets.importTemplate()]),
  );

  Future<void> _pick() async {
    setState(() {
      _error = null;
      _reading = true;
    });
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Fichier des produits',
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
      );
      if (file == null) return;
      final table = Xlsx.readTable(await file.readAsBytes(), fileName: file.name);
      final existing = await _existingProducts();
      final preview = ProductImport.preview(
        table,
        existingNames: {for (final p in existing) p.name},
        existingBarcodes: {for (final p in existing) ?p.barcode},
      );
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        if (preview.error != null) {
          _error = preview.error;
        } else if (preview.rows.isEmpty) {
          _error = 'Aucune ligne de produit sous les en-têtes.';
        } else {
          _preview = preview;
          _stage = _Stage.preview;
        }
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Fichier illisible. Enregistrez-le au format Excel (.xlsx) ou CSV.');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  /// Tout le catalogue (actifs et archivés) pour repérer les doublons.
  Future<List<Product>> _existingProducts() async {
    final repo = ref.read(productsRepositoryProvider);
    final out = <Product>[];
    for (final status in ProductStatusFilter.values) {
      var offset = 0;
      while (true) {
        final page = await repo.fetchProducts(_businessId, ProductFilter(status: status), offset: offset, limit: 500);
        out.addAll(page);
        offset += page.length;
        if (page.length < 500) break;
      }
    }
    return out;
  }

  Future<void> _import() async {
    final rows = _preview!.importable;
    final permissions = ref.read(permissionsProvider);
    final withCost = permissions.can(Permission.productsReadCost) && permissions.can(Permission.productsUpdate);
    final withStock = permissions.can(Permission.inventoryAdjust);
    final withCategories = permissions.can(Permission.categoriesManage);
    setState(() {
      _stage = _Stage.importing;
      _done = 0;
      _created = 0;
      _failures.clear();
      _stopReason = null;
      _cancelled = false;
    });

    final products = ref.read(productsRepositoryProvider);
    try {
      final categoryIds = <String, String>{};
      if (withCategories) {
        final names = {for (final r in rows) ?r.category}.toList();
        if (names.isNotEmpty) {
          for (final c in await products.ensureCategories(_businessId, names)) {
            categoryIds[c.name.toLowerCase()] = c.id;
          }
        }
      } else {
        final known = await products.fetchCategories(_businessId);
        for (final c in known) {
          categoryIds[c.name.toLowerCase()] = c.id;
        }
      }
      String? locationId;
      if (withStock && rows.any((r) => (r.stock ?? 0) > 0)) {
        locationId = await ref.read(businessRepositoryProvider).fetchDefaultLocationId(_businessId);
      }

      for (final row in rows) {
        if (_cancelled || !mounted) break;
        try {
          final created = await products.createProduct(
            _businessId,
            row.toNewProduct(categoryId: categoryIds[row.category?.trim().toLowerCase()], withCost: withCost),
          );
          _created++;
          if (locationId != null && (row.stock ?? 0) > 0) {
            try {
              await ref
                  .read(inventoryRepositoryProvider)
                  .setInitialStock(
                    businessId: _businessId,
                    productId: created.id,
                    locationId: locationId,
                    quantity: row.stock!,
                  );
            } on AppFailure catch (f) {
              _failures.add((row, 'Produit créé, stock non enregistré : ${f.message}'));
            }
          }
        } on AppFailure catch (f) {
          if (f.code == 'PLAN_LIMIT_REACHED') {
            _stopReason =
                'Votre abonnement a atteint sa limite de produits actifs. '
                'Les lignes suivantes n’ont pas été importées.';
            break;
          }
          _failures.add((row, _messageFor(f)));
        }
        if (mounted) setState(() => _done++);
      }
    } on AppFailure catch (f) {
      _stopReason = f.message;
    } finally {
      ref.invalidate(productListProvider);
      ref.invalidate(categoriesProvider);
      if (mounted) setState(() => _stage = _Stage.done);
    }
  }

  String _messageFor(AppFailure f) => switch (f.code) {
    'UNIQUE_VIOLATION' => 'Code-barres ou référence déjà utilisé.',
    _ => f.message,
  };

  @override
  Widget build(BuildContext context) {
    final busy = _stage == _Stage.importing;
    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final stop = await JpOverlays.confirm(
          context,
          title: 'Arrêter l’import ?',
          message: 'Les produits déjà créés resteront dans le catalogue.',
          confirmLabel: 'Arrêter',
          cancelLabel: 'Continuer',
          destructive: true,
        );
        if (stop) _cancelled = true;
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Importer des produits')),
        body: switch (_stage) {
          _Stage.pick => _buildPick(context),
          _Stage.preview => _buildPreview(context),
          _Stage.importing => _buildProgress(context),
          _Stage.done => _buildDone(context),
        },
      ),
    );
  }

  Widget _scroll(List<Widget> children, {Widget? bottom}) {
    final p = context.palette;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.md, JpSpacing.gutter, JpSpacing.xxl),
            children: [
              JpConstrained(
                maxWidth: JpSpacing.maxFormWidth + 80,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ],
          ),
        ),
        if (bottom != null)
          DecoratedBox(
            decoration: BoxDecoration(
              color: p.background,
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.md, JpSpacing.gutter, JpSpacing.md),
                child: JpConstrained(maxWidth: JpSpacing.maxFormWidth + 80, child: bottom),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPick(BuildContext context) {
    final p = context.palette;
    Widget step(String n, String title, String text) => Padding(
      padding: const EdgeInsets.only(bottom: JpSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: p.brandSoft,
            child: Text(n, style: JpTypography.label.copyWith(color: p.brand)),
          ),
          const SizedBox(width: JpSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: JpTypography.bodyStrong.copyWith(color: p.textPrimary)),
                const SizedBox(height: 2),
                Text(text, style: JpTypography.bodySmall.copyWith(color: p.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );

    return _scroll(
      [
        const Center(child: JpIllustratedIcon(icon: Icons.table_view_rounded)),
        const SizedBox(height: JpSpacing.lg),
        Text(
          'Ajoutez tout votre catalogue en une fois',
          textAlign: TextAlign.center,
          style: JpTypography.title.copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: JpSpacing.xl),
        step(
          '1',
          'Préparez le fichier',
          'Une ligne par produit. Colonnes obligatoires : « Nom » et « Prix de vente ». '
              'Facultatives : unité, catégorie, code-barres, référence, coût d’achat, stock, seuil d’alerte.',
        ),
        step('2', 'Choisissez-le ici', 'Format Excel (.xlsx) ou CSV, jusqu’à ${ProductImport.maxRows} produits.'),
        step('3', 'Vérifiez puis importez', 'Les erreurs et les produits déjà présents sont signalés avant l’envoi.'),
        JpButton.outline(
          label: 'Télécharger le modèle Excel',
          icon: Icons.download_rounded,
          onPressed: _reading ? null : _downloadTemplate,
        ),
        if (_error != null) ...[
          const SizedBox(height: JpSpacing.lg),
          JpBanner(message: _fileName == null ? _error! : '$_fileName : $_error', tone: JpTone.danger),
        ],
      ],
      bottom: JpButton(
        label: 'Choisir le fichier',
        icon: Icons.upload_file_rounded,
        isLoading: _reading,
        onPressed: _pick,
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final p = context.palette;
    final preview = _preview!;
    final permissions = ref.watch(permissionsProvider);
    final count = preview.importable.length;
    final notes = <String>[
      if (preview.columns.contains(ImportField.cost) && !permissions.can(Permission.productsReadCost))
        'Les coûts d’achat seront ignorés (droit requis).',
      if (preview.columns.contains(ImportField.stock) && !permissions.can(Permission.inventoryAdjust))
        'Les stocks ne seront pas enregistrés (droit requis).',
      if (preview.columns.contains(ImportField.category) && !permissions.can(Permission.categoriesManage))
        'Seules les catégories existantes seront utilisées.',
    ];

    Widget stat(String label, int value, JpTone tone) {
      final c = p.tone(tone);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: JpSpacing.md, horizontal: JpSpacing.sm),
          decoration: BoxDecoration(color: c.background, borderRadius: JpRadius.all(JpRadius.md)),
          child: Column(
            children: [
              Text('$value', style: JpTypography.title.copyWith(color: c.foreground)),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JpTypography.bodySmall.copyWith(color: c.foreground),
              ),
            ],
          ),
        ),
      );
    }

    final problems = preview.rows.where((r) => !r.importable).toList();
    return _scroll(
      [
        Text(
          _fileName ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: JpTypography.bodySmall.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: JpSpacing.md),
        Row(
          children: [
            stat('À importer', count, JpTone.success),
            const SizedBox(width: JpSpacing.sm),
            stat('Déjà présents', preview.duplicates, JpTone.neutral),
            const SizedBox(width: JpSpacing.sm),
            stat('À corriger', preview.invalid, JpTone.danger),
          ],
        ),
        for (final n in notes) ...[const SizedBox(height: JpSpacing.md), JpBanner(message: n)],
        if (count > 0) ...[
          const SizedBox(height: JpSpacing.xl),
          JpSectionHeader(title: 'Aperçu'),
          for (final r in preview.importable.take(5))
            _RowTile(title: r.name, subtitle: _describe(r), amount: r.salePrice),
          if (count > 5)
            Padding(
              padding: const EdgeInsets.only(top: JpSpacing.sm),
              child: Text(
                '… et ${count - 5} autre${count - 5 > 1 ? 's' : ''}',
                style: JpTypography.bodySmall.copyWith(color: p.textSecondary),
              ),
            ),
        ],
        if (problems.isNotEmpty) ...[
          const SizedBox(height: JpSpacing.xl),
          JpSectionHeader(title: 'Lignes ignorées'),
          for (final r in problems.take(50))
            _RowTile(
              title: 'Ligne ${r.line} · ${r.name.isEmpty ? 'sans nom' : r.name}',
              subtitle: r.duplicate ? 'Déjà dans le catalogue ou en double dans le fichier' : r.errors.join(' · '),
              tone: r.duplicate ? JpTone.neutral : JpTone.danger,
            ),
          if (problems.length > 50)
            Text('… et ${problems.length - 50} autres', style: JpTypography.bodySmall.copyWith(color: p.textSecondary)),
        ],
        const SizedBox(height: JpSpacing.lg),
        JpButton.ghost(
          label: 'Choisir un autre fichier',
          icon: Icons.swap_horiz_rounded,
          onPressed: () => setState(() {
            _stage = _Stage.pick;
            _preview = null;
            _error = null;
          }),
        ),
      ],
      bottom: JpButton(
        label: count == 0 ? 'Rien à importer' : 'Importer $count produit${count > 1 ? 's' : ''}',
        icon: Icons.playlist_add_check_rounded,
        onPressed: count == 0 ? null : _import,
      ),
    );
  }

  String _describe(ImportRow r) => [
    r.unit,
    ?r.category,
    if (r.stock != null) 'stock ${Formatters.quantity(r.stock!)}',
    if (r.barcode != null) r.barcode!,
  ].join(' · ');

  Widget _buildProgress(BuildContext context) {
    final p = context.palette;
    final total = _preview!.importable.length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(JpSpacing.xl),
        child: JpConstrained(
          maxWidth: JpSpacing.maxFormWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Import en cours…', style: JpTypography.title.copyWith(color: p.textPrimary)),
              const SizedBox(height: JpSpacing.lg),
              ClipRRect(
                borderRadius: JpRadius.all(JpRadius.sm),
                child: LinearProgressIndicator(value: total == 0 ? null : _done / total, minHeight: 8),
              ),
              const SizedBox(height: JpSpacing.md),
              Text('$_done / $total', style: JpTypography.bodyStrong.copyWith(color: p.textSecondary)),
              const SizedBox(height: JpSpacing.sm),
              Text(
                'Gardez l’application ouverte jusqu’à la fin.',
                textAlign: TextAlign.center,
                style: JpTypography.bodySmall.copyWith(color: p.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDone(BuildContext context) {
    final p = context.palette;
    final ok = _created > 0 && _failures.isEmpty && _stopReason == null && !_cancelled;
    return _scroll(
      [
        Center(
          child: JpIllustratedIcon(
            icon: ok ? Icons.check_rounded : Icons.info_outline_rounded,
            tone: ok ? JpTone.success : JpTone.warning,
          ),
        ),
        const SizedBox(height: JpSpacing.lg),
        Text(
          _created == 0
              ? 'Aucun produit importé'
              : '$_created produit${_created > 1 ? 's' : ''} ajouté${_created > 1 ? 's' : ''} au catalogue',
          textAlign: TextAlign.center,
          style: JpTypography.title.copyWith(color: p.textPrimary),
        ),
        if (_cancelled) ...[
          const SizedBox(height: JpSpacing.lg),
          const JpBanner(message: 'Import arrêté à votre demande.', tone: JpTone.warning),
        ],
        if (_stopReason != null) ...[
          const SizedBox(height: JpSpacing.lg),
          JpBanner(message: _stopReason!, tone: JpTone.warning),
        ],
        if (_failures.isNotEmpty) ...[
          const SizedBox(height: JpSpacing.xl),
          JpSectionHeader(title: 'À vérifier (${_failures.length})'),
          for (final (r, msg) in _failures.take(50))
            _RowTile(title: 'Ligne ${r.line} · ${r.name}', subtitle: msg, tone: JpTone.danger),
        ],
      ],
      bottom: JpButton(
        label: 'Voir le catalogue',
        icon: Icons.inventory_2_outlined,
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.title, required this.subtitle, this.amount, this.tone});

  final String title;
  final String subtitle;
  final int? amount;
  final JpTone? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: JpSpacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          if (tone != null) ...[
            Icon(Icons.error_outline_rounded, size: 18, color: p.tone(tone!).foreground),
            const SizedBox(width: JpSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: JpTypography.bodySmall.copyWith(color: p.textSecondary),
                  ),
              ],
            ),
          ),
          if (amount != null) ...[
            const SizedBox(width: JpSpacing.md),
            JpAmount(amount!, style: JpTypography.bodyStrong),
          ],
        ],
      ),
    );
  }
}
