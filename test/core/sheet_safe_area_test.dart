import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/media/image_picking.dart';

/// Les feuilles du bas ne doivent jamais passer sous la barre de navigation
/// Android (boutons ou gestes), ni sous le clavier.
void main() {
  const navBar = 48.0; // hauteur logique de la barre à 3 boutons
  const dpr = 2.75;

  Future<void> openPhotoSheet(WidgetTester t, {double keyboard = 0}) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = dpr;
    t.view.padding = const FakeViewPadding(top: 24 * dpr, bottom: navBar * dpr);
    t.view.viewPadding = const FakeViewPadding(top: 24 * dpr, bottom: navBar * dpr);
    t.view.viewInsets = FakeViewPadding(bottom: keyboard * dpr);
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => pickImage(context, maxBytes: 1024),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
  }

  testWidgets('« Prendre une photo » reste au-dessus de la barre de navigation', (t) async {
    await openPhotoSheet(t);
    final screenHeight = 2340 / dpr;
    final button = t.getRect(find.widgetWithText(JpButton, 'Prendre une photo'));
    expect(button.bottom, lessThanOrEqualTo(screenHeight - navBar), reason: 'masqué par la barre de navigation');
    expect(find.widgetWithText(JpButton, 'Choisir dans la galerie'), findsOneWidget);
  });

  testWidgets('clavier ouvert : la feuille remonte au-dessus du clavier', (t) async {
    await openPhotoSheet(t, keyboard: 300);
    final screenHeight = 2340 / dpr;
    final button = t.getRect(find.widgetWithText(JpButton, 'Prendre une photo'));
    expect(button.bottom, lessThanOrEqualTo(screenHeight - 300));
  });
}
