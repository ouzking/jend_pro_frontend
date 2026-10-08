import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../design_system/design_system.dart';

/// Image choisie, prête à envoyer (format accepté par les buckets).
class PickedImage {
  const PickedImage(this.bytes, this.mimeType);

  final Uint8List bytes;
  final String mimeType;
}

/// Propose galerie / appareil photo, redimensionne sur l'appareil (réseau
/// mobile) et vérifie format et poids. Affiche lui-même les refus ; renvoie
/// `null` si rien n'est retenu.
Future<PickedImage?> pickImage(
  BuildContext context, {
  required int maxBytes,
  double maxDimension = 1024,
  String title = 'Ajouter une photo',

  /// Source imposée (sinon l'utilisateur choisit galerie ou appareil photo).
  ImageSource? source,
}) async {
  source ??= await JpOverlays.sheet<ImageSource>(
    context,
    title: title,
    child: Builder(
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          JpButton.outline(
            label: 'Choisir dans la galerie',
            icon: Icons.photo_library_outlined,
            onPressed: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
          const SizedBox(height: JpSpacing.md),
          JpButton.outline(
            label: 'Prendre une photo',
            icon: Icons.photo_camera_outlined,
            onPressed: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;

  final XFile? file;
  try {
    file = await ImagePicker().pickImage(
      source: source,
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      imageQuality: 82,
    );
  } catch (_) {
    if (context.mounted) {
      JpOverlays.toast(context, 'Accès à la caméra ou aux photos refusé.', tone: JpTone.warning);
    }
    return null;
  }
  if (file == null) return null;

  final bytes = await file.readAsBytes();
  final name = file.name.toLowerCase();
  final mime =
      file.mimeType ??
      (name.endsWith('.png')
          ? 'image/png'
          : name.endsWith('.webp')
          ? 'image/webp'
          : 'image/jpeg');
  if (!context.mounted) return null;
  if (!{'image/jpeg', 'image/png', 'image/webp'}.contains(mime)) {
    JpOverlays.toast(context, 'Format non pris en charge. Choisissez une photo JPEG ou PNG.', tone: JpTone.warning);
    return null;
  }
  if (bytes.length > maxBytes) {
    JpOverlays.toast(
      context,
      'Image trop lourde (${(maxBytes / (1024 * 1024)).round()} Mo maximum).',
      tone: JpTone.warning,
    );
    return null;
  }
  return PickedImage(bytes, mime);
}
