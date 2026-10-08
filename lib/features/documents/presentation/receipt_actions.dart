import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';

import '../../../core/contact/contact_links.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../sales/domain/sale_models.dart';
import '../application/document_providers.dart';
import '../data/document_builder.dart';
import '../domain/document_issuer.dart';
import 'document_preview_screen.dart';

/// Boutons « Imprimer » / « Partager » d'un reçu de vente.
class ReceiptActions extends ConsumerStatefulWidget {
  const ReceiptActions({super.key, required this.sale});

  final Sale sale;

  @override
  ConsumerState<ReceiptActions> createState() => _ReceiptActionsState();
}

class _ReceiptActionsState extends ConsumerState<ReceiptActions> {
  bool _busy = false;

  Sale get sale => widget.sale;

  Future<DocumentIssuer> _issuer() => ref.read(documentIssuerProvider.future);

  PdfPageFormat _rollFormat(TicketWidth w) => w == TicketWidth.mm58 ? PdfPageFormat.roll57 : PdfPageFormat.roll80;

  Future<Uint8List> _ticket() async =>
      DocumentBuilder.ticket(sale, await _issuer(), width: ref.read(ticketWidthProvider));

  Future<Uint8List> _invoice() async => DocumentBuilder.invoice(sale, await _issuer());

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on AppFailure catch (f) {
      if (mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    } catch (_) {
      if (mounted) {
        JpOverlays.toast(context, 'Le document n’a pas pu être préparé. Réessayez.', tone: JpTone.danger);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printTicket() => _run(() async {
    final width = ref.read(ticketWidthProvider);
    await ref
        .read(documentActionsProvider)
        .print(await _ticket(), name: 'Ticket ${sale.number}', format: _rollFormat(width));
  });

  Future<void> _openShareSheet() async {
    final choice = await JpOverlays.sheet<_ShareChoice>(
      context,
      title: 'Partager le reçu',
      subtitle: sale.number,
      child: _ShareSheet(sale: sale),
    );
    if (choice == null || !mounted) return;
    final docs = ref.read(documentActionsProvider);
    switch (choice) {
      case _ShareChoice.ticketPdf:
        await _run(() async => docs.share(await _ticket(), filename: documentFilename('Recu', sale.number)));
      case _ShareChoice.invoicePdf:
        await _run(() async => docs.share(await _invoice(), filename: documentFilename('Facture', sale.number)));
      case _ShareChoice.whatsApp:
        await _run(() async {
          final text = DocumentBuilder.receiptText(sale, await _issuer());
          final ok = sale.customerPhone != null
              ? await ContactLinks.whatsApp(sale.customerPhone!, message: text)
              : await ContactLinks.whatsAppText(text);
          if (!ok && mounted) JpOverlays.toast(context, 'WhatsApp n’a pas pu être ouvert.', tone: JpTone.warning);
        });
      case _ShareChoice.previewTicket:
        await DocumentPreviewScreen.open(
          context,
          title: 'Ticket ${sale.number}',
          filename: documentFilename('Recu', sale.number),
          format: _rollFormat(ref.read(ticketWidthProvider)),
          build: _ticket,
        );
      case _ShareChoice.previewInvoice:
        await DocumentPreviewScreen.open(
          context,
          title: 'Facture ${sale.number}',
          filename: documentFilename('Facture', sale.number),
          build: _invoice,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: JpButton.outline(
            label: 'Imprimer',
            icon: Icons.print_outlined,
            size: JpButtonSize.medium,
            isLoading: _busy,
            onPressed: _printTicket,
          ),
        ),
        const SizedBox(width: JpSpacing.sm),
        Expanded(
          child: JpButton.outline(
            label: 'Partager',
            icon: Icons.ios_share_rounded,
            size: JpButtonSize.medium,
            onPressed: _busy ? null : _openShareSheet,
          ),
        ),
      ],
    );
  }
}

enum _ShareChoice { whatsApp, ticketPdf, invoicePdf, previewTicket, previewInvoice }

class _ShareSheet extends ConsumerWidget {
  const _ShareSheet({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final width = ref.watch(ticketWidthProvider);
    Widget tile(_ShareChoice c, IconData icon, String title, String subtitle) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: p.brandSoft, borderRadius: JpRadius.all(JpRadius.md)),
        child: Icon(icon, color: p.brand, size: 20),
      ),
      title: Text(title, style: JpTypography.bodyStrong.copyWith(color: p.textPrimary)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).pop(c),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile(
          _ShareChoice.whatsApp,
          Icons.chat_outlined,
          'WhatsApp',
          sale.customerPhone != null ? 'Reçu texte envoyé à ${sale.customerName}' : 'Reçu texte, choisissez le contact',
        ),
        tile(_ShareChoice.ticketPdf, Icons.receipt_long_outlined, 'Ticket PDF', 'Format caisse ${width.label}'),
        tile(_ShareChoice.invoicePdf, Icons.description_outlined, 'Facture A4 (PDF)', 'Pour un client professionnel'),
        const Divider(height: JpSpacing.xl),
        tile(_ShareChoice.previewTicket, Icons.visibility_outlined, 'Aperçu du ticket', 'Vérifier avant d’imprimer'),
        tile(_ShareChoice.previewInvoice, Icons.picture_as_pdf_outlined, 'Aperçu de la facture', 'Imprimer en A4'),
        const SizedBox(height: JpSpacing.lg),
        Text('Papier de l’imprimante thermique', style: JpTypography.label.copyWith(color: p.textPrimary)),
        const SizedBox(height: JpSpacing.sm),
        SegmentedButton<TicketWidth>(
          segments: [for (final w in TicketWidth.values) ButtonSegment(value: w, label: Text(w.label))],
          selected: {width},
          showSelectedIcon: false,
          onSelectionChanged: (s) => ref.read(ticketWidthProvider.notifier).set(s.single),
        ),
        const SizedBox(height: JpSpacing.sm),
        Text(
          'Imprimante Bluetooth : installez son application de pilote (service d’impression Android) pour qu’elle apparaisse dans la liste.',
          style: JpTypography.caption.copyWith(color: p.textMuted),
        ),
      ],
    );
  }
}
