import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jend_pro_mobile/app/router/redirect.dart';
import 'package:jend_pro_mobile/app/router/routes.dart';
import 'package:jend_pro_mobile/core/permissions/permission.dart';
import 'package:jend_pro_mobile/features/auth/application/auth_session.dart';
import 'package:jend_pro_mobile/features/business/domain/workspace.dart';

const _signedIn = AuthSession(userId: 'u1', email: 'awa@exemple.sn');
const _business = BusinessMembership(
  businessId: 'b1',
  businessName: 'Boutique',
  roleCode: 'OWNER',
  roleName: 'Propriétaire',
);
const _other = BusinessMembership(businessId: 'b2', businessName: 'Dépôt', roleCode: 'CASHIER', roleName: 'Caissier');

Workspace _ready(Set<String> permissions) => Workspace(
  memberships: const [_business],
  invitations: const [],
  active: _business,
  permissions: PermissionSet(permissions),
);

String? _redirect(
  String path, {
  AuthSession auth = _signedIn,
  AsyncValue<Workspace?>? workspace,
  bool setupPending = false,
}) => resolveRedirect(
  path: path,
  auth: auth,
  workspace: workspace ?? AsyncData(_ready({Permission.productsRead, Permission.settingsManage})),
  setupPending: setupPending,
);

void main() {
  group('non connecté', () {
    test('les écrans d’authentification restent accessibles', () {
      for (final path in [Routes.login, Routes.register, Routes.forgotPassword]) {
        expect(_redirect(path, auth: const AuthSession()), isNull, reason: path);
      }
    });

    test('tout le reste renvoie vers la connexion', () {
      for (final path in [Routes.splash, Routes.home, Routes.sale, Routes.resetPassword, Routes.onboarding]) {
        expect(_redirect(path, auth: const AuthSession()), Routes.login, reason: path);
      }
    });
  });

  test('une session de récupération impose le nouveau mot de passe', () {
    const recovery = AuthSession(userId: 'u1', passwordRecovery: true);
    expect(_redirect(Routes.home, auth: recovery), Routes.resetPassword);
    expect(_redirect(Routes.resetPassword, auth: recovery), isNull);
  });

  test('contexte en chargement ou en erreur → écran de démarrage', () {
    expect(_redirect(Routes.home, workspace: const AsyncLoading()), Routes.splash);
    expect(_redirect(Routes.splash, workspace: const AsyncLoading()), isNull);
    expect(_redirect(Routes.login, workspace: AsyncError(Exception('x'), StackTrace.empty)), Routes.splash);
  });

  test('aucune entreprise → onboarding', () {
    const ws = AsyncData<Workspace?>(Workspace(memberships: [], invitations: []));
    expect(_redirect(Routes.home, workspace: ws), Routes.onboarding);
    expect(_redirect(Routes.onboarding, workspace: ws), isNull);
  });

  test('plusieurs entreprises sans choix → sélection', () {
    const ws = AsyncData<Workspace?>(Workspace(memberships: [_business, _other], invitations: []));
    expect(_redirect(Routes.home, workspace: ws), Routes.selectBusiness);
    expect(_redirect(Routes.selectBusiness, workspace: ws), isNull);
  });

  test('contexte prêt : les écrans d’entrée renvoient vers l’accueil', () {
    for (final path in [Routes.splash, Routes.login, Routes.onboarding, Routes.selectBusiness]) {
      expect(_redirect(path), Routes.home, reason: path);
    }
    expect(_redirect(Routes.home), isNull);
    expect(_redirect(Routes.more), isNull);
  });

  test('les écrans protégés exigent leur permission', () {
    // Profil STOCK_MANAGER : ni caisse ni clients.
    final stockManager = AsyncData<Workspace?>(_ready({Permission.productsRead, Permission.inventoryRead}));
    expect(_redirect(Routes.sale, workspace: stockManager), Routes.home);
    expect(_redirect(Routes.customers, workspace: stockManager), Routes.home);
    expect(_redirect(Routes.catalog, workspace: stockManager), isNull);

    // Profil CASHIER : caisse et clients.
    final cashier = AsyncData<Workspace?>(
      _ready({Permission.productsRead, Permission.salesCreate, Permission.customersRead}),
    );
    expect(_redirect(Routes.sale, workspace: cashier), isNull);
    expect(_redirect(Routes.customers, workspace: cashier), isNull);
  });

  test('commerce nouvellement créé → assistant de configuration', () {
    expect(_redirect(Routes.home, setupPending: true), Routes.setup);
    expect(_redirect(Routes.onboarding, setupPending: true), Routes.setup);
    expect(_redirect(Routes.setup, setupPending: true), isNull);
    // Une fois terminé, l'accueil est accessible.
    expect(_redirect(Routes.home), isNull);
  });

  test('l’assistant exige settings.manage', () {
    final cashier = AsyncData<Workspace?>(_ready({Permission.salesCreate}));
    expect(_redirect(Routes.setup, workspace: cashier), Routes.home);
  });

  test('création / modification de produit selon les permissions', () {
    final stockManager = AsyncData<Workspace?>(_ready({Permission.productsRead, Permission.productsCreate}));
    final cashier = AsyncData<Workspace?>(_ready({Permission.productsRead, Permission.salesCreate}));
    expect(_redirect(Routes.productNew(), workspace: stockManager), isNull);
    expect(_redirect(Routes.productNew(), workspace: cashier), Routes.home);
    expect(_redirect(Routes.productEdit('p1'), workspace: cashier), Routes.home);
    expect(_redirect(Routes.productDetail('p1'), workspace: cashier), isNull, reason: 'lecture autorisée');
  });
}
