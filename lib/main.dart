import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/env.dart';
import 'core/errors/app_failure.dart';
import 'core/storage/preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(const ConfigurationErrorApp());
    return;
  }

  Intl.defaultLocale = 'fr';
  final (_, _, prefs) = await (
    initializeDateFormatting('fr'),
    Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabasePublishableKey),
    SharedPreferences.getInstance(),
  ).wait;

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      // Relance automatique uniquement pour les coupures réseau ; les
      // erreurs métier ou de permission s'affichent immédiatement.
      retry: (count, error) {
        if (count >= 3) return null;
        final failure = AppFailure.from(error);
        return failure.kind == FailureKind.network ? Duration(seconds: 1 << count) : null;
      },
      child: const JendProApp(),
    ),
  );
}
