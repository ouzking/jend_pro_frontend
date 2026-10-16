import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/spreadsheet/xlsx.dart';
import '../../../core/design_system/design_system.dart';
import '../../business/application/workspace_controller.dart';
import '../../customers/data/customers_repository.dart';
import '../../customers/domain/customer_models.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/catalog_models.dart';
import '../../reports/domain/report_models.dart';
import '../../sales/data/sales_repository.dart';
import '../domain/export_sheets.dart';

final excelExportProvider = Provider<ExcelExport>(ExcelExport.new);

/// Exports Excel : lit toutes les pages (droits et RLS inchangés : on ne
/// voit que ce que l'écran voit), construit le classeur et ouvre le partage.
class ExcelExport {
  ExcelExport(this._ref);

  final Ref _ref;

  static const _page = 500;

  /// Garde-fou mémoire pour les très gros historiques.
  static const maxRows = 20000;

  String get _businessId => _ref.read(activeBusinessProvider)!.businessId;

  String get _businessName => _ref.read(activeBusinessProvider)?.businessName ?? 'JEND PRO';

  static Future<List<T>> _all<T>(Future<List<T>> Function(int offset, int limit) fetch) async {
    final out = <T>[];
    while (out.length < maxRows) {
      final page = await fetch(out.length, _page);
      out.addAll(page);
      if (page.length < _page) break;
    }
    return out;
  }

  Future<Uint8List> catalog() async {
    final repo = _ref.read(productsRepositoryProvider);
    final active = await _all((o, l) => repo.fetchProducts(_businessId, const ProductFilter(), offset: o, limit: l));
    final archived = await _all(
      (o, l) => repo.fetchProducts(
        _businessId,
        const ProductFilter(status: ProductStatusFilter.archived),
        offset: o,
        limit: l,
      ),
    );
    final withCost = _ref.read(permissionsProvider).can(Permission.productsReadCost);
    return Xlsx.write([
      ExportSheets.products([...active, ...archived], withCost: withCost),
    ]);
  }

  Future<Uint8List> customers() async {
    final repo = _ref.read(customersRepositoryProvider);
    final list = await _all((o, l) => repo.fetchCustomers(_businessId, const CustomerFilter(), offset: o, limit: l));
    return Xlsx.write([ExportSheets.customers(list)]);
  }

  Future<Uint8List> sales({DateTime? from, DateTime? to}) async {
    final repo = _ref.read(salesRepositoryProvider);
    final list = await _all((o, l) => repo.fetchSales(_businessId, from: from, to: to, offset: o, limit: l));
    return Xlsx.write(ExportSheets.sales(list));
  }

  Uint8List report(ReportData data, String periodLabel) => Xlsx.write(ExportSheets.report(data, periodLabel));

  /// Nom de fichier lisible : « Catalogue - Boutique Awa - 2026-10-16.xlsx ».
  String fileName(String what) {
    final shop = _businessName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    return '$what - $shop - ${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx';
  }

  static Future<void> share(Uint8List bytes, {required String fileName, required String subject}) =>
      SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: Xlsx.mimeType, name: fileName)],
          fileNameOverrides: [fileName],
          subject: subject,
        ),
      );

  /// Construit puis partage, avec indicateur d'attente et message d'erreur.
  static Future<void> run(
    BuildContext context, {
    required String fileName,
    required String subject,
    required Future<Uint8List> Function() build,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                SizedBox(width: 20),
                Expanded(child: Text('Préparation du fichier Excel…')),
              ],
            ),
          ),
        ),
      ),
    );
    Uint8List bytes;
    try {
      bytes = await build();
    } catch (e) {
      navigator.pop();
      if (context.mounted) JpOverlays.toast(context, exportErrorMessage(e), tone: JpTone.danger);
      return;
    }
    navigator.pop();
    if (!context.mounted) return;
    try {
      await share(bytes, fileName: fileName, subject: subject);
    } catch (_) {
      if (context.mounted) JpOverlays.toast(context, 'Partage impossible sur cet appareil.', tone: JpTone.danger);
    }
  }
}

/// Message lisible pour un export raté.
String exportErrorMessage(Object e) => e is AppFailure ? e.message : 'L’export a échoué. Réessayez.';
