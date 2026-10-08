/// Page de résultats chargée progressivement (listes longues : catalogue,
/// stock, historiques). Jamais de table entière en mémoire.
class Paged<T> {
  const Paged({required this.items, required this.hasMore, this.loadingMore = false, this.loadMoreError});

  final List<T> items;
  final bool hasMore;
  final bool loadingMore;
  final Object? loadMoreError;

  Paged<T> copyWith({List<T>? items, bool? hasMore, bool? loadingMore, Object? Function()? loadMoreError}) => Paged(
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: loadMoreError != null ? loadMoreError() : this.loadMoreError,
  );

  /// Ajoute une page en dédupliquant (des insertions entre deux pages
  /// peuvent décaler les offsets).
  Paged<T> append(List<T> next, {required int pageSize, required Object Function(T) keyOf}) {
    final seen = {for (final i in items) keyOf(i)};
    return Paged(items: [...items, ...next.where((i) => seen.add(keyOf(i)))], hasMore: next.length == pageSize);
  }
}
