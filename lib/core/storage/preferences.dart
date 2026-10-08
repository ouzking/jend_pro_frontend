import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Préférences locales (non sensibles : entreprise active, choix d'affichage).
/// Initialisé dans `main()` puis injecté par surcharge.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider doit être surchargé au démarrage.'),
);
