import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/errors/app_failure.dart';
import 'package:jend_pro_mobile/features/auth/data/auth_repository.dart';
import 'package:jend_pro_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repository;

  setUp(() => repository = _MockAuthRepository());

  Future<void> pumpLogin(WidgetTester tester, {ThemeData? theme}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(theme: theme ?? AppTheme.light(), home: const LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    final button = find.widgetWithText(JpButton, 'Se connecter');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('valide le formulaire avant tout appel réseau', (tester) async {
    await pumpLogin(tester);
    await tapSubmit(tester);

    expect(find.text('Saisissez votre adresse e-mail.'), findsOneWidget);
    expect(find.text('Saisissez votre mot de passe.'), findsOneWidget);
    verifyNever(
      () => repository.signIn(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    );
  });

  testWidgets('transmet les identifiants au repository', (tester) async {
    when(
      () => repository.signIn(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async {});
    await pumpLogin(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'awa@exemple.sn');
    await tester.enterText(find.byType(TextFormField).at(1), 'motdepasse');
    await tapSubmit(tester);

    verify(() => repository.signIn(email: 'awa@exemple.sn', password: 'motdepasse')).called(1);
  });

  testWidgets('affiche une erreur compréhensible', (tester) async {
    when(
      () => repository.signIn(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenThrow(const AppFailure(FailureKind.auth, 'E-mail ou mot de passe incorrect.', code: 'invalid_credentials'));
    await pumpLogin(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'awa@exemple.sn');
    await tester.enterText(find.byType(TextFormField).at(1), 'mauvais');
    await tapSubmit(tester);

    expect(find.text('E-mail ou mot de passe incorrect.'), findsOneWidget);
  });

  testWidgets('s’affiche aussi en thème sombre', (tester) async {
    await pumpLogin(tester, theme: AppTheme.dark());
    expect(find.text('Content de vous revoir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
