/// Fiche détaillée de l'entreprise (`businesses`).
class BusinessProfile {
  const BusinessProfile({
    required this.id,
    required this.name,
    this.legalName,
    this.ninea,
    this.rccm,
    this.phone,
    this.email,
    this.address,
    this.city,
    this.logoPath,
  });

  static const columns = 'id, name, legal_name, ninea, rccm, phone, email, address, city, logo_path';

  factory BusinessProfile.fromRow(Map<String, dynamic> row) => BusinessProfile(
    id: row['id'] as String,
    name: row['name'] as String,
    legalName: row['legal_name'] as String?,
    ninea: row['ninea'] as String?,
    rccm: row['rccm'] as String?,
    phone: row['phone'] as String?,
    email: row['email'] as String?,
    address: row['address'] as String?,
    city: row['city'] as String?,
    logoPath: row['logo_path'] as String?,
  );

  final String id;
  final String name;
  final String? legalName;
  final String? ninea;
  final String? rccm;
  final String? phone;
  final String? email;
  final String? address;
  final String? city;
  final String? logoPath;
}
