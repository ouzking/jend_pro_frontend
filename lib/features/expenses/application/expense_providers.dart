import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/business_time.dart';
import '../../../core/pagination/paged.dart';
import '../../../core/permissions/permission.dart';
import '../../business/application/workspace_controller.dart';
import '../../dashboard/application/dashboard_controller.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../dashboard/domain/dashboard_models.dart';
import '../data/expenses_repository.dart';
import '../domain/expense_models.dart';

String? _bid(Ref ref) => ref.read(activeBusinessProvider)?.businessId;

/// Mois affiché + filtre catégorie.
class ExpenseView {
  const ExpenseView({required this.month, this.categoryId});

  final ExpenseMonth month;
  final String? categoryId;

  @override
  bool operator ==(Object other) => other is ExpenseView && other.month == month && other.categoryId == categoryId;

  @override
  int get hashCode => Object.hash(month, categoryId);
}

final expenseViewProvider = NotifierProvider<ExpenseViewNotifier, ExpenseView>(ExpenseViewNotifier.new);

class ExpenseViewNotifier extends Notifier<ExpenseView> {
  ExpenseMonth get _current =>
      ExpenseMonth.of(BusinessTime.today(ref.read(activeBusinessProvider)?.timezone ?? 'Africa/Dakar'));

  @override
  ExpenseView build() {
    ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    return ExpenseView(month: _current);
  }

  bool get canGoNext => _current.isAfter(state.month);

  void previous() => state = ExpenseView(month: state.month.previous, categoryId: state.categoryId);

  void next() {
    if (canGoNext) state = ExpenseView(month: state.month.next, categoryId: state.categoryId);
  }

  void category(String? id) => state = ExpenseView(month: state.month, categoryId: id);
}

final expenseCategoriesProvider = FutureProvider.autoDispose<List<ExpenseCategory>>((ref) {
  final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
  if (businessId == null) return Future.value(const []);
  return ref.watch(expensesRepositoryProvider).fetchCategories(businessId);
});

/// Total du mois, calculé par le serveur (`reports.read`), sinon `null`.
final expenseMonthTotalProvider = FutureProvider.autoDispose<int?>((ref) async {
  final business = ref.watch(activeBusinessProvider);
  final view = ref.watch(expenseViewProvider);
  if (business == null || !ref.watch(permissionsProvider).can(Permission.reportsRead)) return null;
  final summary = await ref
      .watch(dashboardRepositoryProvider)
      .fetchSummary(business.businessId, DashboardPeriod.custom(view.month.first, view.month.last));
  return summary.expenses;
});

final expenseListProvider = AsyncNotifierProvider.autoDispose<ExpenseListController, Paged<Expense>>(
  ExpenseListController.new,
);

class ExpenseListController extends AsyncNotifier<Paged<Expense>> {
  static const pageSize = 40;

  Future<List<Expense>> _fetch(String businessId, ExpenseView v, int offset) => ref
      .read(expensesRepositoryProvider)
      .fetchExpenses(
        businessId,
        from: v.month.first,
        to: v.month.last,
        categoryId: v.categoryId,
        offset: offset,
        limit: pageSize,
      );

  @override
  Future<Paged<Expense>> build() async {
    final businessId = ref.watch(activeBusinessProvider.select((b) => b?.businessId));
    final view = ref.watch(expenseViewProvider);
    if (businessId == null) return const Paged(items: [], hasMore: false);
    final items = await _fetch(businessId, view, 0);
    return Paged(items: items, hasMore: items.length == pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    final businessId = _bid(ref);
    if (current == null || businessId == null || !current.hasMore || current.loadingMore || state.isLoading) return;
    state = AsyncData(current.copyWith(loadingMore: true, loadMoreError: () => null));
    try {
      final next = await _fetch(businessId, ref.read(expenseViewProvider), current.items.length);
      if (ref.mounted) state = AsyncData(current.append(next, pageSize: pageSize, keyOf: (e) => e.id));
    } catch (e) {
      if (ref.mounted) state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: () => e));
    }
  }
}

final expenseDetailProvider = FutureProvider.autoDispose.family<Expense, String>(
  (ref, id) => ref.watch(expensesRepositoryProvider).fetchExpense(id),
);

/// URL signée du justificatif (courte durée ; recalculée à chaque ouverture).
final receiptUrlProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, path) => ref.watch(expensesRepositoryProvider).signedReceiptUrl(path),
);

final expenseActionsProvider = Provider<ExpenseActions>(ExpenseActions.new);

class ExpenseActions {
  ExpenseActions(this._ref);

  final Ref _ref;

  ExpensesRepository get _repo => _ref.read(expensesRepositoryProvider);

  String get _businessId => _bid(_ref)!;

  void _refresh([String? id]) {
    _ref.invalidate(expenseListProvider);
    _ref.invalidate(expenseMonthTotalProvider);
    _ref.invalidate(dashboardProvider);
    if (id != null) _ref.invalidate(expenseDetailProvider(id));
  }

  Future<String> uploadReceipt(Uint8List bytes, String mimeType) =>
      _repo.uploadReceipt(_businessId, bytes, mimeType: mimeType);

  Future<Expense> create(ExpenseInput input) async {
    final e = await _repo.create(_businessId, input);
    _refresh(e.id);
    return e;
  }

  Future<Expense> update(Expense previous, ExpenseInput input) async {
    final e = await _repo.update(previous.id, input);
    if (previous.receiptPath != null && previous.receiptPath != input.receiptPath) {
      await _repo.deleteReceipt(previous.receiptPath!);
    }
    _refresh(e.id);
    return e;
  }

  Future<void> delete(Expense e) async {
    await _repo.delete(e.id);
    _refresh(e.id);
  }

  Future<ExpenseCategory> createCategory(String name) async {
    final c = await _repo.createCategory(_businessId, name);
    _ref.invalidate(expenseCategoriesProvider);
    return c;
  }
}
