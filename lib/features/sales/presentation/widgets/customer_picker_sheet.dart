import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/formatting/formatters.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/validation/validators.dart';
import '../../../business/application/workspace_controller.dart';
import '../../data/sales_repository.dart';
import '../../domain/sale_models.dart';

/// Choix (ou création rapide) du client à la caisse.
Future<SaleCustomer?> pickSaleCustomer(BuildContext context) =>
    JpOverlays.sheet<SaleCustomer>(context, title: 'Client', child: const _CustomerPicker(), scrollable: true);

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  Timer? _debounce;
  List<SaleCustomer>? _results;
  Object? _error;
  bool _creating = false;
  bool _saving = false;

  String get _businessId => ref.read(activeBusinessProvider)!.businessId;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    try {
      final results = await ref.read(salesRepositoryProvider).searchCustomers(_businessId, q);
      if (mounted) {
        setState(() {
          _results = results;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _create() async {
    if (Validators.fullName(_name.text) != null) {
      JpOverlays.toast(context, 'Saisissez le nom du client.', tone: JpTone.warning);
      return;
    }
    if (Validators.optionalPhone(_phone.text) case final msg?) {
      JpOverlays.toast(context, msg, tone: JpTone.warning);
      return;
    }
    setState(() => _saving = true);
    try {
      final customer = await ref
          .read(salesRepositoryProvider)
          .createCustomer(_businessId, name: _name.text, phone: Validators.normalizePhone(_phone.text));
      if (mounted) Navigator.of(context).pop(customer);
    } on AppFailure catch (f) {
      if (mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final canCreate = ref.watch(permissionsProvider).can(Permission.customersCreate);

    if (_creating) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          JpTextField(
            label: 'Nom du client',
            hint: 'Ex. Fatou Sow',
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            enabled: !_saving,
          ),
          const SizedBox(height: JpSpacing.lg),
          JpTextField(
            label: 'Téléphone (facultatif)',
            hint: '77 123 45 67',
            controller: _phone,
            keyboardType: TextInputType.phone,
            enabled: !_saving,
          ),
          const SizedBox(height: JpSpacing.xl),
          JpButton(label: 'Créer et choisir', isLoading: _saving, onPressed: _create),
          TextButton(onPressed: () => setState(() => _creating = false), child: const Text('Retour à la recherche')),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JpTextField(
          controller: _search,
          hint: 'Nom ou téléphone',
          prefixIcon: Icons.search_rounded,
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 250), () => _load(v));
          },
        ),
        const SizedBox(height: JpSpacing.md),
        if (_error != null)
          JpBanner(message: AppFailure.from(_error!).message, tone: JpTone.danger)
        else if (_results == null)
          const Padding(
            padding: EdgeInsets.all(JpSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_results!.isEmpty)
          Padding(
            padding: const EdgeInsets.all(JpSpacing.lg),
            child: Text(
              'Aucun client trouvé.',
              textAlign: TextAlign.center,
              style: JpTypography.body.copyWith(color: p.textMuted),
            ),
          )
        else
          for (final c in _results!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: JpAvatar(name: c.name),
              title: Text(c.name),
              subtitle: Text([?c.phone, if (c.balance > 0) 'Doit ${Formatters.money(c.balance)}'].join(' · ')),
              onTap: () => Navigator.of(context).pop(c),
            ),
        if (canCreate) ...[
          const SizedBox(height: JpSpacing.md),
          JpButton.outline(
            label: 'Nouveau client',
            icon: Icons.person_add_alt_1_outlined,
            onPressed: () => setState(() {
              _creating = true;
              _name.text = _search.text.trim();
            }),
          ),
        ],
      ],
    );
  }
}
