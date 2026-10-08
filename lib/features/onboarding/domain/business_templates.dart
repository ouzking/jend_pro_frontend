import 'package:flutter/material.dart';

/// Type de commerce choisi pendant l'onboarding.
///
/// **Non stocké** : le backend n'a pas de colonne « type ». Le choix sert
/// uniquement à proposer des catégories (créées pour de vrai dans
/// `categories`) et des unités adaptées.
class BusinessTemplate {
  const BusinessTemplate({
    required this.id,
    required this.label,
    required this.icon,
    required this.categories,
    required this.units,
    this.example,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<String> categories;

  /// Unités proposées en priorité (`products.unit`, texte libre ≤ 20).
  final List<String> units;

  /// Exemple de produit affiché en indice dans le formulaire.
  final String? example;

  static const all = [
    BusinessTemplate(
      id: 'grocery',
      label: 'Alimentation',
      icon: Icons.shopping_basket_outlined,
      categories: ['Boissons', 'Épicerie', 'Produits laitiers', 'Hygiène', 'Entretien'],
      units: ['pièce', 'kg', 'litre', 'paquet', 'bouteille'],
      example: 'Riz parfumé 5 kg',
    ),
    BusinessTemplate(
      id: 'restaurant',
      label: 'Restaurant',
      icon: Icons.restaurant_outlined,
      categories: ['Plats', 'Boissons', 'Desserts', 'Petit-déjeuner'],
      units: ['plat', 'portion', 'bouteille', 'verre'],
      example: 'Thiéboudienne',
    ),
    BusinessTemplate(
      id: 'pharmacy',
      label: 'Pharmacie',
      icon: Icons.local_pharmacy_outlined,
      categories: ['Médicaments', 'Parapharmacie', 'Hygiène', 'Bébé'],
      units: ['boîte', 'flacon', 'pièce', 'tube'],
      example: 'Paracétamol 500 mg',
    ),
    BusinessTemplate(
      id: 'wholesale',
      label: 'Grossiste',
      icon: Icons.warehouse_outlined,
      categories: ['Céréales', 'Huiles', 'Boissons', 'Conserves', 'Sucre et farine'],
      units: ['sac', 'carton', 'bidon', 'kg', 'pièce'],
      example: 'Sac de sucre 50 kg',
    ),
    BusinessTemplate(
      id: 'hardware',
      label: 'Quincaillerie',
      icon: Icons.hardware_outlined,
      categories: ['Outillage', 'Plomberie', 'Électricité', 'Peinture', 'Construction'],
      units: ['pièce', 'mètre', 'sac', 'kg', 'litre'],
      example: 'Sac de ciment 50 kg',
    ),
    BusinessTemplate(
      id: 'fashion',
      label: 'Mode et beauté',
      icon: Icons.checkroom_outlined,
      categories: ['Vêtements', 'Chaussures', 'Accessoires', 'Cosmétiques'],
      units: ['pièce', 'paire', 'flacon'],
      example: 'Boubou brodé',
    ),
    BusinessTemplate(
      id: 'electronics',
      label: 'Téléphonie',
      icon: Icons.smartphone_outlined,
      categories: ['Téléphones', 'Accessoires', 'Crédit et cartes', 'Électroménager'],
      units: ['pièce', 'carte'],
      example: 'Chargeur USB-C',
    ),
    BusinessTemplate(
      id: 'other',
      label: 'Autre',
      icon: Icons.storefront_outlined,
      categories: [],
      units: ['pièce', 'kg', 'litre', 'paquet'],
    ),
  ];

  /// Unités pour lesquelles la vente au détail (décimales) est naturelle.
  static const fractionalUnits = {'kg', 'litre', 'mètre', 'g', 'l', 'm'};
}
