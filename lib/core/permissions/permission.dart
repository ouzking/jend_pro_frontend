/// Catalogue des permissions du backend (roles-and-permissions.md §2).
///
/// Sert **uniquement** à adapter l'UI (masquer / griser). La base de données
/// reste seule juge : RLS et RPC revérifient chaque action.
abstract final class Permission {
  static const settingsManage = 'settings.manage';
  static const subscriptionManage = 'subscription.manage';
  static const membersRead = 'members.read';
  static const membersManage = 'members.manage';
  static const employeesRead = 'employees.read';
  static const employeesManage = 'employees.manage';
  static const productsRead = 'products.read';
  static const productsCreate = 'products.create';
  static const productsUpdate = 'products.update';
  static const productsDelete = 'products.delete';
  static const productsReadCost = 'products.read_cost';
  static const categoriesManage = 'categories.manage';
  static const inventoryRead = 'inventory.read';
  static const inventoryAdjust = 'inventory.adjust';
  static const inventoryTransfer = 'inventory.transfer';
  static const customersRead = 'customers.read';
  static const customersCreate = 'customers.create';
  static const customersManage = 'customers.manage';
  static const customersPayments = 'customers.payments';
  static const suppliersRead = 'suppliers.read';
  static const suppliersManage = 'suppliers.manage';
  static const purchasesRead = 'purchases.read';
  static const purchasesCreate = 'purchases.create';
  static const purchasesReceive = 'purchases.receive';
  static const purchasesPayments = 'purchases.payments';
  static const purchasesCancel = 'purchases.cancel';
  static const salesRead = 'sales.read';
  static const salesReadOwn = 'sales.read_own';
  static const salesCreate = 'sales.create';
  static const salesDiscount = 'sales.discount';
  static const salesCredit = 'sales.credit';
  static const salesCancel = 'sales.cancel';
  static const expensesRead = 'expenses.read';
  static const expensesCreate = 'expenses.create';
  static const expensesManage = 'expenses.manage';
  static const reportsRead = 'reports.read';
  static const auditRead = 'audit.read';
}

/// Ensemble effectif des permissions de l'utilisateur dans l'entreprise active
/// (déjà filtré par le mode restreint côté serveur).
class PermissionSet {
  const PermissionSet(this._codes);

  const PermissionSet.empty() : _codes = const {};

  final Set<String> _codes;

  bool can(String permission) => _codes.contains(permission);

  bool canAny(Iterable<String> permissions) => permissions.any(_codes.contains);

  bool get canSeeSales => canAny(const [Permission.salesRead, Permission.salesReadOwn]);

  bool get isEmpty => _codes.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is PermissionSet && other._codes.length == _codes.length && other._codes.containsAll(_codes);

  @override
  int get hashCode => Object.hashAllUnordered(_codes);
}
