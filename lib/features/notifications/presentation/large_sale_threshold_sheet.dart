import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/input_formatters.dart';
import '../../business/application/workspace_controller.dart';
import '../../business/data/business_repository.dart';
import '../../products/presentation/widgets/product_form_fields.dart';

final largeSaleThresholdProvider = FutureProvider.autoDispose<int?>((ref) {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  if (businessId == null) return Future.value(null);
  return ref.watch(businessRepositoryProvider).fetchLargeSaleThreshold(businessId);
});

/// Réglage `businesses.large_sale_threshold` (`settings.manage`).
Future<void> showLargeSaleThresholdSheet(BuildContext context) => JpOverlays.sheet<void>(
  context,
  title: 'Alerte « vente importante »',
  subtitle:
      'Les gérants et propriétaires sont prévenus dès qu’une vente atteint ce montant. Les alertes de stock faible suivent le seuil minimal de chaque produit.',
  child: const _ThresholdForm(),
);

class _ThresholdForm extends ConsumerStatefulWidget {
  const _ThresholdForm();

  @override
  ConsumerState<_ThresholdForm> createState() => _ThresholdFormState();
}

class _ThresholdFormState extends ConsumerState<_ThresholdForm> {
  final _amount = TextEditingController();
  bool _enabled = false;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _enabled ? AmountInputFormatter.parse(_amount.text) : null;
    if (_enabled && (value == null || value <= 0)) {
      setState(() => _error = 'Indiquez un montant supérieur à 0.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(businessRepositoryProvider)
          .setLargeSaleThreshold(ref.read(activeBusinessProvider)!.businessId, value);
      ref.invalidate(largeSaleThresholdProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      JpOverlays.toast(context, value == null ? 'Alerte désactivée.' : 'Seuil enregistré.', tone: JpTone.success);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(largeSaleThresholdProvider);
    if (!_loaded && current.hasValue) {
      _loaded = true;
      _enabled = current.value != null;
      if (current.value != null) _amount.text = AmountInputFormatter.format(current.value!);
    }
    if (!current.hasValue && !current.hasError) {
      return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormErrorBanner(message: _error ?? (current.hasError ? AppFailure.from(current.error!).message : null)),
        LabeledSwitch(
          title: 'Prévenir des ventes importantes',
          subtitle: 'Notification en direct sur les téléphones de l’équipe',
          value: _enabled,
          onChanged: _saving ? null : (v) => setState(() => _enabled = v),
        ),
        if (_enabled) ...[
          const SizedBox(height: JpSpacing.lg),
          AmountField(label: 'À partir de', controller: _amount, enabled: !_saving),
        ],
        const SizedBox(height: JpSpacing.xl),
        JpButton(label: 'Enregistrer', isLoading: _saving, onPressed: _save),
      ],
    );
  }
}
