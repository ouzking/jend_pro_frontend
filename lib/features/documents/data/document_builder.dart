import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/formatting/formatters.dart';
import '../../customers/domain/customer_models.dart';
import '../../reports/domain/report_models.dart';
import '../../sales/domain/sale_models.dart';
import '../domain/document_issuer.dart';
import 'document_style.dart';

/// Génère les documents PDF à partir des valeurs **figées par le serveur**
/// (aucun montant n'est recalculé ici), avec l'identité du commerce : bandeau
/// à ses couleurs, logo (ou initiales), statut visible au premier regard.
abstract final class DocumentBuilder {
  static const footer = 'Propulsé par JËND PRO';

  /// Polices et marque : l'app installe [DocumentStyle.app] (Roboto) avant
  /// de générer ; par défaut, polices standard PDF.
  static DocumentStyle style = DocumentStyle.standard();

  // Couleurs (identité JËND PRO : forêt, menthe, laiton).
  static const _brand = PdfColor.fromInt(0xFF1D4536);
  static const _brandDark = PdfColor.fromInt(0xFF0E2A20);
  static const _mint = PdfColor.fromInt(0xFF34C78C);
  static const _tint = PdfColor.fromInt(0xFFEFF6F2);
  static const _zebra = PdfColor.fromInt(0xFFF6F8F7);
  static const _line = PdfColor.fromInt(0xFFDDE3E0);
  static const _muted = PdfColor.fromInt(0xFF5B6B64);
  static const _paid = PdfColor.fromInt(0xFF1F9D6B);
  static const _credit = PdfColor.fromInt(0xFFC77700);
  static const _cancel = PdfColor.fromInt(0xFFC0392B);

  static final _a4 = PdfPageFormat.a4.copyWith(
    marginLeft: 16 * PdfPageFormat.mm,
    marginRight: 16 * PdfPageFormat.mm,
    marginTop: 14 * PdfPageFormat.mm,
    marginBottom: 14 * PdfPageFormat.mm,
  );

  // ------------------------------------------------------------------ Ticket

