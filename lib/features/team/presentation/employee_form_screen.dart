import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/formatting/input_formatters.dart';
import '../../../core/validation/validators.dart';
import '../../products/presentation/widgets/product_form_fields.dart';
import '../application/team_providers.dart';
import '../domain/team_models.dart';

class EmployeeFormScreen extends ConsumerWidget {
  const EmployeeFormScreen({super.key, this.employeeId});

  final String? employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (employeeId == null) return const _Form();
    return ref
        .watch(employeeDetailProvider(employeeId!))
        .when(
          data: (e) => _Form(employee: e),
          loading: () => Scaffold(appBar: AppBar(), body: const JpSkeletonList(itemCount: 4)),
          error: (e, _) => Scaffold(
            appBar: AppBar(),
            body: JpErrorState(error: e, onRetry: () => ref.invalidate(employeeDetailProvider(employeeId!))),
          ),
        );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({this.employee});

  final Employee? employee;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.employee?.fullName);
  late final _phone = TextEditingController(text: widget.employee?.phone);
  late final _position = TextEditingController(text: widget.employee?.position);
  late final _salary = TextEditingController(
    text: widget.employee?.salaryAmount == null ? '' : AmountInputFormatter.format(widget.employee!.salaryAmount!),
  );
  late final _notes = TextEditingController(text: widget.employee?.notes);
  late DateTime? _hiredAt = widget.employee?.hiredAt;
  late DateTime? _endedAt = widget.employee?.endedAt;
  late String? _memberId = widget.employee?.memberId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _position, _salary, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick({required bool end}) async {
    final now = DateTime.now();
    final initial = (end ? _endedAt : _hiredAt) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: end && _hiredAt != null ? _hiredAt! : DateTime(now.year - 40),
      lastDate: DateTime(now.year + 2),
      helpText: end ? 'Fin de contrat' : 'Date d’embauche',
    );
    if (picked == null) return;
    setState(() {
      if (end) {
        _endedAt = picked;
      } else {
        _hiredAt = picked;
        if (_endedAt != null && _endedAt!.isBefore(picked)) _endedAt = null;
      }
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final input = EmployeeInput(
      fullName: _name.text,
      phone: _phone.text.trim().isEmpty ? null : Validators.normalizePhone(_phone.text),
      position: _position.text,
      salaryAmount: AmountInputFormatter.parse(_salary.text),
      hiredAt: _hiredAt,
      endedAt: _endedAt,
      notes: _notes.text,
      memberId: _memberId,
    );
    final actions = ref.read(teamActionsProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final e = widget.employee;
      if (e == null) {
        final created = await actions.createEmployee(input);
        if (!mounted) return;
        JpOverlays.toast(context, 'Fiche de ${created.fullName} créée.', tone: JpTone.success);
        context.pushReplacement(Routes.employeeDetail(created.id));
      } else {
        await actions.updateEmployee(e.id, input);
        if (!mounted) return;
        JpOverlays.toast(context, 'Fiche mise à jour.', tone: JpTone.success);
        Navigator.of(context).pop();
      }
    } on AppFailure catch (f) {
      if (mounted) {
        setState(
          () => _error = f.code == 'UNIQUE_VIOLATION' ? 'Ce compte est déjà lié à une autre fiche employé.' : f.message,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = !_saving;
    final members = ref.watch(linkableMembersProvider).value ?? const <String, TeamMember>{};

    Widget dateTile(String label, DateTime? value, {required bool end}) => JpCard(
      onTap: enabled ? () => _pick(end: end) : null,
      padding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.md),
      child: Row(
        children: [
          Icon(end ? Icons.event_busy_outlined : Icons.event_available_outlined, color: p.textMuted),
          const SizedBox(width: JpSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: JpTypography.caption.copyWith(color: p.textMuted)),
                Text(
                  value == null ? 'Non renseignée' : Formatters.date(value),
                  style: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
                ),
              ],
            ),
          ),
          if (value != null)
            IconButton(
              tooltip: 'Effacer',
              icon: const Icon(Icons.close_rounded),
              onPressed: enabled ? () => setState(() => end ? _endedAt = null : _hiredAt = null) : null,
            ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(widget.employee == null ? 'Nouvel employé' : 'Modifier la fiche')),
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
                          label: 'Nom complet',
                          hint: 'Ex. Moussa Diop',
                          controller: _name,
                          prefixIcon: Icons.person_outline_rounded,
                          textCapitalization: TextCapitalization.words,
                          enabled: enabled,
                          maxLength: 120,
                          validator: (v) => (v?.trim().isEmpty ?? true) ? 'Saisissez le nom.' : null,
                        ),
                        const SizedBox(height: JpSpacing.lg),
                        JpTextField(
                          label: 'Poste',
                          hint: 'Ex. Vendeur, magasinier, livreur',
                          controller: _position,
                          prefixIcon: Icons.work_outline_rounded,
                          textCapitalization: TextCapitalization.sentences,
                          enabled: enabled,
                          maxLength: 80,
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
                        AmountField(label: 'Salaire mensuel', controller: _salary, enabled: enabled, optional: true),
                        const SizedBox(height: JpSpacing.lg),
                        dateTile('Date d’embauche', _hiredAt, end: false),
                        const SizedBox(height: JpSpacing.sm),
                        dateTile('Fin de contrat', _endedAt, end: true),
                        if (members.isNotEmpty || _memberId != null) ...[
                          const SizedBox(height: JpSpacing.lg),
                          DropdownButtonFormField<String?>(
                            initialValue: _memberId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Compte JËND PRO lié',
                              prefixIcon: Icon(Icons.link_rounded),
                            ),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Aucun')),
                              for (final e in members.entries)
                                DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    '${e.value.displayName} · ${e.value.roleName}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (_memberId != null && !members.containsKey(_memberId))
                                DropdownMenuItem(value: _memberId, child: const Text('Compte lié')),
                            ],
                            onChanged: enabled ? (v) => setState(() => _memberId = v) : null,
                          ),
                        ],
                        const SizedBox(height: JpSpacing.lg),
                        JpTextField(
                          label: 'Notes',
                          hint: 'Horaires, avances sur salaire…',
                          controller: _notes,
                          maxLines: 3,
                          maxLength: 1000,
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
                  child: JpConstrained(
                    maxWidth: JpSpacing.maxFormWidth + 80,
                    child: JpButton(
                      label: widget.employee == null ? 'Créer la fiche' : 'Enregistrer',
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
