import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/formatters.dart';
import '../../notifications/application/notification_providers.dart';
import '../../notifications/domain/notification_models.dart';
import '../application/support_providers.dart';
import '../domain/support_models.dart';

/// Conversation avec le support. Les réponses de l'équipe arrivent par
/// notification (temps réel) ; la conversation est aussi relue régulièrement
/// tant que l'écran est ouvert.
class TicketScreen extends ConsumerStatefulWidget {
  const TicketScreen({super.key, required this.ticketId});

  final String ticketId;

  static const refreshEvery = Duration(seconds: 20);

  @override
  ConsumerState<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends ConsumerState<TicketScreen> {
  final _message = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  bool _sending = false;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(TicketScreen.refreshEvery, (_) => ref.read(supportActionsProvider).refresh(widget.ticketId));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: JpMotion.base, curve: Curves.easeOut);
    }
  });

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(supportActionsProvider).reply(widget.ticketId, text);
      _message.clear();
      HapticFeedback.lightImpact();
    } on AppFailure catch (f) {
      if (mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ticket = ref.watch(supportTicketProvider(widget.ticketId));
    final messages = ref.watch(supportMessagesProvider(widget.ticketId));

    // Réponse du support pendant que la conversation est ouverte.
    ref.listen<AppNotification?>(incomingNotificationProvider, (_, n) {
      if (isSupportReplyFor(n, widget.ticketId)) ref.read(supportActionsProvider).refresh(widget.ticketId);
    });
    final count = messages.value?.length ?? 0;
    if (count != _lastCount) {
      _lastCount = count;
      _scrollToEnd();
    }

    final t = ticket.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(t == null ? 'Demande' : 'Demande #${t.number}'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(supportActionsProvider).refresh(widget.ticketId),
          ),
        ],
      ),
      body: Column(
        children: [
          if (t != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.gutter, JpSpacing.sm),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.border)),
              ),
              child: JpConstrained(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.subject, style: JpTypography.bodyStrong.copyWith(color: p.textPrimary)),
                    const SizedBox(height: JpSpacing.xs),
                    JpBadge(label: t.status.label, tone: t.status.tone, dot: true),
                  ],
                ),
              ),
            ),
          Expanded(
            child: JpConstrained(
              child: JpAsyncView<List<SupportMessage>>(
                value: messages,
                onRetry: () => ref.invalidate(supportMessagesProvider(widget.ticketId)),
                data: (list) => ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(JpSpacing.gutter),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final m = list[i];
                    final newDay = i == 0 || !_sameDay(list[i - 1].createdAt, m.createdAt);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (newDay)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: JpSpacing.md),
                            child: Text(
                              Formatters.date(m.createdAt),
                              textAlign: TextAlign.center,
                              style: JpTypography.caption.copyWith(color: p.textMuted),
                            ),
                          ),
                        _Bubble(message: m),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          _Composer(ticket: t, controller: _message, sending: _sending, onSend: _send),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) {
    final x = a.toLocal(), y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final SupportMessage message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final mine = !message.fromStaff;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Container(
          margin: const EdgeInsets.only(bottom: JpSpacing.sm),
          padding: const EdgeInsets.symmetric(horizontal: JpSpacing.md, vertical: JpSpacing.sm),
          decoration: BoxDecoration(
            color: mine ? p.brand : p.surfaceMuted,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(JpRadius.lg),
              topRight: const Radius.circular(JpRadius.lg),
              bottomLeft: Radius.circular(mine ? JpRadius.lg : JpRadius.xs),
              bottomRight: Radius.circular(mine ? JpRadius.xs : JpRadius.lg),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    'Support JËND PRO',
                    style: JpTypography.caption.copyWith(color: p.brand, fontWeight: FontWeight.w700),
                  ),
                ),
              SelectableText(
                message.body,
                style: JpTypography.body.copyWith(color: mine ? p.textOnBrand : p.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                Formatters.time(message.createdAt),
                style: JpTypography.caption.copyWith(
                  color: mine ? p.textOnBrand.withValues(alpha: 0.75) : p.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.ticket, required this.controller, required this.sending, required this.onSend});

  final SupportTicket? ticket;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = ticket;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.background,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(JpSpacing.gutter, JpSpacing.sm, JpSpacing.sm, JpSpacing.sm),
          child: t != null && !t.canReply
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: JpSpacing.sm),
                  child: Text(
                    'Demande fermée. Ouvrez une nouvelle demande si besoin.',
                    textAlign: TextAlign.center,
                    style: JpTypography.bodySmall.copyWith(color: p.textMuted),
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 5000,
                        enabled: !sending,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: t?.status == TicketStatus.resolved
                              ? 'Répondre rouvrira la demande…'
                              : 'Votre message…',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: JpSpacing.xs),
                    IconButton.filled(
                      tooltip: 'Envoyer',
                      onPressed: sending ? null : onSend,
                      icon: sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
