import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jend_pro_mobile/core/design_system/design_system.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/core/storage/preferences.dart';
import 'package:jend_pro_mobile/features/business/application/workspace_controller.dart';
import 'package:jend_pro_mobile/features/business/domain/workspace.dart';
import 'package:jend_pro_mobile/features/notifications/presentation/large_sale_threshold_sheet.dart';
import 'package:jend_pro_mobile/features/settings/application/settings_providers.dart';
import 'package:jend_pro_mobile/features/settings/domain/settings_models.dart';
import 'package:jend_pro_mobile/features/settings/presentation/business_settings_screen.dart';
import 'package:jend_pro_mobile/features/settings/presentation/locations_screen.dart';
import 'package:jend_pro_mobile/features/settings/presentation/subscription_screen.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Actions extends Mock implements SettingsActions {}

class _Workspace extends WorkspaceController {
  _Workspace(this.value);

  final Workspace value;

  @override
  Future<Workspace?> build() async => value;
}

const _settings = BusinessSettings(
  id: 'b1',
  name: 'Boutique Ndèye',
  timezone: 'Africa/Dakar',
  currencyCode: 'XOF',
  allowNegativeStock: false,
  city: 'Dakar',
);

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(LocationKind.store);
    return initializeDateFormatting('fr');
  });

  test('quota de plan : limites et utilisation', () {
    final limits = PlanQuota.fromLimits({'max_members': 3, 'max_products': null, 'max_locations': 1});
    expect((limits.members, limits.products, limits.locations), (3, null, 1));
    final usage = PlanQuota.fromUsage({'members': 2, 'products': 40, 'locations': 1});
    expect(usage.products, 40);
    expect(PlanQuota.fromLimits(null).members, isNull);
  });

  Future<void> pump(WidgetTester t, Widget home, List overrides, {Workspace? workspace}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          activeBusinessProvider.overrideWithValue(null),
          if (workspace != null) workspaceProvider.overrideWith(() => _Workspace(workspace)),
          permissionsProvider.overrideWithValue(const PermissionSet({Permission.settingsManage})),
          ...overrides.cast(),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('commerce : seules les valeurs modifiées sont envoyées', (t) async {
    final actions = _Actions();
    when(() => actions.updateBusiness(any())).thenAnswer((_) async => _settings);
    await pump(t, const BusinessSettingsScreen(), [
      businessSettingsProvider.overrideWith((ref) async => _settings),
      largeSaleThresholdProvider.overrideWith((ref) async => 50000),
      settingsActionsProvider.overrideWithValue(actions),
    ]);
    expect(find.textContaining('À partir de 50'), findsOneWidget);
    await t.enterText(find.widgetWithText(JpTextField, 'Ville'), 'Thiès');
    await t.enterText(find.widgetWithText(JpTextField, 'NINEA'), ' 0123456 2G3 ');
    await t.ensureVisible(find.text('Autoriser le stock négatif'));
    await t.pumpAndSettle();
    await t.tap(find.text('Autoriser le stock négatif'));
    await t.pumpAndSettle();
    await t.tap(find.text('Autoriser'));
    await t.pumpAndSettle();
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    final changes = verify(() => actions.updateBusiness(captureAny())).captured.single as Map<String, Object?>;
    expect(changes, {'city': 'Thiès', 'ninea': '0123456 2G3', 'allow_negative_stock': true});
  });

  testWidgets('emplacements : principal non archivable, archivés à part', (t) async {
    await pump(t, const LocationsScreen(), [
      locationDetailsProvider.overrideWith(
        (ref) async => const [
          LocationDetail(id: 'l1', name: 'Boutique', kind: LocationKind.store, isDefault: true, archived: false),
          LocationDetail(
            id: 'l2',
            name: 'Dépôt Pikine',
            kind: LocationKind.warehouse,
            isDefault: false,
            archived: false,
          ),
          LocationDetail(id: 'l3', name: 'Kiosque', kind: LocationKind.store, isDefault: false, archived: true),
        ],
      ),
    ]);
    expect(find.text('Principal'), findsOneWidget);
    expect(find.text('ARCHIVÉS'), findsOneWidget);
    await t.tap(find.text('Boutique').first);
    await t.pumpAndSettle();
    expect(find.text('Archiver'), findsNothing);
    expect(find.textContaining('ne peut pas être archivé'), findsOneWidget);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    await t.tap(find.text('Dépôt Pikine'));
    await t.pumpAndSettle();
    expect(find.text('Archiver'), findsOneWidget);
  });

  testWidgets('abonnement : statut, utilisation, formules', (t) async {
    await pump(
      t,
      const SubscriptionScreen(),
      [
        subscriptionPlansProvider.overrideWith(
          (ref) async => const [
            SubscriptionPlan(
              code: 'FREE',
              name: 'Gratuit',
              price: 0,
              currencyCode: 'XOF',
              billingPeriod: 'MONTHLY',
              limits: PlanQuota(members: 2, products: 100, locations: 1),
            ),
            SubscriptionPlan(
              code: 'PRO',
              name: 'Pro',
              price: 10000,
              currencyCode: 'XOF',
              billingPeriod: 'MONTHLY',
              limits: PlanQuota(members: 10, products: 5000, locations: 3),
            ),
          ],
        ),
      ],
      workspace: Workspace(
        memberships: const [],
        invitations: const [],
        subscription: SubscriptionStatus(
          planCode: 'PRO',
          planName: 'Pro',
          status: 'TRIALING',
          isRestricted: false,
          trialEndsAt: DateTime.now().add(const Duration(days: 10)),
          limits: const PlanQuota(members: 10, products: 5000, locations: 3),
          usage: const PlanQuota(members: 2, products: 40, locations: 3),
        ),
      ),
    );
    expect(find.text('Formule Pro'), findsOneWidget);
    expect(find.text('Période d’essai'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('Votre formule'), findsOneWidget);
    expect(find.text('Gratuit'), findsWidgets);
  });

  testWidgets('apparence mémorisée', (t) async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(container.read(themeModeProvider), ThemeMode.dark);
    container.read(themeModeProvider.notifier).set(ThemeMode.light);
    expect(prefs.getString('theme_mode'), 'light');
  });
}
