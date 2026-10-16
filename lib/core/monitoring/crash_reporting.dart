import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/env.dart';
import '../errors/app_failure.dart';

/// Suivi des plantages (Sentry). Inactif tant que `SENTRY_DSN` n'est pas
/// fourni à la compilation.
///
/// Confidentialité : aucune donnée personnelle (ni e-mail, ni nom, ni
/// capture d'écran) ; seuls l'identifiant technique de l'utilisateur et du
/// commerce sont joints pour regrouper les erreurs.
abstract final class CrashReporting {
  static bool get enabled => Env.sentryDsn.isNotEmpty;

  /// Lance l'app sous la surveillance de Sentry (ou directement si inactif).
  static Future<void> run(FutureOr<void> Function() appRunner) async {
    if (!enabled) {
      await appRunner();
      return;
    }
    await SentryFlutter.init((o) {
      o.dsn = Env.sentryDsn;
      o.environment = Env.supabaseUrl.contains('supabase.co') ? 'production' : 'developpement';
      o.sendDefaultPii = false;
      o.attachScreenshot = false;
      o.tracesSampleRate = 0;
      o.beforeSend = (event, hint) => shouldReport(event.throwable) ? event : null;
    }, appRunner: appRunner);
  }

  /// Les erreurs prévues (réseau coupé, droits, saisie, conflit métier…) sont
  /// déjà expliquées à l'utilisateur : seules les vraies anomalies remontent.
  static bool shouldReport(Object? error) {
    if (error is AppFailure) return error.kind == FailureKind.unknown;
    return true;
  }

  /// Rattache les erreurs suivantes à l'utilisateur et au commerce (ids
  /// techniques uniquement).
  static void identify({String? userId, String? businessId}) {
    if (!enabled) return;
    Sentry.configureScope((scope) {
      scope.setUser(userId == null ? null : SentryUser(id: userId));
      if (businessId == null) {
        scope.removeTag('business_id');
      } else {
        scope.setTag('business_id', businessId);
      }
    });
  }
}
