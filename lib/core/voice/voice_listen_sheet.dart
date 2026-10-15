import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_system/design_system.dart';
import '../storage/preferences.dart';
import 'voice_recognizer.dart';

/// Ouvre l'écoute et renvoie le texte dicté (ou `null` si annulé / rien dit).
Future<String?> listenToVoice(BuildContext context, {required String title, required String example}) {
  HapticFeedback.selectionClick();
  return JpOverlays.sheet<String>(
    context,
    title: title,
    child: _ListenPanel(example: example),
  );
}

/// Bouton micro pour un champ de recherche : la phrase dictée remplace le
/// texte du champ puis déclenche [onChanged].
class VoiceSearchButton extends StatelessWidget {
  const VoiceSearchButton({super.key, required this.controller, this.onChanged, this.example = 'riz parfumé'});

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String example;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Recherche vocale',
    icon: const Icon(Icons.mic_none_rounded),
    onPressed: () async {
      final text = await listenToVoice(context, title: 'Dites ce que vous cherchez', example: example);
      if (text == null || text.trim().isEmpty) return;
      controller.text = text.trim();
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
      onChanged?.call(controller.text);
    },
  );
}

/// Actions d'un champ de recherche : micro (dictée) et, quand le champ est
/// rempli, effacer. [onChanged] reçoit le nouveau texte (dicté ou vide).
class SearchFieldActions extends StatelessWidget {
  const SearchFieldActions({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onClear,
    this.example = 'riz parfumé',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  /// Effacement spécifique ; par défaut : vide le champ puis `onChanged('')`.
  final VoidCallback? onClear;
  final String example;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VoiceSearchButton(controller: controller, onChanged: onChanged, example: example),
        if (value.text.isNotEmpty)
          IconButton(
            tooltip: 'Effacer',
            icon: const Icon(Icons.close_rounded),
            onPressed:
                onClear ??
                () {
                  controller.clear();
                  onChanged('');
                },
          ),
      ],
    ),
  );
}

final voiceLanguageProvider = NotifierProvider<VoiceLanguageNotifier, VoiceLanguage>(VoiceLanguageNotifier.new);

/// Langue d'écoute préférée (réglage de l'appareil).
class VoiceLanguageNotifier extends Notifier<VoiceLanguage> {
  static const _key = 'voice_language';

  @override
  VoiceLanguage build() {
    final stored = ref.read(sharedPreferencesProvider).getString(_key);
    return VoiceLanguage.values.firstWhere((l) => l.name == stored, orElse: () => VoiceLanguage.french);
  }

  void set(VoiceLanguage language) {
    state = language;
    ref.read(sharedPreferencesProvider).setString(_key, language.name);
  }
}

enum _Phase { starting, listening, failed }

class _ListenPanel extends ConsumerStatefulWidget {
  const _ListenPanel({required this.example});

  final String example;

  @override
  ConsumerState<_ListenPanel> createState() => _ListenPanelState();
}

class _ListenPanelState extends ConsumerState<_ListenPanel> {
  late final VoiceRecognizer _voice = ref.read(voiceRecognizerProvider);
  _Phase _phase = _Phase.starting;
  String _text = '';
  String? _error;
  double _level = 0;
  bool _wolofAvailable = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    if (!_done) _voice.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.starting;
      _text = '';
      _error = null;
    });
    try {
      await _voice.initialize();
      _wolofAvailable = await _voice.localeFor(VoiceLanguage.wolof) != null;
      final wanted = ref.read(voiceLanguageProvider);
      final language = wanted == VoiceLanguage.wolof && !_wolofAvailable ? VoiceLanguage.french : wanted;
      final locale = await _voice.localeFor(language);
      if (!mounted) return;
      setState(() => _phase = _Phase.listening);
      await _voice.listen(
        localeId: locale,
        onLevel: (level) {
          if (mounted) setState(() => _level = level);
        },
        onText: (text, isFinal) {
          if (!mounted) return;
          setState(() => _text = text);
          if (isFinal) _finish();
        },
        onError: (message) {
          if (mounted && !_done) {
            setState(() {
              _phase = _Phase.failed;
              _error = message;
            });
          }
        },
      );
    } on VoiceFailure catch (f) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = f.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = 'La reconnaissance vocale n’a pas pu démarrer. Réessayez.';
        });
      }
    }
  }

  void _finish() {
    if (_done) return;
    if (_text.trim().isEmpty) {
      setState(() {
        _phase = _Phase.failed;
        _error = 'Je n’ai rien entendu. Parlez près du téléphone et réessayez.';
      });
      return;
    }
    _done = true;
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(_text.trim());
  }

  Future<void> _stop() async {
    await _voice.stop();
    // Certains téléphones n'envoient pas de résultat final après un arrêt
    // manuel : on retient le dernier texte entendu.
    if (mounted) _finish();
  }

  Future<void> _switch(VoiceLanguage language) async {
    ref.read(voiceLanguageProvider.notifier).set(language);
    await _voice.cancel();
    await _start();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final language = ref.watch(voiceLanguageProvider);
    final listening = _phase == _Phase.listening;
    final scale = 1.0 + (listening ? (_level.clamp(0.0, 10.0) / 10) * 0.35 : 0.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_wolofAvailable) ...[
          SegmentedButton<VoiceLanguage>(
            segments: [for (final l in VoiceLanguage.values) ButtonSegment(value: l, label: Text(l.label))],
            selected: {language},
            showSelectedIcon: false,
            onSelectionChanged: (s) => _switch(s.single),
          ),
          const SizedBox(height: JpSpacing.lg),
        ],
        Center(
          child: Semantics(
            label: listening ? 'Écoute en cours' : 'Micro',
            child: AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 120),
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _phase == _Phase.failed ? p.dangerSoft : p.brandSoft,
                  boxShadow: listening ? JpShadows.glow(p.signal) : null,
                ),
                child: Icon(
                  _phase == _Phase.failed ? Icons.mic_off_rounded : Icons.mic_rounded,
                  size: 40,
                  color: _phase == _Phase.failed ? p.danger : p.brand,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: JpSpacing.lg),
        Semantics(
          liveRegion: true,
          child: Text(
            switch (_phase) {
              _Phase.starting => 'Préparation du micro…',
              _Phase.failed => _error ?? '',
              _Phase.listening => _text.isEmpty ? 'Je vous écoute…' : '« $_text »',
            },
            textAlign: TextAlign.center,
            style: (_text.isEmpty || _phase != _Phase.listening ? JpTypography.body : JpTypography.title).copyWith(
              color: _phase == _Phase.failed ? p.danger : p.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: JpSpacing.sm),
        Text(
          'Exemple : « ${widget.example} »'
          '${_wolofAvailable ? '' : '\nVous pouvez mélanger français et wolof : « ñaar riz ak benn huile ».'}',
          textAlign: TextAlign.center,
          style: JpTypography.caption.copyWith(color: p.textMuted),
        ),
        const SizedBox(height: JpSpacing.xl),
        if (_phase == _Phase.failed)
          JpButton(label: 'Réessayer', icon: Icons.refresh_rounded, onPressed: _start)
        else
          JpButton(label: 'Terminé', icon: Icons.check_rounded, onPressed: listening ? _stop : null),
        const SizedBox(height: JpSpacing.sm),
        JpButton.ghost(label: 'Annuler', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}
