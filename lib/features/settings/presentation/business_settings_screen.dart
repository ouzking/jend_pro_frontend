import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../../core/media/image_picking.dart';
import '../../../core/validation/validators.dart';
import '../../business/application/workspace_controller.dart';
import '../../business/data/business_repository.dart';
import '../../documents/application/document_providers.dart';
import '../../notifications/presentation/large_sale_threshold_sheet.dart';
import '../../products/presentation/widgets/product_form_fields.dart';
import '../application/settings_providers.dart';
import '../domain/settings_models.dart';

/// Fiche du commerce (`settings.manage`) : identité, mentions légales des
/// documents, fuseau horaire, règles de stock.
class BusinessSettingsScreen extends ConsumerWidget {
  const BusinessSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(businessSettingsProvider)
      .when(
        data: (s) => _Form(settings: s),
        loading: () => Scaffold(appBar: AppBar(), body: const JpSkeletonList(itemCount: 6)),
        error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: JpErrorState(error: e, onRetry: () => ref.invalidate(businessSettingsProvider)),
        ),
      );
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.settings});

  final BusinessSettings settings;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _formKey = GlobalKey<FormState>();
  late final _fields = {
    for (final c in BusinessSettings.textColumns) c: TextEditingController(text: widget.settings.text(c)),
  };
  late String _timezone = widget.settings.timezone;
  late bool _allowNegative = widget.settings.allowNegativeStock;
  bool _saving = false;
  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _changeLogo() async {
    final image = await pickImage(context, maxBytes: 1024 * 1024, maxDimension: 512, title: 'Logo du commerce');
    if (image == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await ref.read(businessRepositoryProvider).uploadLogo(widget.settings.id, image.bytes, mimeType: image.mimeType);
      ref
        ..invalidate(businessSettingsProvider)
        ..invalidate(documentIssuerProvider);
      await ref.read(workspaceProvider.notifier).refreshContext();
      if (mounted) JpOverlays.toast(context, 'Logo mis à jour.', tone: JpTone.success);
    } on AppFailure catch (f) {
      if (mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final s = widget.settings;
    String? v(String c) {
      final t = _fields[c]!.text.trim();
      if (t.isEmpty) return null;
      return c == 'phone' ? Validators.normalizePhone(t) : t;
    }

    final changes = <String, Object?>{
      for (final c in BusinessSettings.textColumns)
        if (v(c) != s.text(c)) c: v(c),
      if (_timezone != s.timezone) 'timezone': _timezone,
      if (_allowNegative != s.allowNegativeStock) 'allow_negative_stock': _allowNegative,
    };
    if (changes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(settingsActionsProvider).updateBusiness(changes);
      if (!mounted) return;
      JpOverlays.toast(context, 'Informations enregistrées.', tone: JpTone.success);
      Navigator.of(context).pop();
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleNegative(bool value) async {
    if (value) {
      final ok = await JpOverlays.confirm(
        context,
        title: 'Autoriser le stock négatif ?',
        message:
            'La caisse pourra vendre un produit même si le stock enregistré est à zéro. Pratique si vous saisissez vos arrivages après coup, mais vos quantités seront moins fiables.',
        confirmLabel: 'Autoriser',
      );
      if (!ok) return;
    }
    setState(() => _allowNegative = value);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.settings;
    final enabled = !_saving;
    final logoUrl = s.logoPath == null ? null : ref.read(businessRepositoryProvider).publicLogoUrl(s.logoPath!);
    final threshold = ref.watch(largeSaleThresholdProvider).value ?? s.largeSaleThreshold;
    final zones = {...westAfricanTimezones, if (!westAfricanTimezones.containsKey(_timezone)) _timezone: _timezone};

    JpTextField field(
      String column,
      String label, {
      IconData? icon,
      String? hint,
      TextInputType? keyboard,
      FormFieldValidator<String>? validator,
      TextCapitalization caps = TextCapitalization.none,
    }) => JpTextField(
      label: label,
      hint: hint,
      controller: _fields[column],
      prefixIcon: icon,
      keyboardType: keyboard,
      textCapitalization: caps,
      enabled: enabled,
      validator: validator,
    );

    const gap = SizedBox(height: JpSpacing.lg);
    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: JpSpacing.xl, bottom: JpSpacing.md),
      child: Text(title.toUpperCase(), style: JpTypography.overline.copyWith(color: p.textMuted)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Mon commerce')),
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
                        Center(
                          child: Semantics(
                            button: true,
                            label: 'Changer le logo',
                            child: InkWell(
                              onTap: _uploading || !enabled ? null : _changeLogo,
                              borderRadius: JpRadius.all(JpRadius.xl),
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  Container(
                                    width: 96,
                                    height: 96,
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      color: p.surfaceMuted,
                                      borderRadius: JpRadius.all(JpRadius.xl),
                                      border: Border.all(color: p.border),
                                    ),
                                    child: _uploading
                                        ? const Center(child: CircularProgressIndicator())
                                        : logoUrl == null
                                        ? Icon(Icons.storefront_outlined, size: 40, color: p.textMuted)
                                        : Image.network(
                                            logoUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                Icon(Icons.storefront_outlined, size: 40, color: p.textMuted),
                                          ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle),
                                    child: Icon(Icons.photo_camera_outlined, size: 16, color: p.textOnBrand),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: JpSpacing.sm),
                        Text(
                          'Le logo apparaît sur vos reçus et factures.',
                          textAlign: TextAlign.center,
                          style: JpTypography.caption.copyWith(color: p.textMuted),
                        ),
                        section('Identité'),
                        field(
                          'name',
                          'Nom du commerce',
                          icon: Icons.storefront_outlined,
                          caps: TextCapitalization.words,
                          validator: Validators.businessName,
                        ),
                        gap,
                        field(
                          'phone',
                          'Téléphone',
                          icon: Icons.phone_outlined,
                          keyboard: TextInputType.phone,
                          validator: Validators.optionalPhone,
                        ),
                        gap,
                        field(
                          'email',
                          'E-mail',
                          icon: Icons.alternate_email_rounded,
                          keyboard: TextInputType.emailAddress,
                          validator: (v) => (v?.trim().isEmpty ?? true) ? null : Validators.email(v),
                        ),
                        gap,
                        field('address', 'Adresse', icon: Icons.place_outlined),
                        gap,
                        field('city', 'Ville', icon: Icons.location_city_outlined, caps: TextCapitalization.words),
                        section('Mentions légales (reçus et factures)'),
                        field(
                          'legal_name',
                          'Raison sociale',
                          hint: 'Si différente du nom commercial',
                          caps: TextCapitalization.words,
                        ),
                        gap,
                        field('ninea', 'NINEA', hint: 'Facultatif'),
                        gap,
                        field('rccm', 'RCCM', hint: 'Facultatif'),
                        section('Fonctionnement'),
                        DropdownButtonFormField<String>(
                          initialValue: _timezone,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Fuseau horaire',
                            prefixIcon: Icon(Icons.schedule_rounded),
                            helperText: 'Sert à découper les journées des rapports.',
                          ),
                          items: [for (final e in zones.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                          onChanged: enabled ? (v) => setState(() => _timezone = v ?? _timezone) : null,
                        ),
                        gap,
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Monnaie',
                            prefixIcon: Icon(Icons.payments_outlined),
                            helperText: 'Fixée à la création du commerce.',
                          ),
                          child: Text(Formatters.currencySymbol(s.currencyCode)),
                        ),
                        gap,
                        LabeledSwitch(
                          title: 'Autoriser le stock négatif',
                          subtitle: 'Vendre même si le stock enregistré est épuisé',
                          value: _allowNegative,
                          onChanged: enabled ? _toggleNegative : null,
                        ),
                        gap,
                        JpCard(
                          onTap: () => showLargeSaleThresholdSheet(context),
                          padding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: JpSpacing.md),
                          child: Row(
                            children: [
                              Icon(Icons.notifications_active_outlined, color: p.textMuted),
                              const SizedBox(width: JpSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Alerte « vente importante »',
                                      style: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
                                    ),
                                    Text(
                                      threshold == null
                                          ? 'Désactivée'
                                          : 'À partir de ${Formatters.money(threshold, currency: s.currencyCode)}',
                                      style: JpTypography.caption.copyWith(color: p.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, color: p.textMuted),
                            ],
                          ),
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
                    child: JpButton(label: 'Enregistrer', isLoading: _saving, onPressed: _save),
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
