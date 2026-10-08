import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../design_system/design_system.dart';

/// Ouvre le scanner plein écran ; renvoie le code lu (ou saisi à la main),
/// `null` si l'utilisateur annule. Réutilisé par le catalogue et la caisse.
Future<String?> scanBarcode(BuildContext context, {String title = 'Scanner un code-barres'}) => Navigator.of(
  context,
  rootNavigator: true,
).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => BarcodeScannerScreen(title: title)));

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key, required this.title});

  final String title;

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
  );
  bool _done = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final value = capture.barcodes.map((b) => b.rawValue).nonNulls.firstOrNull?.trim();
    if (value == null || value.isEmpty) return;
    _done = true;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(value);
  }

  Future<void> _manualEntry() async {
    final controller = TextEditingController();
    final code = await JpOverlays.sheet<String>(
      context,
      title: 'Saisir le code',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          JpTextField(
            controller: controller,
            hint: 'Ex. 6001234567890',
            keyboardType: TextInputType.number,
            autofocus: true,
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
          const SizedBox(height: JpSpacing.lg),
          Builder(
            builder: (sheetContext) =>
                JpButton(label: 'Valider', onPressed: () => Navigator.of(sheetContext).pop(controller.text.trim())),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code != null && code.isNotEmpty && mounted) Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    const frame = Size(280, 180);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => ColoredBox(
              color: JpColors.forest975,
              child: SafeArea(
                child: JpEmptyState(
                  icon: Icons.no_photography_outlined,
                  tone: JpTone.warning,
                  title: 'Caméra indisponible',
                  message: error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Autorisez l’accès à l’appareil photo dans les réglages du téléphone, ou saisissez le code.'
                      : 'Impossible d’ouvrir la caméra. Saisissez le code à la main.',
                  actionLabel: 'Saisir le code',
                  onAction: _manualEntry,
                ),
              ),
            ),
          ),
          // Voile sombre avec fenêtre de visée.
          IgnorePointer(
            child: CustomPaint(
              painter: _ViewfinderPainter(frame: frame, color: JpColors.mint400),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: JpSpacing.sm, vertical: JpSpacing.xs),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Fermer',
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: JpTypography.titleSmall.copyWith(color: Colors.white),
                        ),
                      ),
                      IconButton(
                        tooltip: _torch ? 'Éteindre la lampe' : 'Allumer la lampe',
                        icon: Icon(
                          _torch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () async {
                          await _controller.toggleTorch();
                          if (mounted) setState(() => _torch = !_torch);
                        },
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(height: frame.height + JpSpacing.xxxl * 2),
                Text(
                  'Placez le code-barres dans le cadre',
                  style: JpTypography.body.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(JpSpacing.xl),
                  child: TextButton.icon(
                    onPressed: _manualEntry,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    icon: const Icon(Icons.keyboard_alt_outlined),
                    label: const Text('Saisir le code à la main'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({required this.frame, required this.color});

  final Size frame;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: frame.width, height: frame.height);
    final window = RRect.fromRectAndRadius(rect, const Radius.circular(JpRadius.lg));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(window)),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    // Coins de visée.
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const l = 28.0;
    for (final (corner, dx, dy) in [
      (rect.topLeft, 1.0, 1.0),
      (rect.topRight, -1.0, 1.0),
      (rect.bottomLeft, 1.0, -1.0),
      (rect.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(corner, corner.translate(l * dx, 0), paint);
      canvas.drawLine(corner, corner.translate(0, l * dy), paint);
    }
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => old.frame != frame || old.color != color;
}
