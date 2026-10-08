import 'package:pdf/widgets.dart' as pw;

import '../../business/domain/business_profile.dart';

/// Émetteur des documents (en-tête des reçus, factures et relevés), tiré de
/// la fiche entreprise. Aucune mention légale n'est inventée : seuls les
/// champs renseignés dans `businesses` apparaissent.
class DocumentIssuer {
  const DocumentIssuer({
    required this.name,
    this.legalName,
    this.address,
    this.city,
    this.phone,
    this.email,
    this.ninea,
    this.rccm,
    this.currency = 'XOF',
    this.logo,
  });

  factory DocumentIssuer.fromProfile(BusinessProfile p, {String currency = 'XOF', pw.ImageProvider? logo}) =>
      DocumentIssuer(
        name: p.name,
        legalName: p.legalName,
        address: p.address,
        city: p.city,
        phone: p.phone,
        email: p.email,
        ninea: p.ninea,
        rccm: p.rccm,
        currency: currency,
        logo: logo,
      );

  final String name;
  final String? legalName;
  final String? address;
  final String? city;
  final String? phone;
  final String? email;
  final String? ninea;
  final String? rccm;
  final String currency;
  final pw.ImageProvider? logo;

  /// Adresse sur une ligne (« Rue 10, Dakar »).
  String? get location {
    final parts = [address, city].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Mentions légales disponibles (« NINEA … · RCCM … »).
  String? get legalLine {
    final parts = [
      if (ninea?.trim().isNotEmpty ?? false) 'NINEA ${ninea!.trim()}',
      if (rccm?.trim().isNotEmpty ?? false) 'RCCM ${rccm!.trim()}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// Largeur du papier des tickets thermiques.
enum TicketWidth {
  mm58('58 mm'),
  mm80('80 mm');

  const TicketWidth(this.label);

  final String label;
}
