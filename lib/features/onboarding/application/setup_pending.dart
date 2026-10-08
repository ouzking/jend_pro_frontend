import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/preferences.dart';
import '../../business/application/workspace_controller.dart';

/// `true` tant que l'assistant de configuration d'un commerce nouvellement
/// créé n'est pas terminé (ou passé). Conservé localement : si l'app est
/// fermée en cours de route, l'assistant reprend au prochain lancement.
final setupPendingProvider = NotifierProvider<SetupPendingNotifier, bool>(SetupPendingNotifier.new);

class SetupPendingNotifier extends Notifier<bool> {
  @override
  bool build() {
    final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    if (businessId == null) return false;
    return ref.read(sharedPreferencesProvider).getBool(setupPendingKey(businessId)) ?? false;
  }

  Future<void> complete() async {
    final businessId = ref.read(activeBusinessProvider)?.businessId;
    if (businessId != null) await ref.read(sharedPreferencesProvider).remove(setupPendingKey(businessId));
    state = false;
  }
}
