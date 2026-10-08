import '../errors/app_failure.dart';

/// Exécute un appel Supabase et convertit toute exception en [AppFailure].
Future<T> guardSupabase<T>(Future<T> Function() action) async {
  try {
    return await action();
  } catch (e) {
    throw AppFailure.from(e);
  }
}
