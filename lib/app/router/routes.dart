import '../../core/permissions/permission.dart';

/// Chemins de l'application — aucune chaîne de route en dur ailleurs.
abstract final class Routes {
  static const splash = '/';

  static const login = '/auth/login';
  static const register = '/auth/register';
  static const forgotPassword = '/auth/forgot-password';
  static const resetPassword = '/auth/reset-password';

  static const onboarding = '/onboarding';
  static const selectBusiness = '/select-business';

  /// Assistant de configuration d'un commerce nouvellement créé.
  static const setup = '/setup';

  // Onglets du shell.
  static const home = '/home';
  static const catalog = '/catalog';
  static const customers = '/customers';
  static const more = '/more';

  // Écrans plein écran (hors shell).
  static const sale = '/sale';
  static const salesHistory = '/sales';
  static String saleDetail(String id) => '$salesHistory/$id';
  static const changePassword = '/more/change-password';

  // Clients.
  static String customerDetail(String id) => '$customers/$id';
  static const customerNew = '/customer-form/new';
  static String customerEdit(String id) => '/customer-form/$id';

  // Fournisseurs.
  static const suppliers = '/suppliers';
  static String supplierDetail(String id) => '$suppliers/$id';
  static const supplierNew = '/supplier-form/new';
  static String supplierEdit(String id) => '/supplier-form/$id';

  // Achats.
  static const purchases = '/purchases';
  static String purchaseDetail(String id) => '$purchases/$id';
  static String purchaseNew({String? supplierId}) =>
      supplierId == null ? '/purchase-form/new' : '/purchase-form/new?supplier=$supplierId';
  static String purchaseEdit(String id) => '/purchase-form/$id';

  // Catalogue.
  static const products = '/products';
  static String productDetail(String id) => '$catalog/product/$id';
  static String productStock(String id) => '$catalog/product/$id/stock';
  static String productNew({String? barcode}) =>
      barcode == null ? '$products/new' : '$products/new?barcode=${Uri.encodeQueryComponent(barcode)}';
  static String productEdit(String id) => '$products/$id/edit';

  /// Écrans accessibles uniquement à un utilisateur connecté **sans**
  /// entreprise active.
  static const _preWorkspace = {splash, onboarding, selectBusiness};

  static bool isAuth(String path) => path.startsWith('/auth/');

  static bool isPreWorkspace(String path) => _preWorkspace.contains(path);

  /// Permissions requises (au moins une) par préfixe de chemin. Simple
  /// confort d'UI : la base revérifie tout.
  static const _guards = <String, List<String>>{
    catalog: [Permission.productsRead],
    customers: [Permission.customersRead],
    suppliers: [Permission.suppliersRead],
    purchases: [Permission.purchasesRead],
    '/purchase-form': [Permission.purchasesCreate],
    '/supplier-form': [Permission.suppliersManage],
    '/customer-form': [Permission.customersCreate, Permission.customersManage],
    sale: [Permission.salesCreate],
    salesHistory: [Permission.salesRead, Permission.salesReadOwn],
    setup: [Permission.settingsManage],
    products: [Permission.productsCreate, Permission.productsUpdate],
  };

  static List<String>? requiredPermissions(String path) {
    for (final entry in _guards.entries) {
      if (path == entry.key || path.startsWith('${entry.key}/')) return entry.value;
    }
    return null;
  }
}
