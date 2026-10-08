import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/media/image_picking.dart';
import '../../../business/application/workspace_controller.dart';
import '../../application/setup_wizard_controller.dart';
import '../setup_wizard_screen.dart';

/// Logo du commerce : bucket `business-assets` (JPEG / PNG / WebP, 1 Mo).
class LogoStep extends ConsumerStatefulWidget {
  const LogoStep({super.key});

  @override
  ConsumerState<LogoStep> createState() => _LogoStepState();
}

class _LogoStepState extends ConsumerState<LogoStep> {
  static const _maxBytes = 1024 * 1024;
  bool _uploading = false;

  Future<void> _pick(ImageSource source) async {
    // Redimensionné et compressé sur l'appareil : réseau mobile, 1 Mo max.
    final image = await pickImage(context, maxBytes: _maxBytes, maxDimension: 512, source: source);
    if (image == null || !mounted) return;
    final (bytes, mime) = (image.bytes, image.mimeType);

    setState(() => _uploading = true);
    try {
      await ref.read(setupWizardProvider.notifier).uploadLogo(bytes, mime);
      if (mounted) JpOverlays.toast(context, 'Logo enregistré.', tone: JpTone.success);
    } on AppFailure catch (f) {
      if (mounted) JpOverlays.toast(context, f.message, tone: JpTone.danger);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final controller = ref.read(setupWizardProvider.notifier);
    final logoPath = ref.watch(setupWizardProvider.select((s) => s.profile?.logoPath));
    final businessName = ref.watch(activeBusinessProvider)?.businessName;
    final hasLogo = logoPath != null;

    return SetupStepLayout(
      stepLabel: 'Étape 3 sur 5',
      title: 'Votre logo',
      subtitle: 'Il personnalise vos reçus et votre espace. Vous pourrez le changer plus tard.',
      primary: JpButton(
        label: hasLogo ? 'Continuer' : 'Plus tard',
        trailingIcon: Icons.arrow_forward_rounded,
        variant: hasLogo ? JpButtonVariant.primary : JpButtonVariant.secondary,
        onPressed: _uploading ? null : controller.next,
      ),
      child: Column(
        children: [
          const SizedBox(height: JpSpacing.lg),
          AnimatedSwitcher(
            duration: JpMotion.base,
            child: Container(
              key: ValueKey(logoPath),
              width: 140,
              height: 140,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: JpRadius.all(JpRadius.xxl),
                border: Border.all(color: hasLogo ? p.border : p.borderStrong, width: hasLogo ? 1 : 1.5),
                boxShadow: JpShadows.md(p.shadow),
              ),
              child: _uploading
                  ? const Center(child: CircularProgressIndicator())
                  : hasLogo
                  ? Image.network(
                      controller.logoUrl(logoPath),
                      fit: BoxFit.cover,
                      semanticLabel: 'Logo de $businessName',
                      errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: p.textMuted),
                    )
                  : Center(child: JpAvatar(name: businessName, size: 84)),
            ),
          ),
          const SizedBox(height: JpSpacing.xxxl),
          Row(
            children: [
              Expanded(
                child: JpButton.outline(
                  label: 'Galerie',
                  icon: Icons.photo_library_outlined,
                  size: JpButtonSize.medium,
                  onPressed: _uploading ? null : () => _pick(ImageSource.gallery),
                ),
              ),
              const SizedBox(width: JpSpacing.md),
              Expanded(
                child: JpButton.outline(
                  label: 'Appareil photo',
                  icon: Icons.photo_camera_outlined,
                  size: JpButtonSize.medium,
                  onPressed: _uploading ? null : () => _pick(ImageSource.camera),
                ),
              ),
            ],
          ),
          const SizedBox(height: JpSpacing.md),
          Text('JPEG, PNG ou WebP · carré de préférence', style: JpTypography.caption.copyWith(color: p.textMuted)),
        ],
      ),
    );
  }
}
