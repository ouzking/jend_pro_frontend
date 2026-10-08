import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/validation/validators.dart';
import '../application/supplier_providers.dart';
import '../domain/supplier_models.dart';

class SupplierFormScreen extends ConsumerWidget {
  const SupplierFormScreen({super.key, this.supplierId});

  final String? supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (supplierId == null) return const _Form();
    return ref
        .watch(supplierDetailProvider(supplierId!))
        .when(
          data: (s) => _Form(supplier: s),
          loading: () => Scaffold(appBar: AppBar(), body: const JpSkeletonList(itemCount: 4)),
          error: (e, _) => Scaffold(
            appBar: AppBar(),
            body: JpErrorState(error: e, onRetry: () => ref.invalidate(supplierDetailProvider(supplierId!))),
          ),
        );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({this.supplier});

  final Supplier? supplier;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _formKey = GlobalKey<FormState>();
  late final _fields = {
    'name': TextEditingController(text: widget.supplier?.name),
    'contact_name': TextEditingController(text: widget.supplier?.contactName),
    'phone': TextEditingController(text: widget.supplier?.phone),
    'email': TextEditingController(text: widget.supplier?.email),
    'address': TextEditingController(text: widget.supplier?.address),
    'notes': TextEditingController(text: widget.supplier?.notes),
  };
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    String? v(String k) => _fields[k]!.text.trim().isEmpty ? null : _fields[k]!.text.trim();
    final values = <String, Object?>{
      'name': v('name'),
      'contact_name': v('contact_name'),
      'phone': v('phone') == null ? null : Validators.normalizePhone(v('phone')),
      'email': v('email'),
      'address': v('address'),
      'notes': v('notes'),
    };
    final actions = ref.read(supplierActionsProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final s = widget.supplier;
      if (s == null) {
        final created = await actions.create({
          for (final e in values.entries)
            if (e.value != null) e.key: e.value,
        });
        if (!mounted) return;
        JpOverlays.toast(context, '« ${created.name} » ajouté.', tone: JpTone.success);
        context.pushReplacement(Routes.supplierDetail(created.id));
      } else {
        final before = {
          'name': s.name,
          'contact_name': s.contactName,
          'phone': s.phone,
          'email': s.email,
          'address': s.address,
          'notes': s.notes,
        };
        await actions.update(s, {
          for (final e in values.entries)
            if (e.value != before[e.key]) e.key: e.value,
        });
        if (!mounted) return;
        JpOverlays.toast(context, 'Fiche mise à jour.', tone: JpTone.success);
        Navigator.of(context).pop();
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
    final enabled = !_saving;
    return Scaffold(
      appBar: AppBar(title: Text(widget.supplier == null ? 'Nouveau fournisseur' : 'Modifier le fournisseur')),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, JpSpacing.xxl),
                children: [
                  JpConstrained(
                    maxWidth: JpSpacing.maxFormWidth + 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FormErrorBanner(message: _error),
                        JpTextField(
                          label: 'Nom du fournisseur',
                          hint: 'Ex. Sedima Distribution',
                          controller: _fields['name'],
                          prefixIcon: Icons.local_shipping_outlined,
                          textCapitalization: TextCapitalization.words,
                          enabled: enabled,
                          validator: (v) => (v?.trim().isEmpty ?? true) ? 'Saisissez le nom.' : null,
                        ),
                        const SizedBox(height: JpSpacing.lg),
                        JpTextField(
                          label: 'Personne à contacter',
                          controller: _fields['contact_name'],
                          prefixIcon: Icons.person_outline_rounded,
                          textCapitalization: TextCapitalization.words,
                          enabled: enabled,
                        ),
                        const SizedBox(height: JpSpacing.lg),
                        JpTextField(
                          label: 'Téléphone',
                          hint: '77 123 45 67',
                          controller: _fields['phone'],
                          prefixIcon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          enabled: enabled,
                          validator: Validators.optionalPhone,
                        ),
                        const SizedBox(height: JpSpacing.lg),
                        JpTextField(
                          label: 'E-mail',
                          controller: _fields['email'],
                          prefixIcon: Icons.alternate_email_rounded,
                          keyboardType: TextInputType.emailAddress,
                          enabled: enabled,
                          validator: (v) => (v?.trim().isEmpty ?? true) ? null : Validators.email(v),
                        ),
                        const SizedBox(height: JpSpacing.lg),
                        JpTextField(
                          label: 'Adresse',
                          controller: _fields['address'],
                          prefixIcon: Icons.place_outlined,
                          enabled: enabled,
                        ),
                        const SizedBox(height: JpSpacing.lg),
                        JpTextField(
                          label: 'Notes',
                          hint: 'Délais de livraison, conditions…',
                          controller: _fields['notes'],
                          maxLines: 3,
                          enabled: enabled,
                        ),
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
                  child: JpButton(
                    label: widget.supplier == null ? 'Ajouter le fournisseur' : 'Enregistrer',
                    isLoading: _saving,
                    onPressed: _save,
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
