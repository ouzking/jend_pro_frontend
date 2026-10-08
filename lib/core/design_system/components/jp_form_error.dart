import 'package:flutter/material.dart';

import '../tokens/jp_metrics.dart';
import '../tokens/jp_palette.dart';
import 'jp_misc.dart';

/// Bloc d'erreur de formulaire, annoncé aux lecteurs d'écran.
class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: JpMotion.base,
      curve: JpMotion.emphasized,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: JpSpacing.lg),
              child: Semantics(
                liveRegion: true,
                child: JpBanner(message: message!, tone: JpTone.danger, icon: Icons.error_outline_rounded),
              ),
            ),
    );
  }
}
