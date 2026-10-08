import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Point d'accès unique au client Supabase. Surchargé dans les tests.
final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);
