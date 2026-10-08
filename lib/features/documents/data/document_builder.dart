import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/formatting/formatters.dart';
import '../../customers/domain/customer_models.dart';
import '../../sales/domain/sale_models.dart';
import '../domain/document_issuer.dart';

/// Génère les documents PDF à partir des valeurs **figées par le serveur**
/// (aucun montant n'est recalculé ici). Polices standard PDF (Helvetica) :
/// légères, lisibles par toutes les imprimantes, encodage Windows-1252.
abstract final class DocumentBuilder {
  static const footer = 'Propulsé par JËND PRO';

  // ------------------------------------------------------------------ Ticket

  /// Ticket de caisse pour imprimante thermique (rouleau 58 ou 80 mm).
  static Future<Uint8List> ticket(Sale sale, DocumentIssuer issuer, {TicketWidth width = TicketWidth.mm58}) {
    final narrow = width == TicketWidth.mm58;
    final base = narrow ? 7.5 : 9.0;
    final format = (narrow ? PdfPageFormat.roll57 : PdfPageFormat.roll80).copyWith(
      marginLeft: 2 * PdfPageFormat.mm,
      marginRight: 2 * PdfPageFormat.mm,
      marginTop: 3 * PdfPageFormat.mm,
      marginBottom: 8 * PdfPageFormat.mm,
    );
    final cur = issuer.currency;
    final body = pw.TextStyle(fontSize: base);
    final small = pw.TextStyle(fontSize: base - 1);
    final bold = pw.TextStyle(fontSize: base, fontWeight: pw.FontWeight.bold);

    pw.Widget row(String label, String value, {pw.TextStyle? style}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 0.8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: pw.Text(clean(label), style: style ?? body)),
          pw.Text(clean(value), style: style ?? body),
        ],
      ),
    );
    pw.Widget rule() => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Divider(height: 1, thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
    );

    final doc = _document('Ticket ${sale.number}', issuer);
    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (issuer.logo != null)
              pw.Center(
                child: pw.Image(issuer.logo!, height: narrow ? 28 : 36, fit: pw.BoxFit.contain),
              ),
            pw.SizedBox(height: 2),
            pw.Text(
              clean(issuer.name.toUpperCase()),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: base + 3, fontWeight: pw.FontWeight.bold),
            ),
            for (final line in [
              issuer.location,
              issuer.phone == null ? null : 'Tél. ${Formatters.phone(issuer.phone!)}',
              issuer.legalLine,
            ])
              if (line != null) pw.Text(clean(line), textAlign: pw.TextAlign.center, style: small),
            rule(),
            if (sale.cancelled) ...[
              pw.Text(
                'VENTE ANNULÉE',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: base + 2, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
            ],
            row('Ticket', sale.number, style: bold),
            row('Date', Formatters.dateTime(sale.soldAt)),
            if (sale.customerName != null) row('Client', sale.customerName!),
            rule(),
            for (final l in sale.lines) ...[
              pw.Text(clean(l.productName), style: bold),
              row(
                '  ${Formatters.quantity(l.quantity)} x ${Formatters.money(l.unitPrice, currency: cur, withSymbol: false)}',
                Formatters.money(l.lineTotal, currency: cur, withSymbol: false),
              ),
              if (l.discount > 0)
                row('  Remise', '-${Formatters.money(l.discount, currency: cur, withSymbol: false)}', style: small),
            ],
            rule(),
            if (sale.discount > 0) ...[
              row('Sous-total', Formatters.money(sale.subtotal, currency: cur)),
              row('Remise', '-${Formatters.money(sale.discount, currency: cur)}'),
            ],
            row(
              'TOTAL',
              Formatters.money(sale.total, currency: cur),
              style: pw.TextStyle(fontSize: base + 3, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            for (final pay in sale.payments.where((x) => x.incoming))
              row(pay.method.label, Formatters.money(pay.amount, currency: cur)),
            if (sale.creditAmount > 0)
              row('Reste à payer (crédit)', Formatters.money(sale.creditAmount, currency: cur)),
            for (final r in sale.payments.where((x) => !x.incoming))
              row('Remboursé (${r.method.label})', '-${Formatters.money(r.amount, currency: cur)}'),
            rule(),
            pw.Text('Merci de votre visite !', textAlign: pw.TextAlign.center, style: bold),
            pw.SizedBox(height: 2),
            pw.Text(footer, textAlign: pw.TextAlign.center, style: small),
          ],
        ),
      ),
    );
    return doc.save();
  }

  // ----------------------------------------------------------------- Facture

  /// Facture A4 d'une vente. Le numéro est celui de la vente (séquence
  /// serveur sans trou) ; aucune TVA n'est calculée : le backend n'en gère pas.
  static Future<Uint8List> invoice(Sale sale, DocumentIssuer issuer) {
    final cur = issuer.currency;
    final doc = _document('Facture ${sale.number}', issuer);
    final paid = sale.payments.where((x) => x.incoming).fold<int>(0, (s, x) => s + x.amount);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 18 * PdfPageFormat.mm,
          marginRight: 18 * PdfPageFormat.mm,
          marginTop: 16 * PdfPageFormat.mm,
          marginBottom: 16 * PdfPageFormat.mm,
        ),
        footer: (ctx) => _pageFooter(ctx, issuer),
        build: (_) => [
          _a4Header(
            issuer,
            title: sale.cancelled ? 'FACTURE ANNULÉE' : 'FACTURE',
            meta: [('N°', sale.number), ('Date', Formatters.date(sale.soldAt))],
          ),
          pw.SizedBox(height: 18),
          if (sale.customerName != null)
            _box('Facturé à', [
              sale.customerName!,
              if (sale.customerPhone != null) Formatters.phone(sale.customerPhone!),
            ]),
          pw.SizedBox(height: 18),
          _table(
            headers: const ['Désignation', 'Qté', 'Prix unitaire', 'Remise', 'Montant'],
            flex: const [5, 1.4, 2.2, 1.8, 2.4],
            rows: [
              for (final l in sale.lines)
                [
                  l.productName,
                  Formatters.quantity(l.quantity),
                  Formatters.money(l.unitPrice, currency: cur),
                  l.discount > 0 ? Formatters.money(l.discount, currency: cur) : '',
                  Formatters.money(l.lineTotal, currency: cur),
                ],
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Spacer(flex: 3),
              pw.Expanded(
                flex: 2,
                child: pw.Column(
                  children: [
                    if (sale.discount > 0) ...[
                      _totalRow('Sous-total', Formatters.money(sale.subtotal, currency: cur)),
                      _totalRow('Remise', '-${Formatters.money(sale.discount, currency: cur)}'),
                    ],
                    _totalRow('Total', Formatters.money(sale.total, currency: cur), strong: true),
                    _totalRow('Payé', Formatters.money(paid, currency: cur)),
                    if (sale.creditAmount > 0)
                      _totalRow('Reste à payer', Formatters.money(sale.creditAmount, currency: cur), strong: true),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          if (sale.payments.isNotEmpty)
            pw.Text(
              clean(
                'Règlement : ${sale.payments.where((x) => x.incoming).map((x) => '${x.method.label} ${Formatters.money(x.amount, currency: cur)}').join(' · ')}',
              ),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          if (sale.cancelled && sale.cancelReason != null)
            pw.Text(clean('Motif d’annulation : ${sale.cancelReason}'), style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
    return doc.save();
  }

  // ----------------------------------------------------------------- Relevé

  /// Relevé de compte client (opérations les plus récentes d'abord, solde
  /// après chaque opération tel que calculé en base).
  static Future<Uint8List> statement(
    Customer customer,
    List<CustomerTransaction> transactions,
    DocumentIssuer issuer, {
    DateTime? issuedAt,
  }) {
    final cur = issuer.currency;
    final doc = _document('Relevé ${customer.name}', issuer);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 18 * PdfPageFormat.mm,
          marginRight: 18 * PdfPageFormat.mm,
          marginTop: 16 * PdfPageFormat.mm,
          marginBottom: 16 * PdfPageFormat.mm,
        ),
        footer: (ctx) => _pageFooter(ctx, issuer),
        build: (_) => [
          _a4Header(
            issuer,
            title: 'RELEVÉ DE COMPTE',
            meta: [('Édité le', Formatters.date(issuedAt ?? DateTime.now()))],
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _box('Client', [
                  customer.name,
                  if (customer.phone != null) Formatters.phone(customer.phone!),
                  if (customer.address != null) customer.address!,
                ]),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _box(customer.balance > 0 ? 'Montant dû' : 'Solde', [
                  Formatters.money(customer.balance, currency: cur),
                ], emphasize: true),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          if (transactions.isEmpty)
            pw.Text('Aucune opération.', style: const pw.TextStyle(color: PdfColors.grey700))
          else
            _table(
              headers: const ['Date', 'Opération', 'Montant', 'Solde'],
              flex: const [2.4, 4.6, 2.2, 2.2],
              rows: [
                for (final t in transactions)
                  [
                    Formatters.date(t.createdAt),
                    [t.type.label, if (t.saleNumber != null) t.saleNumber!, if (t.note != null) t.note!].join(' · '),
                    '${t.amount > 0 ? '+' : ''}${Formatters.money(t.amount, currency: cur)}',
                    Formatters.money(t.balanceAfter, currency: cur),
                  ],
              ],
            ),
          pw.SizedBox(height: 10),
          pw.Text(
            '« + » : achat à crédit (la dette augmente) · « - » : règlement ou correction (la dette diminue).',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
    return doc.save();
  }

  // ------------------------------------------------------------- Texte brut

  /// Reçu texte pour WhatsApp / SMS.
  static String receiptText(Sale sale, DocumentIssuer issuer) {
    final cur = issuer.currency;
    final b = StringBuffer()
      ..writeln('*${issuer.name}*')
      ..writeln('Reçu ${sale.number} · ${Formatters.dateTime(sale.soldAt)}');
    if (sale.cancelled) b.writeln('*VENTE ANNULÉE*');
    b.writeln();
    for (final l in sale.lines) {
      b.writeln(
        '${l.productName} : ${Formatters.quantity(l.quantity)} x ${Formatters.money(l.unitPrice, currency: cur)}'
        ' = ${Formatters.money(l.lineTotal, currency: cur)}',
      );
    }
    b.writeln();
    if (sale.discount > 0) b.writeln('Remise : -${Formatters.money(sale.discount, currency: cur)}');
    b.writeln('*Total : ${Formatters.money(sale.total, currency: cur)}*');
    for (final pay in sale.payments.where((x) => x.incoming)) {
      b.writeln('${pay.method.label} : ${Formatters.money(pay.amount, currency: cur)}');
    }
    if (sale.creditAmount > 0) b.writeln('Reste à payer : ${Formatters.money(sale.creditAmount, currency: cur)}');
    b
      ..writeln()
      ..write('Merci de votre visite !');
    return b.toString();
  }

  // --------------------------------------------------------------- Communs

  static pw.Document _document(String title, DocumentIssuer issuer) => pw.Document(
    title: clean(title),
    author: clean(issuer.name),
    creator: 'JËND PRO',
    theme: pw.ThemeData.withFont(base: pw.Font.helvetica(), bold: pw.Font.helveticaBold()),
  );

  static const _brand = PdfColor.fromInt(0xFF1D4536);
  static const _line = PdfColor.fromInt(0xFFDDE3E0);

  static pw.Widget _a4Header(DocumentIssuer issuer, {required String title, required List<(String, String)> meta}) =>
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (issuer.logo != null) ...[
            pw.SizedBox(width: 56, height: 56, child: pw.Image(issuer.logo!, fit: pw.BoxFit.contain)),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  clean(issuer.name),
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _brand),
                ),
                for (final l in [
                  if (issuer.legalName != null && issuer.legalName != issuer.name) issuer.legalName,
                  issuer.location,
                  [issuer.phone, issuer.email].whereType<String>().join(' · '),
                  issuer.legalLine,
                ])
                  if (l != null && l.isNotEmpty)
                    pw.Text(clean(l), style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                clean(title),
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _brand),
              ),
              pw.SizedBox(height: 4),
              for (final (k, v) in meta) pw.Text(clean('$k : $v'), style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        ],
      );

  static pw.Widget _box(String title, List<String> lines, {bool emphasize = false}) => pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _line),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(clean(title.toUpperCase()), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        pw.SizedBox(height: 3),
        for (final (i, l) in lines.indexed)
          pw.Text(
            clean(l),
            style: pw.TextStyle(
              fontSize: emphasize ? 16 : 10,
              fontWeight: i == 0 ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
      ],
    ),
  );

  static pw.Widget _table({
    required List<String> headers,
    required List<double> flex,
    required List<List<String>> rows,
  }) {
    pw.Widget cell(String text, int col, {bool header = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        clean(text),
        textAlign: col == 0 || (col == 1 && headers.length == 4) ? pw.TextAlign.left : pw.TextAlign.right,
        style: pw.TextStyle(
          fontSize: header ? 8.5 : 9.5,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: header ? PdfColors.white : PdfColors.black,
        ),
      ),
    );
    return pw.Table(
      columnWidths: {for (final (i, f) in flex.indexed) i: pw.FlexColumnWidth(f)},
      border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5)),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _brand),
          children: [for (final (i, h) in headers.indexed) cell(h, i, header: true)],
        ),
        for (final r in rows) pw.TableRow(children: [for (final (i, c) in r.indexed) cell(c, i)]),
      ],
    );
  }

  static pw.Widget _totalRow(String label, String value, {bool strong = false}) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
    decoration: strong ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEAF5EF)) : null,
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            clean(label),
            style: pw.TextStyle(fontSize: 10, fontWeight: strong ? pw.FontWeight.bold : null),
          ),
        ),
        pw.Text(
          clean(value),
          style: pw.TextStyle(fontSize: strong ? 12 : 10, fontWeight: strong ? pw.FontWeight.bold : null),
        ),
      ],
    ),
  );

  static pw.Widget _pageFooter(pw.Context ctx, DocumentIssuer issuer) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 12),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            clean('${issuer.name} · $footer'),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        pw.Text(
          'Page ${ctx.pageNumber}/${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    ),
  );

  /// Caractères supplémentaires de Windows-1252 (au-delà de Latin-1).
  static const _cp1252 = '€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ';

  /// Rend un texte imprimable avec les polices standard : espaces insécables
  /// (formats français) → espaces, caractères hors Windows-1252 supprimés.
  static String clean(String input) {
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      if (rune == 0x202F || rune == 0x00A0 || rune == 0x2009) {
        out.write(' ');
      } else if (rune == 0x2212) {
        out.write('-');
      } else if ((rune >= 0x20 && rune < 0x7F) || (rune >= 0xA0 && rune <= 0xFF) || _cp1252.contains(ch)) {
        out.write(ch);
      } else if (rune == 0x0A) {
        out.write(ch);
      }
      // Autres caractères (émojis…) : ignorés plutôt qu'imprimés en « ? ».
    }
    return out.toString();
  }
}