  /// Ticket de caisse pour imprimante thermique (rouleau 58 ou 80 mm) :
  /// noir et blanc, lisible, logo (ou initiales) en tête.
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
    final small = pw.TextStyle(fontSize: base - 1, color: PdfColors.grey800);
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
    pw.Widget rule({bool solid = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Divider(
        height: 1,
        thickness: solid ? 0.8 : 0.5,
        borderStyle: solid ? pw.BorderStyle.solid : pw.BorderStyle.dashed,
      ),
    );
    final status = _statusOf(sale, cur);

    final doc = _document('Ticket ${sale.number}', issuer);
    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(child: _identity(issuer, size: narrow ? 30 : 38, onDark: false)),
            pw.SizedBox(height: 3),
            pw.Text(
              clean(issuer.name.toUpperCase()),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: base + 3, fontWeight: pw.FontWeight.bold, letterSpacing: 0.4),
            ),
            for (final line in [
              issuer.location,
              issuer.phone == null ? null : 'Tél. ${Formatters.phone(issuer.phone!)}',
              issuer.legalLine,
            ])
              if (line != null) pw.Text(clean(line), textAlign: pw.TextAlign.center, style: small),
            rule(solid: true),
            pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
                child: pw.Text(
                  clean(status.ticketLabel),
                  style: pw.TextStyle(fontSize: base + 1, fontWeight: pw.FontWeight.bold, letterSpacing: 1),
                ),
              ),
            ),
            pw.SizedBox(height: 3),
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
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(width: 0.8), bottom: pw.BorderSide(width: 0.8)),
              ),
              child: row(
                'TOTAL',
                Formatters.money(sale.total, currency: cur),
                style: pw.TextStyle(fontSize: base + 4, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 2),
            for (final pay in sale.payments.where((x) => x.incoming))
              row(pay.method.label, Formatters.money(pay.amount, currency: cur)),
            if (sale.creditAmount > 0)
              row('Reste à payer', Formatters.money(sale.creditAmount, currency: cur), style: bold),
            for (final r in sale.payments.where((x) => !x.incoming))
              row('Remboursé (${r.method.label})', '-${Formatters.money(r.amount, currency: cur)}'),
            rule(),
            pw.Text('Merci de votre visite !', textAlign: pw.TextAlign.center, style: bold),
            pw.SizedBox(height: 3),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                if (style.brandMark != null) ...[
                  pw.Image(style.brandMark!, width: base + 2, height: base + 2),
                  pw.SizedBox(width: 3),
                ],
                pw.Text(clean(footer), style: small),
              ],
            ),
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
    final status = _statusOf(sale, cur);
    doc.addPage(
      pw.MultiPage(
        pageFormat: _a4,
        footer: (ctx) => _pageFooter(ctx, issuer),
        build: (_) => [
          _a4Header(issuer, title: 'FACTURE', meta: [('N°', sale.number), ('Date', Formatters.date(sale.soldAt))]),
          pw.SizedBox(height: 16),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: sale.customerName == null
                    ? _box('Client', ['Client comptoir'])
                    : _box('Facturé à', [
                        sale.customerName!,
                        if (sale.customerPhone != null) Formatters.phone(sale.customerPhone!),
                        if (sale.customerEmail != null) sale.customerEmail!,
                      ]),
              ),
              pw.SizedBox(width: 16),
              _stamp(status),
            ],
          ),
          pw.SizedBox(height: 16),
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
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (sale.payments.any((x) => x.incoming)) ...[
                      _label('Règlement'),
                      for (final x in sale.payments.where((x) => x.incoming))
                        pw.Text(
                          clean('${x.method.label} · ${Formatters.money(x.amount, currency: cur)}'),
                          style: const pw.TextStyle(fontSize: 9.5),
                        ),
                      pw.SizedBox(height: 10),
                    ],
                    if (sale.cancelled && sale.cancelReason != null) ...[
                      _label('Motif d’annulation'),
                      pw.Text(clean(sale.cancelReason!), style: const pw.TextStyle(fontSize: 9.5)),
                      pw.SizedBox(height: 10),
                    ],
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          drawText: false,
                          data:
                              '${issuer.name} | ${sale.number} | ${Formatters.isoDay(sale.soldAt)} | ${sale.total} $cur',
                          width: 54,
                          height: 54,
                          color: _brandDark,
                        ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: pw.Text(
                            clean(
                              'Référence ${sale.number}\nÀ conserver : présentez-la pour tout retour ou réclamation.',
                            ),
                            style: const pw.TextStyle(fontSize: 8, color: _muted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                flex: 2,
                child: _totalsCard([
                  if (sale.discount > 0) ...[
                    ('Sous-total', Formatters.money(sale.subtotal, currency: cur), false),
                    ('Remise', '-${Formatters.money(sale.discount, currency: cur)}', false),
                  ],
                  ('Total', Formatters.money(sale.total, currency: cur), true),
                  ('Payé', Formatters.money(paid, currency: cur), false),
                  if (sale.creditAmount > 0)
                    ('Reste à payer', Formatters.money(sale.creditAmount, currency: cur), false),
                ]),
              ),
            ],
          ),
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
    final owes = customer.balance > 0;
    doc.addPage(
      pw.MultiPage(
        pageFormat: _a4,
        footer: (ctx) => _pageFooter(ctx, issuer),
        build: (_) => [
          _a4Header(
            issuer,
            title: 'RELEVÉ DE COMPTE',
            meta: [('Édité le', Formatters.date(issuedAt ?? DateTime.now()))],
          ),
          pw.SizedBox(height: 16),
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
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: owes ? const PdfColor.fromInt(0xFFFFF4E0) : _tint,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _label(owes ? 'Montant dû' : 'Solde'),
                      pw.Text(
                        clean(Formatters.money(customer.balance, currency: cur)),
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: owes ? _credit : _paid,
                        ),
                      ),
                      if (customer.creditLimit != null)
                        pw.Text(
                          clean('Plafond de crédit : ${Formatters.money(customer.creditLimit!, currency: cur)}'),
                          style: const pw.TextStyle(fontSize: 8.5, color: _muted),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          if (transactions.isEmpty)
            pw.Text('Aucune opération.', style: const pw.TextStyle(color: _muted))
          else
            _table(
              headers: const ['Date', 'Opération', 'Montant', 'Solde'],
              flex: const [2.4, 4.6, 2.2, 2.2],
              leftAligned: const {0, 1},
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
            clean('« + » : achat à crédit (la dette augmente) · « - » : règlement ou correction (la dette diminue).'),
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ],
      ),
    );
    return doc.save();
  }

  // ----------------------------------------------------------------- Rapport

  /// Rapport d'activité A4 (indicateurs, trésorerie, évolution, meilleures
  /// ventes), valeurs telles que renvoyées par les RPC d'analyse.
  static Future<Uint8List> report(ReportData data, DocumentIssuer issuer, String periodLabel, {DateTime? issuedAt}) {
    final cur = issuer.currency;
    String money(int v) => Formatters.money(v, currency: cur);
    String delta(num now, num before) {
      final d = ReportData.delta(now, before);
      return d == null ? '—' : Formatters.percentDelta(d);
    }

    final s = data.summary;
    final prev = data.previous;
    final doc = _document('Rapport d’activité', issuer);
    final granularity = data.period.granularity;
    String periodOf(DateTime d) => switch (granularity) {
      'day' => Formatters.date(d),
      'week' => 'Sem. du ${Formatters.date(d)}',
      _ => Formatters.monthYear(d),
    };

    pw.Widget kpi(String label, String value, {PdfColor? color}) => pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: const pw.BoxDecoration(color: _tint, borderRadius: pw.BorderRadius.all(pw.Radius.circular(8))),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _label(label),
            pw.Text(
              clean(value),
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: color ?? _brandDark),
            ),
          ],
        ),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: _a4,
        footer: (ctx) => _pageFooter(ctx, issuer),
        build: (_) => [
          _a4Header(
            issuer,
            title: 'RAPPORT D’ACTIVITÉ',
            meta: [('Période', periodLabel), ('Édité le', Formatters.date(issuedAt ?? DateTime.now()))],
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              kpi('Chiffre d’affaires', money(s.revenue)),
              pw.SizedBox(width: 8),
              kpi('Ventes', '${s.salesCount}'),
              pw.SizedBox(width: 8),
              if (s.estimatedMargin != null)
                kpi('Marge estimée', money(s.estimatedMargin!), color: _paid)
              else
                kpi('Panier moyen', money(s.averageBasket)),
              pw.SizedBox(width: 8),
              kpi('Flux net', money(s.netCashFlow), color: s.netCashFlow >= 0 ? _paid : _cancel),
            ],
          ),
          pw.SizedBox(height: 14),
          _table(
            headers: const ['Indicateur', 'Période', 'Précédente', 'Évolution'],
            flex: const [4, 3, 3, 2],
            rows: [
              ['Chiffre d’affaires', money(s.revenue), money(prev.revenue), delta(s.revenue, prev.revenue)],
              ['Nombre de ventes', '${s.salesCount}', '${prev.salesCount}', delta(s.salesCount, prev.salesCount)],
              [
                'Panier moyen',
                money(s.averageBasket),
                money(prev.averageBasket),
                delta(s.averageBasket, prev.averageBasket),
              ],
              if (s.estimatedMargin != null)
                [
                  'Marge estimée',
                  money(s.estimatedMargin!),
                  prev.estimatedMargin == null ? '—' : money(prev.estimatedMargin!),
                  prev.estimatedMargin == null ? '—' : delta(s.estimatedMargin!, prev.estimatedMargin!),
                ],
              ['Remises accordées', money(s.discounts), money(prev.discounts), delta(s.discounts, prev.discounts)],
              ['Vendu à crédit', money(s.creditGiven), money(prev.creditGiven), delta(s.creditGiven, prev.creditGiven)],
              ['Ventes annulées', '${s.cancelledCount}', '${prev.cancelledCount}', ''],
              ['Clients actifs', '${s.activeCustomers}', '${prev.activeCustomers}', ''],
            ],
          ),
          pw.SizedBox(height: 14),
          _table(
            headers: const ['Trésorerie', 'Montant'],
            flex: const [8, 4],
            rows: [
              ['Encaissements', money(s.cashIn)],
              ['Décaissements (fournisseurs, remboursements)', money(-s.cashOut)],
              ['Dépenses', money(-s.expenses)],
              ['Flux net', money(s.netCashFlow)],
              ['Créances clients (à date)', money(s.customersDebt)],
            ],
          ),
          if (data.topProducts.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _table(
              headers: [
                'Meilleures ventes',
                'Quantité',
                'CA',
                if (data.topProducts.any((t) => t.estimatedMargin != null)) 'Marge',
              ],
              flex: [6, 2, 3, if (data.topProducts.any((t) => t.estimatedMargin != null)) 3],
              rows: [
                for (final t in data.topProducts)
                  [
                    t.name,
                    Formatters.quantity(t.quantity),
                    money(t.revenue),
                    if (data.topProducts.any((x) => x.estimatedMargin != null))
                      t.estimatedMargin == null ? '—' : money(t.estimatedMargin!),
                  ],
              ],
            ),
          ],
          if (data.series.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _table(
              headers: ['Évolution', 'Ventes', 'CA', if (data.hasMargin) 'Marge'],
              flex: [4, 2, 3, if (data.hasMargin) 3],
              rows: [
                for (final p in data.series)
                  [
                    periodOf(p.period),
                    '${p.salesCount}',
                    money(p.revenue),
                    if (data.hasMargin) p.estimatedMargin == null ? '—' : money(p.estimatedMargin!),
                  ],
              ],
            ),
          ],
          pw.SizedBox(height: 10),
          pw.Text(
            clean(
              'Montants calculés par le serveur JËND PRO à partir des ventes, paiements et dépenses enregistrés. '
              'La marge est une estimation fondée sur le coût moyen des produits au moment de la vente.',
            ),
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ],
      ),
    );
    return doc.save();
  }

  // ---------------------------------------------------- Messages de partage

  /// Reçu texte pour WhatsApp / SMS (mise en forme WhatsApp : *gras*).
  static String receiptText(Sale sale, DocumentIssuer issuer) {
    final cur = issuer.currency;
    final b = StringBuffer()
      ..writeln('*${issuer.name}*')
      ..writeln('🧾 Reçu ${sale.number} · ${Formatters.dateTime(sale.soldAt)}');
    if (sale.cancelled) b.writeln('❌ *VENTE ANNULÉE*');
    b.writeln('──────────────');
    for (final l in sale.lines) {
      b.writeln(
        '• ${l.productName} : ${Formatters.quantity(l.quantity)} x ${Formatters.money(l.unitPrice, currency: cur)}'
        ' = ${Formatters.money(l.lineTotal, currency: cur)}',
      );
    }
    b.writeln('──────────────');
    if (sale.discount > 0) b.writeln('Remise : -${Formatters.money(sale.discount, currency: cur)}');
    b.writeln('*Total : ${Formatters.money(sale.total, currency: cur)}*');
    for (final pay in sale.payments.where((x) => x.incoming)) {
      b.writeln('✅ ${pay.method.label} : ${Formatters.money(pay.amount, currency: cur)}');
    }
    if (sale.creditAmount > 0) b.writeln('⏳ Reste à payer : ${Formatters.money(sale.creditAmount, currency: cur)}');
    b
      ..writeln()
      ..writeln('Merci de votre visite ! 🙏');
    if (issuer.phone != null) b.writeln('📞 ${Formatters.phone(issuer.phone!)}');
    return b.toString().trimRight();
  }

  /// Objet et message accompagnant un PDF partagé (e-mail, WhatsApp…).
  static (String subject, String body) shareMessage({
    required String document,
    required String reference,
    required DocumentIssuer issuer,
    String? recipient,
    int? amount,
    String amountPhrase = ' d’un montant de ',
  }) {
    final hello = recipient == null ? 'Bonjour,' : 'Bonjour ${recipient.split(' ').first},';
    final amountText = amount == null ? '' : '$amountPhrase${Formatters.money(amount, currency: issuer.currency)}';
    final contact = [
      issuer.phone == null ? null : Formatters.phone(issuer.phone!),
      issuer.email,
    ].whereType<String>().join(' · ');
    return (
      '$document $reference — ${issuer.name}',
      '$hello\n\nVeuillez trouver ci-joint votre ${document.toLowerCase()} $reference$amountText.\n\n'
          'Merci pour votre confiance.\n${issuer.name}${contact.isEmpty ? '' : '\n$contact'}',
    );
  }

  // --------------------------------------------------------------- Communs

  static pw.Document _document(String title, DocumentIssuer issuer) =>
      pw.Document(title: clean(title), author: clean(issuer.name), creator: 'JËND PRO', theme: style.theme);

  /// Statut affiché en tampon (facture) ou en encadré (ticket).
  static ({String label, String ticketLabel, String? detail, PdfColor color}) _statusOf(Sale sale, String cur) {
    if (sale.cancelled) return (label: 'ANNULÉE', ticketLabel: 'VENTE ANNULÉE', detail: null, color: _cancel);
    if (sale.creditAmount > 0) {
      final rest = 'Reste ${Formatters.money(sale.creditAmount, currency: cur)}';
      return (label: 'À CRÉDIT', ticketLabel: 'À CRÉDIT', detail: rest, color: _credit);
    }
    return (label: 'PAYÉE', ticketLabel: 'PAYÉ', detail: null, color: _paid);
  }

  static pw.Widget _stamp(({String label, String ticketLabel, String? detail, PdfColor color}) s) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: s.color, width: 2),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
    ),
    child: pw.Column(
      children: [
        pw.Text(
          clean(s.label),
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: s.color, letterSpacing: 1.5),
        ),
        if (s.detail != null)
          pw.Text(
            clean(s.detail!),
            style: pw.TextStyle(fontSize: 9, color: s.color, fontWeight: pw.FontWeight.bold),
          ),
      ],
    ),
  );

  /// Logo du commerce, ou ses initiales sur pastille si aucun logo.
  static pw.Widget _identity(DocumentIssuer issuer, {required double size, required bool onDark}) {
    if (issuer.logo != null) {
      return pw.Container(
        width: size,
        height: size,
        padding: onDark ? pw.EdgeInsets.all(size * 0.08) : null,
        decoration: onDark
            ? pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(size * 0.22)),
              )
            : null,
        child: pw.Image(issuer.logo!, fit: pw.BoxFit.contain),
      );
    }
    return pw.Container(
      width: size,
      height: size,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: onDark ? PdfColors.white : PdfColors.black,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(size * 0.22)),
      ),
      child: pw.Text(
        clean(initials(issuer.name)),
        style: pw.TextStyle(
          fontSize: size * 0.42,
          fontWeight: pw.FontWeight.bold,
          color: onDark ? _brand : PdfColors.white,
        ),
      ),
    );
  }

  /// Initiales d'un nom de commerce (« Boutique Ndèye » → « BN »).
  static String initials(String name) {
    const skip = {'de', 'du', 'des', 'la', 'le', 'les', 'et', '&', 'chez'};
    final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty && !skip.contains(w.toLowerCase())).toList();
    if (words.isEmpty) return 'J';
    return words.take(2).map((w) => String.fromCharCode(w.runes.first).toUpperCase()).join();
  }

  static pw.Widget _a4Header(DocumentIssuer issuer, {required String title, required List<(String, String)> meta}) {
    final contacts = [
      if (issuer.legalName != null && issuer.legalName != issuer.name) issuer.legalName,
      issuer.location,
      [issuer.phone == null ? null : Formatters.phone(issuer.phone!), issuer.email].whereType<String>().join(' · '),
    ].whereType<String>().where((l) => l.isNotEmpty).toList();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: const pw.BoxDecoration(
            gradient: pw.LinearGradient(colors: [_brand, _brandDark]),
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              _identity(issuer, size: 54, onDark: true),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      clean(issuer.name),
                      style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                    ),
                    pw.SizedBox(height: 3),
                    for (final l in contacts)
                      pw.Text(clean(l), style: const pw.TextStyle(fontSize: 8.5, color: PdfColor(1, 1, 1, 0.78))),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    clean(title),
                    style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _mint, letterSpacing: 1.2),
                  ),
                  pw.SizedBox(height: 4),
                  for (final (k, v) in meta)
                    pw.Text(clean('$k : $v'), style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.white)),
                ],
              ),
            ],
          ),
        ),
        if (issuer.legalLine != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 5, left: 4),
            child: pw.Text(clean(issuer.legalLine!), style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ),
      ],
    );
  }

  static pw.Widget _label(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Text(
      clean(text.toUpperCase()),
      style: pw.TextStyle(fontSize: 7.5, color: _muted, fontWeight: pw.FontWeight.bold, letterSpacing: 0.8),
    ),
  );

  static pw.Widget _box(String title, List<String> lines) => pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _line),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _label(title),
        for (final (i, l) in lines.indexed)
          pw.Text(
            clean(l),
            style: pw.TextStyle(fontSize: i == 0 ? 11 : 9.5, fontWeight: i == 0 ? pw.FontWeight.bold : null),
          ),
      ],
    ),
  );

  static pw.Widget _table({
    required List<String> headers,
    required List<double> flex,
    required List<List<String>> rows,
    Set<int> leftAligned = const {0},
  }) {
    pw.Widget cell(String text, int col, {bool header = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      child: pw.Text(
        clean(text),
        textAlign: leftAligned.contains(col) ? pw.TextAlign.left : pw.TextAlign.right,
        style: pw.TextStyle(
          fontSize: header ? 8.5 : 9.5,
          fontWeight: header ? pw.FontWeight.bold : null,
          color: header ? PdfColors.white : PdfColors.black,
          letterSpacing: header ? 0.4 : null,
        ),
      ),
    );
    return pw.Table(
      columnWidths: {for (final (i, f) in flex.indexed) i: pw.FlexColumnWidth(f)},
      border: const pw.TableBorder(bottom: pw.BorderSide(color: _line, width: 0.8)),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: _brand,
            borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(6)),
          ),
          children: [for (final (i, h) in headers.indexed) cell(h, i, header: true)],
        ),
        for (final (r, row) in rows.indexed)
          pw.TableRow(
            decoration: pw.BoxDecoration(color: r.isOdd ? _zebra : PdfColors.white),
            children: [for (final (i, c) in row.indexed) cell(c, i)],
          ),
      ],
    );
  }

  /// Encadré des totaux ; la ligne principale est mise en valeur.
  static pw.Widget _totalsCard(List<(String, String, bool)> rows) => pw.Container(
    decoration: pw.BoxDecoration(
      color: _tint,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      border: pw.Border.all(color: _line),
    ),
    child: pw.Column(
      children: [
        for (final (label, value, main) in rows)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            decoration: main
                ? const pw.BoxDecoration(color: _brand, borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)))
                : null,
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    clean(main ? label.toUpperCase() : label),
                    style: pw.TextStyle(
                      fontSize: main ? 10 : 9.5,
                      fontWeight: main ? pw.FontWeight.bold : null,
                      color: main ? PdfColors.white : _muted,
                      letterSpacing: main ? 1 : null,
                    ),
                  ),
                ),
                pw.Text(
                  clean(value),
                  style: pw.TextStyle(
                    fontSize: main ? 14 : 10,
                    fontWeight: pw.FontWeight.bold,
                    color: main ? PdfColors.white : _brandDark,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  static pw.Widget _pageFooter(pw.Context ctx, DocumentIssuer issuer) {
    final contact = [
      issuer.phone == null ? null : Formatters.phone(issuer.phone!),
      issuer.email,
    ].whereType<String>().join(' · ');
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 14),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _line, width: 0.8)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  clean('Merci pour votre confiance — ${issuer.name}'),
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _brand),
                ),
                if (contact.isNotEmpty) pw.Text(clean(contact), style: const pw.TextStyle(fontSize: 8, color: _muted)),
              ],
            ),
          ),
          if (style.brandMark != null) ...[pw.Image(style.brandMark!, width: 11, height: 11), pw.SizedBox(width: 4)],
          pw.Text(
            clean('$footer  ·  Page ${ctx.pageNumber}/${ctx.pagesCount}'),
            style: const pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
        ],
      ),
    );
  }

  /// Équivalents Latin-1 des signes typographiques (polices standard PDF).
  static const _fallbacks = {
    '’': "'",
    '‘': "'",
    '‚': ',',
    '“': '"',
    '”': '"',
    '„': '"',
    '–': '-',
    '—': '-',
    '−': '-',
    '…': '...',
    '•': '·',
    '€': 'EUR',
    'œ': 'oe',
    'Œ': 'OE',
    '™': 'TM',
  };

  /// Rend un texte imprimable par la police en cours :
  /// - Roboto (Unicode) : tout est gardé sauf les émojis ; l'espace fine des
  ///   milliers devient insécable ;
  /// - polices standard (Latin-1) : signes typographiques remplacés par des
  ///   équivalents simples, autres caractères supprimés.
  static String clean(String input) {
    final unicode = style.unicode;
    final out = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      if (rune == 0x202F || rune == 0x2009) {
        out.write(unicode ? ' ' : ' ');
      } else if (rune == 0x00A0) {
        out.write(unicode ? ch : ' ');
      } else if (unicode) {
        final emoji = rune > 0xFFFF || (rune >= 0x2600 && rune <= 0x27BF) || rune == 0xFE0F || rune == 0x200D;
        if (!emoji && (rune >= 0x20 || rune == 0x0A)) out.write(ch);
      } else if (_fallbacks.containsKey(ch)) {
        out.write(_fallbacks[ch]);
      } else if ((rune >= 0x20 && rune < 0x7F) || (rune > 0xA0 && rune <= 0xFF) || rune == 0x0A) {
        out.write(ch);
      }
    }
    return out.toString();
  }
}
