import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../core/design_system/design_system.dart';

/// Aperçu plein écran d'un document PDF, avec impression et partage.
class DocumentPreviewScreen extends StatelessWidget {
  const DocumentPreviewScreen({
    super.key,
    required this.title,
    required this.filename,
    required this.builder,
    this.format = PdfPageFormat.a4,
  });

  final String title;
  final String filename;
  final PdfPageFormat format;
  final Future<Uint8List> Function() builder;

  static Future<void> open(
    BuildContext context, {
    required String title,
    required String filename,
    required Future<Uint8List> Function() build,
    PdfPageFormat format = PdfPageFormat.a4,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => DocumentPreviewScreen(title: title, filename: filename, builder: build, format: format),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        build: (_) => builder(),
        initialPageFormat: format,
        pdfFileName: filename,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        scrollViewDecoration: BoxDecoration(color: p.surfaceMuted),
        pdfPreviewPageDecoration: BoxDecoration(color: Colors.white, boxShadow: JpShadows.sm(p.shadow)),
        loadingWidget: const Center(child: CircularProgressIndicator()),
        onError: (context, error) => JpErrorState(error: error),
      ),
    );
  }
}
