import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/domain/payment_method.dart';
import 'package:jend_pro_mobile/features/sales/domain/cart.dart';
import 'package:jend_pro_mobile/features/sales/domain/sale_models.dart';

const _riz = SellableProduct(
  id: 'riz',
  name: 'Riz',
  unit: 'kg',
  salePrice: 650,
  trackStock: true,
  allowsFractional: true,
);
const _huile = SellableProduct(
  id: 'huile',
  name: 'Huile 5 L',
  unit: 'bidon',
  salePrice: 6500,
  trackStock: true,
  allowsFractional: false,
);

PaymentEntry _cash(int a) => PaymentEntry(method: PaymentMethod.cash, amount: a);
PaymentEntry _wave(int a) => PaymentEntry(method: PaymentMethod.wave, amount: a);

void main() {
  group('Cart', () {
    test('ajouter deux fois le même produit incrémente une seule ligne', () {
      final cart = const Cart().add(_huile).add(_huile).add(_riz, quantity: 2.5);
      expect(cart.lines, hasLength(2));
      expect(cart.quantityOf('huile'), 2);
      expect(cart.subtotal, 2 * 6500 + 1625, reason: '2,5 × 650 = 1 625');
    });

    test('arrondi au franc, demi vers le haut (comme le serveur)', () {
      const p = SellableProduct(
        id: 'x',
        name: 'x',
        unit: 'kg',
        salePrice: 333,
        trackStock: false,
        allowsFractional: true,
      );
      expect(const Cart().add(p, quantity: 1.5).subtotal, 500, reason: '499,5 → 500');
    });

    test('remises bornées au montant concerné', () {
      var cart = const Cart().add(_huile).setLineDiscount('huile', 9999);
      expect(cart.lines.single.discount, 6500);
      cart = const Cart().add(_huile, quantity: 2).setLineDiscount('huile', 1000).setQuantity('huile', 1);
      expect(cart.lines.single.discount, 1000);
      cart = const Cart().add(_huile).setGlobalDiscount(10000);
      expect(cart.globalDiscount, 6500);
      expect(cart.total, 0);
    });

    test('réduire le panier réajuste la remise globale', () {
      final cart = const Cart().add(_huile, quantity: 2).setGlobalDiscount(10000).setQuantity('huile', 1);
      expect(cart.globalDiscount, 6500);
    });

    test('quantité 0 retire la ligne', () {
      expect(const Cart().add(_huile).setQuantity('huile', 0).isEmpty, isTrue);
    });

    test('charge utile create_sale : jamais de prix envoyé', () {
      final json = const Cart().add(_huile).setLineDiscount('huile', 200).lines.single.toJson();
      expect(json, {'product_id': 'huile', 'quantity': 1, 'discount_amount': 200});
    });
  });

  group('Settlement', () {
    test('espèces : on envoie le dû, on rend la monnaie', () {
      final s = Settlement.compute(total: 4250, tendered: [_cash(5000)]);
      expect(s.payments.single.amount, 4250);
      expect(s.change, 750);
      expect(s.credit, 0);
    });

    test('paiements multiples : espèces + Wave', () {
      final s = Settlement.compute(total: 15000, tendered: [_cash(5000), _wave(10000)]);
      expect(s.payments.map((p) => p.amount), [5000, 10000]);
      expect(s.change, 0);
    });

    test('un paiement électronique n’est jamais plafonné au-delà du dû et ne rend pas de monnaie', () {
      final s = Settlement.compute(total: 4000, tendered: [_wave(5000)]);
      expect(s.payments.single.amount, 4000);
      expect(s.change, 0);
    });

    test('reste dû = crédit', () {
      final s = Settlement.compute(total: 26000, tendered: [_wave(20000)]);
      expect(s.credit, 6000);
      expect(s.isCredit, isTrue);
      expect(s.paid, 20000);
    });

    test('tout à crédit : aucun paiement envoyé', () {
      final s = Settlement.compute(total: 9600, tendered: const []);
      expect(s.payments, isEmpty);
      expect(s.credit, 9600);
    });

    test('Σ paiements envoyés ≤ total (sinon PAYMENT_EXCEEDS_TOTAL)', () {
      final s = Settlement.compute(total: 1000, tendered: [_wave(800), _cash(2000), _cash(500)]);
      expect(s.payments.fold<int>(0, (a, p) => a + p.amount), 1000);
      expect(s.change, 1800 + 500, reason: '2 000 − 200 dû, puis 500 en trop');
    });
  });

  test('client : crédit disponible', () {
    expect(const SaleCustomer(id: 'c', name: 'Fatou', balance: 3000, creditLimit: 10000).creditAvailable, 7000);
    expect(const SaleCustomer(id: 'c', name: 'Fatou', creditLimit: 0).creditAllowed, isFalse);
    expect(
      const SaleCustomer(id: 'c', name: 'Fatou', balance: 5000).creditAvailable,
      isNull,
      reason: 'illimité',
    );
  });
}
