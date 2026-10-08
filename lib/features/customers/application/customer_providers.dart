import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/payment_method.dart';
import '../../../core/formatting/business_time.dart';
import '../../../core/pagination/paged.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../../business/data/business_repository.dart';
import '../../dashboard/application/dashboard_controller.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../dashboard/domain/dashboard_models.dart';
import '../../sales/domain/sale_models.dart';
import '../data/customers_repository.dart';
import '../domain/customer_models.dart';

String? _bid(Ref ref) => ref.read(activeBusinessProvider)?.businessId;

final customerFilterProvider = NotifierProvider<CustomerFilterNotifier, CustomerFilter>(CustomerFilterNotifier.new);

class CustomerFilterNotifier extends Notifier<CustomerFilter> {
  @override
  CustomerFilter build() {
    ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    return const CustomerFilter();
  }

  void search(String query) => state = CustomerFilter(query: query.trim(), segment: state.segment);

  void segment(CustomerSegment segment) => state = CustomerFilter(query: state.query, segment: segment);
}

final customerListProvider = AsyncNotifierProvider.autoDispose<CustomerListController, Paged<Customer>>(
  CustomerListController.new,
);

class CustomerListController extends AsyncNotifier<Paged<Customer>> {
  static const pageSize = 30;

  @override
  Future<Paged<Customer>> build() async {
    final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    final filter = ref.watch(customerFilterProvider);
    if (businessId == null) return const Paged(items: [], hasMore: false);
    final items = await ref
        .read(customersRepositoryProvider)
        .fetchCustomers(businessId, filter, offset: 0, limit: pageSize);
    return Paged(items: items, hasMore: items.length == pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    final businessId = _bid(ref);
    if (current == null || businessId == null || !current.hasMore || current.loadingMore || state.isLoading) return;
    state = AsyncData(current.copyWith(loadingMore: true, loadMoreError: () => null));
    try {
      final next = await ref
          .read(customersRepositoryProvider)
          .fetchCustomers(businessId, ref.read(customerFilterProvider), offset: current.items.length, limit: pageSize);
      if (ref.mounted) state = AsyncData(current.append(next, pageSize: pageSize, keyOf: (c) => c.id));
    } catch (e) {
      if (ref.mounted) state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: () => e));
    }
  }
}

/// Total des créances (calculé en base) — seulement avec `reports.read`.
final customersDebtProvider = FutureProvider.autoDispose<int?>((ref) async {
  final business = ref.watch(activeBusinessProvider);
  if (business == null || !ref.watch(permissionsProvider).can(Permission.reportsRead)) return null;
  final today = BusinessTime.today(business.timezone);
  final summary = await ref
      .watch(dashboardRepositoryProvider)
      .fetchSummary(business.businessId, DashboardPeriod.preset(PeriodKind.today, today));
  return summary.customersDebt;
});

final customerDetailProvider = FutureProvider.autoDispose.family<Customer, String>(
  (ref, id) => ref.watch(customersRepositoryProvider).fetchCustomer(id),
);

final customerSalesProvider = FutureProvider.autoDispose.family<List<Sale>, String>((ref, id) {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  if (businessId == null) return Future.value(const []);
  return ref.watch(customersRepositoryProvider).fetchSales(businessId, id);
});

/// Relevé de compte (paginé, plus récent d'abord).
final customerStatementProvider =
    AsyncNotifierProvider.family<CustomerStatementController, Paged<CustomerTransaction>, String>(
      CustomerStatementController.new,
      isAutoDispose: true,
    );

class CustomerStatementController extends AsyncNotifier<Paged<CustomerTransaction>> {
  CustomerStatementController(this.customerId);

  final String customerId;
  static const pageSize = 30;

  @override
  Future<Paged<CustomerTransaction>> build() async {
    final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    if (businessId == null) return const Paged(items: [], hasMore: false);
    final items = await ref
        .read(customersRepositoryProvider)
        .fetchTransactions(businessId, customerId, offset: 0, limit: pageSize);
    return Paged(items: items, hasMore: items.length == pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    final businessId = _bid(ref);
    if (current == null || businessId == null || !current.hasMore || current.loadingMore || state.isLoading) return;
    state = AsyncData(current.copyWith(loadingMore: true, loadMoreError: () => null));
    try {
      final next = await ref
          .read(customersRepositoryProvider)
          .fetchTransactions(businessId, customerId, offset: current.items.length, limit: pageSize);
      if (ref.mounted) state = AsyncData(current.append(next, pageSize: pageSize, keyOf: (t) => t.id));
    } catch (e) {
      if (ref.mounted) state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: () => e));
    }
  }
}

final customerActionsProvider = Provider<CustomerActions>(CustomerActions.new);

/// Écritures clients + rafraîchissement de tout ce qui en dépend.
class CustomerActions {
  CustomerActions(this._ref);

  final Ref _ref;

  CustomersRepository get _repo => _ref.read(customersRepositoryProvider);

  String get _businessId => _bid(_ref)!;

  void _refresh([String? id]) {
    _ref.invalidate(customerListProvider);
    _ref.invalidate(customersDebtProvider);
    _ref.invalidate(dashboardProvider);
    if (id != null) {
      _ref.invalidate(customerDetailProvider(id));
      _ref.invalidate(customerStatementProvider(id));
    }
  }

  /// Création + plafond et reprise de dette facultatifs (`customers.manage`).
  Future<Customer> create({
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    int? creditLimit,
    bool setCreditLimit = false,
    int openingBalance = 0,
  }) async {
    final c = await _repo.create(_businessId, name: name, phone: phone, email: email, address: address, notes: notes);
    try {
      if (setCreditLimit) await _repo.setCreditLimit(c.id, creditLimit);
      if (openingBalance > 0) {
        await _repo.adjustBalance(c.id, amount: openingBalance, reason: 'Reprise du solde existant (cahier de crédit)');
      }
    } finally {
      _refresh(c.id);
    }
    return c;
  }

  Future<Customer> update(Customer customer, Map<String, Object?> changes) async {
    final updated = changes.isEmpty ? customer : await _repo.update(customer.id, changes);
    _refresh(customer.id);
    return updated;
  }

  Future<void> setArchived(Customer customer, {required bool archived}) async {
    await _repo.setArchived(customer.id, archived: archived);
    _refresh(customer.id);
  }

  Future<void> setCreditLimit(Customer customer, int? limit) async {
    await _repo.setCreditLimit(customer.id, limit);
    _refresh(customer.id);
  }

  /// Règlement encaissé à l'emplacement par défaut de l'entreprise.
  Future<void> recordPayment(
    Customer customer, {
    required int amount,
    required PaymentMethod method,
    String? reference,
    String? note,
  }) async {
    final locationId = await _ref.read(businessRepositoryProvider).fetchDefaultLocationId(_businessId);
    await _repo.recordPayment(
      customerId: customer.id,
      amount: amount,
      method: method,
      locationId: locationId,
      externalReference: reference,
      note: note,
    );
    _refresh(customer.id);
  }

  Future<void> adjustBalance(Customer customer, {required int amount, required String reason}) async {
    await _repo.adjustBalance(customer.id, amount: amount, reason: reason);
    _refresh(customer.id);
  }
}
