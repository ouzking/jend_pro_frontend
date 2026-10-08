/// Jours « locaux de l'entreprise » (backend : `businesses.timezone`).
///
/// Les RPC d'analytics attendent des dates `YYYY-MM-DD` dans le fuseau de
/// l'entreprise. Les fuseaux d'Afrique de l'Ouest sont UTC+0 sans heure
/// d'été : on calcule alors le jour en UTC, indépendamment du réglage du
/// téléphone. Pour un autre fuseau, l'heure locale de l'appareil sert
/// d'approximation.
abstract final class BusinessTime {
  static const _utcZones = {
    'Africa/Dakar',
    'Africa/Abidjan',
    'Africa/Bamako',
    'Africa/Banjul',
    'Africa/Conakry',
    'Africa/Freetown',
    'Africa/Lome',
    'Africa/Nouakchott',
    'Africa/Ouagadougou',
    'Africa/Accra',
    'Africa/Bissau',
    'Africa/Monrovia',
    'UTC',
    'Etc/UTC',
  };

  static DateTime now(String timezone, {DateTime? clock}) {
    final reference = clock ?? DateTime.now();
    return _utcZones.contains(timezone) ? reference.toUtc() : reference.toLocal();
  }

  /// Date du jour (minuit, sans heure) dans le fuseau de l'entreprise.
  static DateTime today(String timezone, {DateTime? clock}) {
    final n = now(timezone, clock: clock);
    return DateTime(n.year, n.month, n.day);
  }
}

/// Jour calendaire sans heure.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
