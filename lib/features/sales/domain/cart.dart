import '../../../core/domain/payment_method.dart';
import 'sale_models.dart';

/// Ligne de panier. Les montants sont des **estimations** : le serveur
/// recalcule tout à partir du prix catalogue (business-rules §4.1).
class CartLine {
  const CartLine({required this.product, required this.quantity, this.discount = 0});

  final SellableProduct product;
  final num quantity;

  /// Remise de ligne en FCFA (`sales.discount`).
  final int discount;

  /// `round(quantité × prix) − remise`, arrondi au franc (demi vers le haut).
  int get gross => (quantity * product.salePrice).round();

  int get total => gross - discount;

  CartLine copyWith({num? quantity, int? discount}) =>
      CartLine(product: product, quantity: quantity ?? this.quantity, discount: discount ?? this.discount);

  Map<String, dynamic> toJson() => {
    'product_id': product.id,
    'quantity': quantity,
    if (discount > 0) 'discount_amount': discount,
  };
}

/// Panier + paiement en cours de saisie. Immuable : chaque action renvoie
/// un nouveau panier (facile à tester, aucune mutation partagée).
class Cart {
  const Cart({this.lines = const [], this.globalDiscount = 0, this.customer, this.payments = const [], this.notes});

  final List<CartLine> lines;
  final int globalDiscount;
  final SaleCustomer? customer;

  /// Paiements **autres** que le paiement principal saisi à l'écran
  /// d'encaissement (paiements multiples).
  final List<PaymentEntry> payments;
  final String? notes;

  bool get isEmpty => lines.isEmpty;

  num get itemCount => lines.fold<num>(0, (s, l) => s + (l.product.allowsFractional ? 1 : l.quantity));

  int get subtotal => lines.fold(0, (s, l) => s + l.total);

  int get lineDiscounts => lines.fold(0, (s, l) => s + l.discount);

  int get total => (subtotal - globalDiscount).clamp(0, subtotal);

  bool get hasDiscount => globalDiscount > 0 || lineDiscounts > 0;

  num quantityOf(String productId) {
    for (final l in lines) {
      if (l.product.id == productId) return l.quantity;
    }
    return 0;
  }

  /// Ajoute (ou incrémente) un produit. Un même produit n'apparaît qu'une
  /// fois (`DUPLICATE_PRODUCT` côté serveur sinon).
  Cart add(SellableProduct product, {num quantity = 1}) {
    final index = lines.indexWhere((l) => l.product.id == product.id);
    if (index == -1) {
      return _with(
        lines: [
          ...lines,
          CartLine(product: product, quantity: quantity),
        ],
      );
    }
    final updated = [...lines];
    updated[index] = lines[index].copyWith(quantity: lines[index].quantity + quantity);
    return _with(lines: updated);
  }

  /// Fixe la quantité (≤ 0 retire la ligne). La remise de ligne est bornée
  /// au nouveau montant.
  Cart setQuantity(String productId, num quantity) {
    if (quantity <= 0) return remove(productId);
    return _with(
      lines: [
        for (final l in lines)
          if (l.product.id == productId) _boundDiscount(l.copyWith(quantity: quantity)) else l,
      ],
    );
  }

  Cart setLineDiscount(String productId, int discount) => _with(
    lines: [
      for (final l in lines)
        if (l.product.id == productId) _boundDiscount(l.copyWith(discount: discount)) else l,
    ],
  );

  Cart remove(String productId) => _with(lines: lines.where((l) => l.product.id != productId).toList());

  Cart setGlobalDiscount(int discount) => _with(globalDiscount: discount.clamp(0, subtotal));

  Cart setCustomer(SaleCustomer? customer) =>
      Cart(lines: lines, globalDiscount: globalDiscount, customer: customer, payments: payments, notes: notes);

  Cart setNotes(String? notes) =>
      Cart(lines: lines, globalDiscount: globalDiscount, customer: customer, payments: payments, notes: notes);

  Cart _with({List<CartLine>? lines, int? globalDiscount}) {
    final next = Cart(
      lines: lines ?? this.lines,
      globalDiscount: globalDiscount ?? this.globalDiscount,
      customer: customer,
      payments: payments,
      notes: notes,
    );
    // Après modification des lignes, la remise globale reste ≤ sous-total.
    return next.globalDiscount > next.subtotal
        ? Cart(lines: next.lines, globalDiscount: next.subtotal, customer: customer, payments: payments, notes: notes)
        : next;
  }

  static CartLine _boundDiscount(CartLine l) => l.discount > l.gross ? l.copyWith(discount: l.gross) : l;
}

/// Calcul d'encaissement à partir de ce que donne le client.
///
/// Règle backend : on n'envoie **que le montant dû**. Si le client donne
/// 5 000 pour 4 250 en espèces, on envoie 4 250 et on rend 750 à l'écran.
class Settlement {
  const Settlement._({required this.total, required this.payments, required this.change, required this.credit});

  /// [tendered] : montants remis par le client, dans l'ordre de saisie.
  /// Seules les espèces peuvent dépasser le dû (monnaie rendue) ; les
  /// paiements électroniques sont plafonnés au restant.
  factory Settlement.compute({required int total, required List<PaymentEntry> tendered}) {
    var remaining = total;
    var change = 0;
    final sent = <PaymentEntry>[];
    for (final t in tendered) {
      if (t.amount <= 0) continue;
      if (remaining <= 0) {
        if (t.method == PaymentMethod.cash) change += t.amount;
        continue;
      }
      final applied = t.amount > remaining ? remaining : t.amount;
      if (t.method == PaymentMethod.cash && t.amount > remaining) change += t.amount - remaining;
      sent.add(PaymentEntry(method: t.method, amount: applied, externalReference: t.externalReference));
      remaining -= applied;
    }
    return Settlement._(total: total, payments: sent, change: change, credit: remaining);
  }

  final int total;

  /// Paiements à envoyer à `create_sale` (Σ ≤ total).
  final List<PaymentEntry> payments;

  /// Monnaie à rendre au client (espèces).
  final int change;

  /// Reste dû, porté au compte client (vente à crédit).
  final int credit;

  int get paid => total - credit;

  bool get isCredit => credit > 0;
}
