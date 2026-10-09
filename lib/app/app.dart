import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system/design_system.dart';
import '../features/business/application/workspace_controller.dart';
import '../features/sales/application/pos_providers.dart';
import '../features/settings/application/settings_providers.dart';
import 'router/app_router.dart';

class JendProApp extends ConsumerStatefulWidget {
  const JendProApp({super.key});

  @override
  ConsumerState<JendProApp> createState() => _JendProAppState();
}

class _JendProAppState extends ConsumerState<JendProApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Au retour au premier plan : rôle, statut de membre ou abonnement ont pu
    // changer côté serveur (roles-and-permissions.md / frontend-integration §4).
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.read(workspaceProvider.notifier).refreshContext();
        // Ventes gardées hors ligne : nouvel essai d'envoi.
        ref.read(pendingSalesProvider.notifier).sync();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'JËND PRO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(appRouterProvider),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        // Accessibilité : on respecte la taille de texte du système, avec un
        // plafond qui préserve la lisibilité des montants et des listes.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: media.textScaler.clamp(maxScaleFactor: 1.3)),
          child: child!,
        );
      },
    );
  }
}

/// Affiché quand l'app est lancée sans configuration Supabase.
class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const Scaffold(
        body: JpEmptyState(
          icon: Icons.settings_suggest_outlined,
          tone: JpTone.warning,
          title: 'Configuration manquante',
          message:
              'Lancez l’application avec --dart-define-from-file=env/dev.json '
              '(SUPABASE_URL et SUPABASE_PUBLISHABLE_KEY). Voir le README.',
        ),
      ),
    );
  }
}
