import '../../../core/formatting/formatters.dart';
import '../../../core/spreadsheet/xlsx.dart';
import '../../customers/domain/customer_models.dart';
import '../../products/domain/catalog_models.dart';
import '../../reports/domain/report_models.dart';
import '../../sales/domain/sale_models.dart';

/// Feuilles Excel des exports (valeurs telles que renvoyées par le serveur).
abstract final class ExportSheets {
  /// En-têtes du catalogue ; aussi reconnus à l'import.
  static const productHeaders = [
    'Nom',
    'Prix de vente',
    'Unité',
    'Catégorie',
    'Code-barres',
    'Référence',
    'Coût d’achat',
    'Stock',
    'Seuil d’alerte',
  ];

  static XlsxSheet products(List<Product> products, {required bool withCost}) => XlsxSheet(
    name: 'Catalogue',
    headers: [
      for (final h in productHeaders)
        if (withCost || h != 'Coût d’achat') h,
      'Statut',
    ],
    rows: [
      for (final p in products)
        [
          p.name,
          p.salePrice,
          p.unit,
          p.categoryName,
          p.barcode,
          p.sku,
          if (withCost) p.costPrice,
          p.trackStock ? p.stockQuantity : null,
          p.trackStock ? p.minStockLevel : null,
          p.archived ? 'Archivé' : 'Actif',
        ],
    ],
  );

  static XlsxSheet customers(List<Customer> customers) => XlsxSheet(
    name: 'Clients',
    headers: const ['Nom', 'Téléphone', 'E-mail', 'Adresse', 'Doit', 'Plafond de crédit', 'Client depuis', 'Statut'],
    rows: [
      for (final c in customers)
        [c.name, c.phone, c.email, c.address, c.balance, c.creditLimit, c.createdAt, c.archived ? 'Archivé' : 'Actif'],
    ],
  );

  /// Ventes (une ligne par vente) + détail des articles.
  static List<XlsxSheet> sales(List<Sale> sales) => [
    XlsxSheet(
      name: 'Ventes',
      headers: const [
        'N°',
        'Date',
        'Client',
        'Articles',
        'Sous-total',
        'Remise',
        'Total',
        'Encaissé',
        'À crédit',
        'Moyens de paiement',
        'Statut',
      ],
      rows: [
        for (final s in sales)
          [
            s.number,
            s.soldAt,
            s.customerName,
            s.itemCount,
            s.subtotal,
            s.discount,
            s.total,
            s.amountPaid,
            s.creditAmount,
            {for (final p in s.payments.where((p) => p.incoming)) p.method.label}.join(', '),
            s.cancelled ? 'Annulée' : 'Validée',
          ],
      ],
    ),
    XlsxSheet(
      name: 'Articles vendus',
      headers: const ['N° de vente', 'Date', 'Article', 'Quantité', 'Prix unitaire', 'Remise', 'Montant', 'Statut'],
      rows: [
        for (final s in sales)
          for (final l in s.lines)
            [
              s.number,
              s.soldAt,
              l.productName,
              l.quantity,
              l.unitPrice,
              l.discount,
              l.lineTotal,
              s.cancelled ? 'Annulée' : 'Validée',
            ],
      ],
    ),
  ];

  static List<XlsxSheet> report(ReportData data, String periodLabel) {
    final s = data.summary;
    final p = data.previous;
    return [
      XlsxSheet(
        name: 'Indicateurs',
        headers: ['Indicateur', 'Période : $periodLabel', 'Période précédente'],
        rows: [
          ['Chiffre d’affaires', s.revenue, p.revenue],
          ['Nombre de ventes', s.salesCount, p.salesCount],
          ['Panier moyen', s.averageBasket, p.averageBasket],
          if (s.estimatedMargin != null) ['Marge estimée', s.estimatedMargin, p.estimatedMargin],
          ['Remises accordées', s.discounts, p.discounts],
          ['Vendu à crédit', s.creditGiven, p.creditGiven],
          ['Ventes annulées', s.cancelledCount, p.cancelledCount],
          ['Clients actifs', s.activeCustomers, p.activeCustomers],
          ['Encaissements', s.cashIn, p.cashIn],
          ['Décaissements', s.cashOut, p.cashOut],
          ['Dépenses', s.expenses, p.expenses],
          ['Flux net', s.netCashFlow, p.netCashFlow],
          ['Créances clients (à date)', s.customersDebt, null],
        ],
      ),
      XlsxSheet(
        name: 'Évolution',
        headers: ['Période', 'Ventes', 'Chiffre d’affaires', if (data.hasMargin) 'Marge estimée'],
        rows: [
          for (final pt in data.series)
            [Formatters.isoDay(pt.period), pt.salesCount, pt.revenue, if (data.hasMargin) pt.estimatedMargin],
        ],
      ),
      XlsxSheet(
        name: 'Meilleures ventes',
        headers: ['Article', 'Quantité', 'Chiffre d’affaires', if (data.hasMargin) 'Marge estimée'],
        rows: [
          for (final t in data.topProducts) [t.name, t.quantity, t.revenue, if (data.hasMargin) t.estimatedMargin],
        ],
      ),
    ];
  }

  /// Modèle d'import du catalogue, avec deux exemples à remplacer.
  static XlsxSheet importTemplate() => const XlsxSheet(
    name: 'Produits à importer',
    headers: productHeaders,
    rows: [
      ['Riz parfumé 25 kg', 14500, 'sac', 'Céréales', '6001234567890', 'RIZ-25', 12000, 20, 5],
      ['Sucre en poudre', 700, 'kg', 'Épicerie', null, null, 550, 50, 10],
    ],
  );
}
