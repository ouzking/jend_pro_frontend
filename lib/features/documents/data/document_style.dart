import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

/// Polices et marque utilisées dans les PDF.
///
/// - [DocumentStyle.app] : Roboto intégrée à l'app (Unicode complet :
///   apostrophes, tirets, « ñ » du wolof…) + monogramme JËND PRO ;
/// - [DocumentStyle.standard] : polices standard PDF (Helvetica, Latin-1),
///   sans fichier à charger (tests, secours).
class DocumentStyle {
  const DocumentStyle({
    required this.base,
    required this.medium,
    required this.bold,
    required this.unicode,
    this.brandMark,
  });

  factory DocumentStyle.standard() => DocumentStyle(
    base: pw.Font.helvetica(),
    medium: pw.Font.helveticaBold(),
    bold: pw.Font.helveticaBold(),
    unicode: false,
  );

  /// Charge Roboto et le monogramme depuis les ressources de l'app ; se
  /// rabat sur [DocumentStyle.standard] si un fichier manque.
  static Future<DocumentStyle> app([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    try {
      final (regular, medium, bold) = (
        await b.load('assets/fonts/pdf/Roboto-Regular.ttf'),
        await b.load('assets/fonts/pdf/Roboto-Medium.ttf'),
        await b.load('assets/fonts/pdf/Roboto-Bold.ttf'),
      );
      pw.ImageProvider? mark;
      try {
        mark = pw.MemoryImage((await b.load('assets/branding/app_icon.png')).buffer.asUint8List());
      } catch (_) {
        mark = null;
      }
      return DocumentStyle(
        base: pw.Font.ttf(regular),
        medium: pw.Font.ttf(medium),
        bold: pw.Font.ttf(bold),
        unicode: true,
        brandMark: mark,
      );
    } catch (_) {
      return DocumentStyle.standard();
    }
  }

  final pw.Font base;
  final pw.Font medium;
  final pw.Font bold;

  /// `true` : la police couvre l'Unicode courant (pas de conversion Latin-1).
  final bool unicode;

  /// Monogramme JËND PRO (pied de page « Propulsé par »).
  final pw.ImageProvider? brandMark;

  pw.ThemeData get theme => pw.ThemeData.withFont(base: base, bold: bold, fontFallback: [medium]);
}
