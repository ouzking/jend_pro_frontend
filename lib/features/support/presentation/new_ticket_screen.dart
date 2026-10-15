import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../business/application/workspace_controller.dart';
import '../../products/presentation/widgets/product_form_fields.dart';
import '../application/support_providers.dart';
import '../domain/support_models.dart';

/// Nouvelle demande d'aide : sujet (suggestions rapides) et message.
class NewTicketScreen extends ConsumerStatefulWidget {
  const NewTicketScreen({super.key});

  @override
  ConsumerState<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends ConsumerState<NewTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _urgent = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(supportActionsProvider)
          .create(subject: _subject.text, body: _body.text, urgent: _urgent);
      if (!mounted) return;
      JpOverlays.toast(context, 'Demande envoyée. Le support vous répondra ici.', tone: JpTone.success);
      context.pushReplacement(Routes.supportTicket(id));
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final business = ref.watch(activeBusinessProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Écrire au support')),
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
                        Text('De quoi s’agit-il ?', style: JpTypography.label.copyWith(color: p.textPrimary)),
                        const SizedBox(height: JpSpacing.sm),
                        Wrap(
                          spacing: JpSpacing.sm,
                          runSpacing: JpSpacing.sm,
                          children: [
                            for (final topic in supportTopics)
                              ChoiceChip(
                                label: Text(topic),
                                selected: _subject.text == topic,
                                onSelected: _sending ? null : (_) => setState(() => _subject.text = topic),
                              ),
                          ],
                        ),
                        const SizedBox(height: JpSpacing.lg),
                        JpTextField(
                          label: 'Sujet',
                          controller: _subject,
                          maxLength: 200,
                          textCapitalization: TextCapitalization.sentences,
                          enabled: !_sending,
                          onChanged: (_) => setState(() {}),
                          validator: (v) =>
                              (v?.trim().length ?? 0) < 3 ? 'Indiquez un sujet (3 caractères min.).' : null,
                        ),
                        const SizedBox(height: JpSpacing.lg),
                        JpTextField(
                          label: 'Votre message',
                          hint: 'Décrivez ce qui se passe : écran concerné, message d’erreur, ce que vous avez essayé…',
                          controller: _body,
                          maxLines: 6,
                          maxLength: 5000,
                          textCapitalization: TextCapitalization.sentences,
                          enabled: !_sending,
                          validator: (v) => (v?.trim().isEmpty ?? true) ? 'Écrivez votre message.' : null,
                        ),
                        const SizedBox(height: JpSpacing.md),
                        LabeledSwitch(
                          title: 'C’est bloquant',
                          subtitle: 'Je ne peux plus vendre ou travailler normalement',
                          value: _urgent,
                          onChanged: _sending ? null : (v) => setState(() => _urgent = v),
                        ),
                        if (business != null) ...[
                          const SizedBox(height: JpSpacing.md),
                          Text(
                            'Le commerce « ${business.businessName} » est joint à la demande pour que le support puisse vous aider.',
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
                    child: JpButton(label: 'Envoyer', icon: Icons.send_rounded, isLoading: _sending, onPressed: _send),
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
