import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';

Widget _host(Widget child, ThemeData theme) => MaterialApp(
  theme: theme,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  for (final (name, theme) in [('clair', AppTheme.light()), ('sombre', AppTheme.dark())]) {
    group('thème $name', () {
      testWidgets('les jetons sont exposés via le thème', (tester) async {
        late JpPalette palette;
        await tester.pumpWidget(
          _host(
            Builder(
              builder: (context) {
                palette = context.palette;
                return const SizedBox();
              },
            ),
            theme,
          ),
        );
        expect(palette.brand, theme.colorScheme.primary);
      });

      testWidgets('JpButton : clic, chargement et désactivation', (tester) async {
        var taps = 0;
        await tester.pumpWidget(_host(JpButton(label: 'Valider', onPressed: () => taps++), theme));
        await tester.tap(find.text('Valider'));
        expect(taps, 1);

        await tester.pumpWidget(_host(JpButton(label: 'Valider', isLoading: true, onPressed: () => taps++), theme));
        await tester.tap(find.byType(JpButton), warnIfMissed: false);
        expect(taps, 1);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('JpButton : toutes les variantes se construisent', (tester) async {
        for (final variant in JpButtonVariant.values) {
          await tester.pumpWidget(_host(JpButton(label: variant.name, variant: variant, onPressed: () {}), theme));
          expect(tester.takeException(), isNull, reason: variant.name);
        }
      });

      testWidgets('JpSkeletonList : utilisable dans une liste défilante', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: CustomScrollView(slivers: [SliverToBoxAdapter(child: JpSkeletonList(itemCount: 3))]),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('JpButton : cible tactile ≥ 48 dp', (tester) async {
        await tester.pumpWidget(
          _host(JpButton(label: 'OK', size: JpButtonSize.medium, expand: false, onPressed: () {}), theme),
        );
        final size = tester.getSize(find.byType(JpButton));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
      });

      testWidgets('JpErrorState : message traduit et réessayer', (tester) async {
        var retried = false;
        await tester.pumpWidget(
          _host(
            JpErrorState(
              error: const AppFailure(FailureKind.network, 'Connexion internet indisponible.'),
              onRetry: () => retried = true,
            ),
            theme,
          ),
        );
        expect(find.text('Pas de connexion'), findsOneWidget);
        await tester.tap(find.text('Réessayer'));
        expect(retried, isTrue);
      });

      testWidgets('JpErrorState : pas de « Réessayer » sur un refus de permission', (tester) async {
        await tester.pumpWidget(
          _host(JpErrorState(error: const AppFailure(FailureKind.permission, 'Non autorisé.'), onRetry: () {}), theme),
        );
        expect(find.text('Réessayer'), findsNothing);
      });

      testWidgets('JpAmount annonce le montant complet', (tester) async {
        await tester.pumpWidget(_host(const JpAmount(1500), theme));
        expect(find.bySemanticsLabel(RegExp(r'1.500 FCFA')), findsOneWidget);
      });
    });
  }
}
