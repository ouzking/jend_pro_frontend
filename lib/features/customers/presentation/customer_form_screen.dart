import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/input_formatters.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/validation/validators.dart';
import '../../business/application/workspace_controller.dart';
import '../../products/presentation/widgets/product_form_fields.dart';
import '../application/customer_providers.dart';
import '../domain/customer_models.dart';

/// Création (`customerId == null`) ou modification d'un client.
class CustomerFormScreen extends ConsumerWidget {
  const CustomerFormScreen({super.key, this.customerId});

  final String? customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (customerId == null) return const _Form();
    return ref
        .watch(customerDetailProvider(customerId!))
        .when(
          data: (c) => _Form(customer: c),
          loading: () => Scaffold(appBar: AppBar(), body: const JpSkeletonList(itemCount: 4)),
          error: (e, _) => Scaffold(
            appBar: AppBar(),
            body: JpErrorState(error: e, onRetry: () => ref.invalidate(customerDetailProvider(customerId!))),
          ),
        );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({this.customer});

  final Customer? customer;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.customer?.name);
  late final _phone = TextEditingController(text: widget.customer?.phone);
  late final _email = TextEditingController(text: widget.customer?.email);
  late final _address = TextEditingController(text: widget.customer?.address);
  late final _notes = TextEditingController(text: widget.customer?.notes);
  final _limit = TextEditingController();
  final _opening = TextEditingController();
  bool _allowCredit = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.customer != null;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _address, _notes, _limit, _opening]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _clean(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final actions = ref.read(customerActionsProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final phone = _clean(_phone) == null ? null : Validators.normalizePhone(_phone.text);
      if (_isEdit) {
        final c = widget.customer!;
        final next = {
          'name': _name.text.trim(),
          'phone': phone,
          'email': _clean(_email),
          'address': _clean(_address),
          'notes': _clean(_notes),
        };
        final before = {'name': c.name, 'phone': c.phone, 'email': c.email, 'address': c.address, 'notes': c.notes};
        await actions.update(c, {
          for (final e in next.entries)
            if (e.value != before[e.key]) e.key: e.value,
        });
        if (!mounted) return;
        JpOverlays.toast(context, 'Fiche mise à jour.', tone: JpTone.success);
        Navigator.of(context).pop();
      } else {
        final created = await actions.create(
          name: _name.text,
          phone: phone,
          email: _clean(_email),
          address: _clean(_address),
          notes: _clean(_notes),
          setCreditLimit: _allowCredit,
          creditLimit: AmountInputFormatter.parse(_limit.text),
          openingBalance: AmountInputFormatter.parse(_opening.text) ?? 0,
        );
        if (!mounted) return;
        JpOverlays.toast(context, '« ${created.name} » ajouté.', tone: JpTone.success);
        context.pushReplacement(Routes.customerDetail(created.id));
      }
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final canManage = ref.watch(permissionsProvider).can(Permission.customersManage);
    final enabled = !_saving;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Modifier le client' : 'Nouveau client')),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, JpSpacing.xxl),
                children: [
                  JpConstrained(
                    maxWidth: JpSpacing.maxFormWidth + 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FormErrorBanner(message: _error),
                        JpTextField(
                          label: 'Nom',
                          hint: 'Ex. Fatou Sow',
                          controller: _name,
                          prefixIcon: Icons.person_outline_rounded,
                          textCapitalization: TextCapitalization.words,
                          maxLength: 150,
                          enabled: enabled,
                          validator: (v) => (v?.trim().isEmpty ?? true) ? 'Saisissez le nom du client.' : null,
                        ),
                        const SizedBox(height: JpSpacing.lg),
                        JpTextField(
                          label: 'Téléphone',
                          hint: '77 123 45 67',
                          controller: _phone,
                          prefixIcon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          enabled: enabled,
                          validator: Validators.optionalPhone,
                        ),
                        const SizedBox(height: JpSpacing.lg),
                        JpTextField(
                          label: 'E-mail (facultatif)',
                          controller: _email,
                          prefixIcon: Icons.alternate_email_rounded,
                          keyboardType: TextInputType.emailAddress,
                          enabled: enabled,
                          validator: (v) => (v?.trim().isEmpty ?? true) ? null : Validators.email(v),
                        ),
                        const SizedBox(height: JpSpacing.lg),
                        JpTextField(
                          label: 'Adresse (facultatif)',
                          controller: _address,
                          prefixIcon: Icons.place_outlined,
                          textCapitalization: TextCapitalization.sentences,
                          enabled: enabled,
                        ),
                        const SizedBox(height: JpSpacing.lg),
                        JpTextField(
                          label: 'Notes (facultatif)',
                          controller: _notes,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                          enabled: enabled,
                        ),
                        if (!_isEdit && canManage) ...[
                          const SizedBox(height: JpSpacing.xl),
                          const JpSectionHeader(title: 'Crédit'),
                          LabeledSwitch(
                            title: 'Autoriser le crédit',
                            subtitle: 'Sinon, ce client paie toujours comptant.',
                            value: _allowCredit,
                            onChanged: enabled ? (v) => setState(() => _allowCredit = v) : null,
                          ),
                          if (_allowCredit)
                            AmountField(
                              label: 'Plafond (vide = sans plafond)',
                              controller: _limit,
                              enabled: enabled,
                              optional: true,
                            ),
                          const SizedBox(height: JpSpacing.lg),
                          AmountField(
                            label: 'Doit déjà (cahier de crédit)',
                            controller: _opening,
                            enabled: enabled,
                            optional: true,
                          ),
                          const SizedBox(height: JpSpacing.xs),
                          Text(
                            'Reprise d’une dette existante, enregistrée et tracée dans le relevé.',
                            style: JpTypography.caption.copyWith(color: p.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: p.background,
                border: Border(top: BorderSide(color: p.border)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(JpSpacing.gutter),
                  child: JpConstrained(
                    maxWidth: JpSpacing.maxFormWidth + 80,
                    child: JpButton(
                      label: _isEdit ? 'Enregistrer' : 'Ajouter le client',
                      isLoading: _saving,
                      onPressed: _save,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
