/// Exécution parallèle typée.
///
/// Contrairement à `(a, b).wait` (qui lève un `ParallelWaitError` opaque),
/// ces helpers relancent la **première erreur d'origine** : une `AppFailure`
/// reste une `AppFailure`, donc l'UI affiche le bon message (réseau,
/// permission…). Toutes les futures restent surveillées (aucune erreur non
/// gérée).
library;

Future<(A, B)> parallel2<A, B>(Future<A> a, Future<B> b) async {
  final r = await Future.wait<Object?>([a, b]);
  return (r[0] as A, r[1] as B);
}

Future<(A, B, C)> parallel3<A, B, C>(Future<A> a, Future<B> b, Future<C> c) async {
  final r = await Future.wait<Object?>([a, b, c]);
  return (r[0] as A, r[1] as B, r[2] as C);
}

Future<(A, B, C, D)> parallel4<A, B, C, D>(Future<A> a, Future<B> b, Future<C> c, Future<D> d) async {
  final r = await Future.wait<Object?>([a, b, c, d]);
  return (r[0] as A, r[1] as B, r[2] as C, r[3] as D);
}

Future<(A, B, C, D, E, F)> parallel6<A, B, C, D, E, F>(
  Future<A> a,
  Future<B> b,
  Future<C> c,
  Future<D> d,
  Future<E> e,
  Future<F> f,
) async {
  final r = await Future.wait<Object?>([a, b, c, d, e, f]);
  return (r[0] as A, r[1] as B, r[2] as C, r[3] as D, r[4] as E, r[5] as F);
}
