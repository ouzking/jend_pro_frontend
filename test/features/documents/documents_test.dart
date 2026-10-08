import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/domain/payment_method.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/core/storage/preferences.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/customers/domain/customer_models.dart';
import 'package:jend_pro_mobile/features/documents/application/document_providers.dart';
import 'package:jend_pro_mobile/features/documents/data/document_builder.dart';
import 'package:jend_pro_mobile/features/documents/domain/document_issuer.dart';
import 'package:jend_pro_mobile/features/sales/application/pos_providers.dart';
import 'package:jend_pro_mobile/features/sales/domain/sale_models.dart';
import 'package:jend_pro_mobile/features/sales/presentation/sale_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _issuer = DocumentIssuer(
  name: 'Boutique Ndèye',
  address: 'Rue 10 x 13',
  city: 'Dakar',
  phone: '771234567',
  ninea: '0123456 2G3',
);

Sale _sale({int lines = 2, bool credit = false, bool cancelled = false}) => Sale(
  id: 's1',
  number: 'V-000042',
  soldAt: DateTime(2026, 10, 8, 10, 30),
  subtotal: 9000,
  discount: 500,
  total: 8500,
  amountPaid: credit ? 5000 : 8500,
  creditAmount: credit ? 3500 : 0,
  cancelled: cancelled,
  cancelReason: cancelled ? 'Erreur de caisse' : null,
  customerName: credit ? 'Awa Fall' : null,
  customerPhone: credit ? '770000000' : null,
  lines: [
    for (var i = 0; i < lines; i++)
      SaleLine(
        productName: i == 0 ? 'Riz parfumé 5 kg 🍚' : 'Huile Niinal 1 L n°$i',
        quantity: i == 0 ? 2.5 : 1,
        unitPrice: 1800,
        discount: i == 0 ? 100 : 0,
        lineTotal: i == 0 ? 4400 : 1800,
      ),
  ],
  payments: [
    SalePayment(
      method: PaymentMethod.cash,
      amount: credit ? 5000 : 8500,
      incoming: true,
      paidAt: DateTime(2026, 10, 8),
    ),
  ],
);

bool _isPdf(List<int> bytes) => bytes.length > 500 && ascii.decode(bytes.sublist(0, 5)) == '%PDF-';

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  group('DocumentBuilder', () {
    test('nettoyage : espaces insécables, caractères hors Windows-1252', () {
      expect(DocumentBuilder.clean('1 500 F CFA'), '1 500 F CFA');
      expect(DocumentBuilder.clean('Ndèye · JËND – « ok » ’'), 'Ndèye · JËND – « ok » ’');
      expect(DocumentBuilder.clean('Riz 🍚'), 'Riz ');
    });

    test('ticket 58 et 80 mm, y compris long ticket et vente annulée', () async {
      for (final w in TicketWidth.values) {
        expect(_isPdf(await DocumentBuilder.ticket(_sale(), _issuer, width: w)), isTrue);
      }
      expect(_isPdf(await DocumentBuilder.ticket(_sale(lines: 60, credit: true, cancelled: true), _issuer)), isTrue);
    });

    test('facture A4 sur plusieurs pages', () async {
      expect(_isPdf(await DocumentBuilder.invoice(_sale(lines: 80, credit: true), _issuer)), isTrue);
    });

    test('relevé client', () async {
      final customer = Customer(
        id: 'c1',
        name: 'Awa Fall',
        balance: 3500,
        archived: false,
        createdAt: DateTime(2026),
        phone: '770000000',
      );
      final tx = [
        CustomerTransaction(
          id: 't1',
          type: CustomerTransactionType.creditSale,
          amount: 3500,
          balanceAfter: 3500,
          createdAt: DateTime(2026, 10, 8),
          saleNumber: 'V-000042',
        ),
      ];
      expect(_isPdf(await DocumentBuilder.statement(customer, tx, _issuer)), isTrue);
      expect(_isPdf(await DocumentBuilder.statement(customer, const [], _issuer)), isTrue);
    });

    test('reçu texte WhatsApp : valeurs figées, reste à payer', () {
      final text = DocumentBuilder.receiptText(_sale(credit: true), _issuer);
      expect(text, startsWith('*Boutique Ndèye*'));
      expect(text, contains('Reçu V-000042'));
      expect(text, contains('*Total : 8'));
      expect(text, contains('Reste à payer : 3'));
    });

    test('en-tête : seules les mentions renseignées', () {
      expect(_issuer.location, 'Rue 10 x 13, Dakar');
      expect(_issuer.legalLine, 'NINEA 0123456 2G3');
      expect(const DocumentIssuer(name: 'X').legalLine, isNull);
      expect(documentFilename('Recu', 'V-000042'), 'Recu-V-000042.pdf');
      expect(documentFilename('Releve', 'Awa Fall'), 'Releve-Awa-Fall.pdf');
    });
  });

  testWidgets('reçu : boutons et feuille de partage, largeur mémorisée', (t) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          permissionsProvider.overrideWithValue(const PermissionSet({Permission.salesRead})),
          activeBusinessProvider.overrideWithValue(null),
          saleDetailProvider('s1').overrideWith((ref) async => _sale(credit: true)),
          documentIssuerProvider.overrideWith((ref) async => _issuer),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SaleDetailScreen(saleId: 's1'),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Imprimer'), findsOneWidget);
    await t.tap(find.text('Partager'));
    await t.pumpAndSettle();
    expect(find.text('Reçu texte envoyé à Awa Fall'), findsOneWidget);
    expect(find.text('Facture A4 (PDF)'), findsOneWidget);
    expect(find.text('Format caisse 58 mm'), findsOneWidget);
    await t.tap(find.text('80 mm'));
    await t.pumpAndSettle();
    expect(find.text('Format caisse 80 mm'), findsOneWidget);
    expect(prefs.getString('ticket_width'), 'mm80');
  });
}
