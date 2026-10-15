import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Langue d'écoute. Le wolof n'est proposé que si le téléphone sait le
/// reconnaître ; sinon l'écoute se fait en français et le module de
/// compréhension accepte les nombres wolof tels qu'ils sont transcrits.
enum VoiceLanguage {
  french('Français'),
  wolof('Wolof');

  const VoiceLanguage(this.label);

  final String label;
}

/// Problème d'écoute, traduit pour l'utilisateur.
class VoiceFailure implements Exception {
  const VoiceFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reconnaissance vocale du téléphone (remplaçable dans les tests).
abstract class VoiceRecognizer {
  /// Prépare le service et demande l'autorisation du micro si besoin.
  /// Lève [VoiceFailure] si la voix est indisponible ou refusée.
  Future<void> initialize();

  /// Identifiant de langue du téléphone pour [language], ou `null` si absent.
  Future<String?> localeFor(VoiceLanguage language);

  /// Écoute jusqu'à une pause : [onText] reçoit le texte au fil de l'eau
  /// (`isFinal` à la fin), [onError] un message lisible.
  Future<void> listen({
    required String? localeId,
    required void Function(String text, bool isFinal) onText,
    required void Function(String message) onError,
    void Function(double level)? onLevel,
  });

  Future<void> stop();

  Future<void> cancel();
}

final voiceRecognizerProvider = Provider<VoiceRecognizer>((ref) => SpeechToTextRecognizer());

/// Implémentation `speech_to_text` (Android : service Google ; iPhone : Apple).
class SpeechToTextRecognizer implements VoiceRecognizer {
  SpeechToTextRecognizer([SpeechToText? speech]) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  void Function(String message)? _onError;
  void Function(String text, bool isFinal)? _onText;
  String _last = '';
  bool _finalSent = false;

  static String message(String code) => switch (code) {
    'error_no_match' || 'error_speech_timeout' => 'Je n’ai rien compris. Parlez près du téléphone et réessayez.',
    'error_network' ||
    'error_network_timeout' ||
    'error_server' ||
    'error_server_disconnected' => 'La reconnaissance vocale a besoin d’internet sur ce téléphone.',
    'error_permission' ||
    'error_insufficient_permissions' => 'Autorisez le micro pour JËND PRO dans les réglages du téléphone.',
    'error_busy' || 'error_recognizer_busy' => 'Le micro est déjà utilisé. Réessayez dans un instant.',
    'error_language_not_supported' ||
    'error_language_unavailable' => 'Cette langue n’est pas disponible sur ce téléphone.',
    _ => 'La reconnaissance vocale a échoué. Réessayez.',
  };

  @override
  Future<void> initialize() async {
    final ok = await _speech.initialize(
      onError: (SpeechRecognitionError e) => _onError?.call(message(e.errorMsg)),
      onStatus: (status) {
        // Fin d'écoute sans résultat final : on transmet le dernier texte.
        if ((status == 'done' || status == 'notListening') && !_finalSent) {
          _finalSent = true;
          _onText?.call(_last, true);
        }
      },
    );
    if (!ok) {
      throw const VoiceFailure(
        'La reconnaissance vocale n’est pas disponible : autorisez le micro, ou installez l’application Google sur ce téléphone.',
      );
    }
  }

  @override
  Future<String?> localeFor(VoiceLanguage language) async {
    final locales = await _speech.locales();
    String norm(String id) => id.replaceAll('-', '_').toLowerCase();
    final ids = [for (final l in locales) l.localeId];
    final prefix = language == VoiceLanguage.wolof ? 'wo' : 'fr';
    final preferred = language == VoiceLanguage.wolof ? 'wo_sn' : 'fr_sn';
    for (final id in ids) {
      if (norm(id) == preferred) return id;
    }
    if (language == VoiceLanguage.french) {
      for (final id in ids) {
        if (norm(id) == 'fr_fr') return id;
      }
    }
    for (final id in ids) {
      if (norm(id).startsWith('${prefix}_') || norm(id) == prefix) return id;
    }
    return null;
  }

  @override
  Future<void> listen({
    required String? localeId,
    required void Function(String text, bool isFinal) onText,
    required void Function(String message) onError,
    void Function(double level)? onLevel,
  }) async {
    _onText = onText;
    _onError = onError;
    _last = '';
    _finalSent = false;
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) {
        _last = r.recognizedWords;
        if (r.finalResult) {
          if (_finalSent) return;
          _finalSent = true;
        }
        onText(r.recognizedWords, r.finalResult);
      },
      onSoundLevelChange: onLevel,
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}
