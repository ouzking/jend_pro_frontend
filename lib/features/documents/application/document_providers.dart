import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/storage/preferences.dart';
import '../../business/application/workspace_controller.dart';
import '../../business/data/business_repository.dart';
import '../domain/document_issuer.dart';

/// En-tête des documents de l'entreprise active (fiche + logo). Un logo
/// illisible ou indisponible n'empêche jamais d'éditer un reçu.
final documentIssuerProvider = FutureProvider.autoDispose<DocumentIssuer>((ref) async {
  final business = ref.watch(activeBusinessProvider);
  if (business == null) return const DocumentIssuer(name: 'JËND PRO');
  final repo = ref.watch(businessRepositoryProvider);
  final profile = await repo.fetchProfile(business.businessId);
  pw.ImageProvider? logo;
  if (profile.logoPath != null) {
    try {
      // Passe par le décodeur Flutter : JPEG, PNG et WebP acceptés.
      logo = await flutterImageProvider(MemoryImage(await repo.downloadLogo(profile.logoPath!)));
    } catch (_) {
      logo = null;
    }
  }
  return DocumentIssuer.fromProfile(profile, currency: business.currencyCode, logo: logo);
});

/// Largeur du papier de l'imprimante thermique (réglage propre à l'appareil).
final ticketWidthProvider = NotifierProvider<TicketWidthNotifier, TicketWidth>(TicketWidthNotifier.new);

class TicketWidthNotifier extends Notifier<TicketWidth> {
  static const _key = 'ticket_width';

  @override
  TicketWidth build() {
    final stored = ref.read(sharedPreferencesProvider).getString(_key);
    return TicketWidth.values.firstWhere((w) => w.name == stored, orElse: () => TicketWidth.mm58);
  }

  void set(TicketWidth width) {
    state = width;
    ref.read(sharedPreferencesProvider).setString(_key, width.name);
  }
}

final documentActionsProvider = Provider<DocumentActions>((_) => const DocumentActions());

/// Impression (service d'impression du système : Wi-Fi, Bluetooth via une
/// application de pilote, PDF) et partage (WhatsApp, e-mail…).
class DocumentActions {
  const DocumentActions();

  Future<bool> print(Uint8List bytes, {required String name, PdfPageFormat format = PdfPageFormat.a4}) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: name, format: format);

  Future<bool> share(Uint8List bytes, {required String filename}) =>
      Printing.sharePdf(bytes: bytes, filename: filename);
}

/// Nom de fichier sûr : `Recu-V-000123.pdf`.
String documentFilename(String prefix, String reference) =>
    '$prefix-${reference.replaceAll(RegExp(r'[^A-Za-z0-9\-]+'), '-')}.pdf';
