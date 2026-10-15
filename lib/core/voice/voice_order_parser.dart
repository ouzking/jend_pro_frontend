/// Compréhension d'une commande dictée (« deux sacs de riz et une huile cinq
/// litres », « ñaar riz ak benn huile ») : découpage en lignes « quantité +
/// article », puis rapprochement avec le catalogue. Français et wolof, avec
/// les transcriptions approximatives que produit une reconnaissance vocale
/// réglée en français (« niaar », « gnett », « diouroum »…).
///
/// Code pur (sans Flutter) : entièrement testable.
library;

import 'dart:math' as math;

/// Une demande isolée dans la phrase : quantité (1 par défaut) + mots décrivant
/// l'article.
class VoiceItem {
  const VoiceItem({required this.quantity, required this.words, required this.raw, this.explicitQuantity = true});

  final num quantity;

  /// Mots utiles (normalisés), sans articles ni liaisons.
  final List<String> words;

  /// Extrait de la phrase d'origine (affiché si l'article n'est pas trouvé).
  final String raw;

  /// `false` si aucune quantité n'a été dite (1 par défaut).
  final bool explicitQuantity;

  String get query => words.join(' ');

  @override
  String toString() => 'VoiceItem($quantity × $query)';
}

/// Article candidat (sous-ensemble neutre d'un produit du catalogue).
class VoiceCandidate {
  const VoiceCandidate({required this.id, required this.name});

  final String id;
  final String name;
}

/// Résultat du rapprochement d'une demande avec le catalogue.
class VoiceMatch {
  const VoiceMatch({required this.item, required this.ranked});

  final VoiceItem item;

  /// Candidats triés par pertinence (score de 0 à 1), meilleurs d'abord.
  final List<(VoiceCandidate, double)> ranked;

  /// Au moins environ la moitié de la demande retrouvée dans le nom : un mot
  /// mal reconnu (« vitalé ») n'empêche pas de proposer l'article.
  static const threshold = 0.45;

  VoiceCandidate? get best => ranked.isNotEmpty && ranked.first.$2 >= threshold ? ranked.first.$1 : null;

  /// Deux candidats presque à égalité : à faire vérifier.
  bool get ambiguous => best != null && ranked.length > 1 && ranked.first.$2 - ranked[1].$2 < 0.08;
}

abstract final class VoiceOrderParser {
  // ------------------------------------------------------------ Normalisation

  static const _accents = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'ã': 'a',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'í': 'i',
    'ô': 'o',
    'ö': 'o',
    'ó': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ú': 'u',
    'ÿ': 'y',
    'ñ': 'gn',
    'ŋ': 'ng',
    'œ': 'oe',
    'æ': 'ae',
    '’': "'",
    '‘': "'",
  };

  /// Minuscules, sans accents (ñ → gn), ponctuation → espaces (sauf décimales).
  static String normalize(String input) {
    final b = StringBuffer();
    for (final ch in input.toLowerCase().split('')) {
      b.write(_accents[ch] ?? ch);
    }
    var s = b.toString();
    s = s.replaceAllMapped(RegExp(r'(\d)[.,](\d)'), (m) => '${m[1]}#${m[2]}'); // 2,5 → 2#5
    s = s.replaceAll(RegExp(r"[\-_/']"), ' ');
    s = s.replaceAll(RegExp(r'[,;:!?.]'), ' , ');
    s = s.replaceAll('#', '.');
    s = s.replaceAllMapped(RegExp(r'(\d)([a-z])'), (m) => '${m[1]} ${m[2]}'); // 5l → 5 l
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Forme de comparaison d'un mot : sans pluriel simple.
  static String stem(String w) {
    if (w.length > 3 && (w.endsWith('s') || w.endsWith('x'))) return w.substring(0, w.length - 1);
    return w;
  }

  // ------------------------------------------------------------ Nombres

  static const _fr = {
    'zero': 0,
    'un': 1,
    'une': 1,
    'deux': 2,
    'trois': 3,
    'quatre': 4,
    'cinq': 5,
    'six': 6,
    'sept': 7,
    'huit': 8,
    'neuf': 9,
    'dix': 10,
    'onze': 11,
    'douze': 12,
    'treize': 13,
    'quatorze': 14,
    'quinze': 15,
    'seize': 16,
    'vingt': 20,
    'vingts': 20,
    'trente': 30,
    'quarante': 40,
    'cinquante': 50,
    'soixante': 60,
    'cent': 100,
    'cents': 100,
    'mille': 1000,
  };

  /// Nombres wolof et transcriptions approchées d'une reconnaissance en français.
  static const _wo = {
    1: ['benn', 'ben', 'bene', 'bɛnn', 'bain'],
    2: ['gnaar', 'niaar', 'nyaar', 'naar', 'gnar', 'niar', 'nyar', 'gniar'],
    3: ['gnett', 'niett', 'nyett', 'gnet', 'niet', 'nyet', 'nett', 'gniet'],
    4: ['gneent', 'nieent', 'nyeent', 'gnent', 'nient', 'nyent', 'neent', 'gnient'],
    5: ['juroom', 'jurom', 'diouroum', 'djouroum', 'diourom', 'juurom', 'dioroum', 'djurom'],
    10: ['fukk', 'fuk', 'fouk', 'foukk', 'fook'],
    100: ['teemeer', 'temeer', 'temer', 'teemer', 'teymer'],
  };

  static final Map<String, int> _woIndex = {
    for (final e in _wo.entries)
      for (final v in e.value) v: e.key,
  };

  static const _special = {'douzaine': 12, 'dizaine': 10, 'demi': 0.5, 'demie': 0.5, 'quart': 0.25, 'paire': 2};

  /// Valeur d'un mot-nombre (chiffres, français, wolof), sinon `null`.
  static num? wordValue(String w) {
    final d = num.tryParse(w);
    if (d != null) return d;
    if (_fr.containsKey(w)) return _fr[w];
    if (_woIndex.containsKey(w)) return _woIndex[w];
    return null;
  }

  /// Lit un nombre à partir de [i] ; renvoie (valeur, nombre de mots lus).
  /// Gère « vingt et un », « soixante dix », « quatre vingt », « dix sept »,
  /// « juroom benn » (6), « gnaar fukk » (20), « fukk ak benn » (11),
  /// « une douzaine », « deux et demi », « un demi ».
  static (num, int)? readNumber(List<String> t, int i) {
    if (i >= t.length) return null;
    final first = t[i];

    // « demi », « une douzaine », « une dizaine »
    if (_special.containsKey(first)) return (_special[first]!, 1);
    final v0 = wordValue(first);
    if (v0 == null) return null;
    var value = v0;
    var used = 1;

    num? at(int k) => k < t.length ? wordValue(t[k]) : null;
    String? word(int k) => k < t.length ? t[k] : null;

    // « une douzaine » / « deux douzaines »
    final next = word(i + 1);
    if (next != null && (next == 'douzaine' || next == 'douzaines' || next == 'dizaine' || next == 'dizaines')) {
      return (value * (next.startsWith('douz') ? 12 : 10), 2);
    }
    // « un demi » (kilo) — demi seul
    if (v0 == 1 && (next == 'demi' || next == 'demie')) return (0.5, 2);

    if (_woIndex.containsKey(first)) {
      // juroom + benn..gneent → 6..9
      if (v0 == 5 && _woIndex.containsKey(word(i + 1)) && (at(i + 1) ?? 0) >= 1 && (at(i + 1) ?? 0) <= 4) {
        value = 5 + at(i + 1)!;
        used = 2;
      }
      // gnaar fukk → 20 ; benn teemeer → 100
      final mult = word(i + used);
      if (mult != null && (_woIndex[mult] == 10 || _woIndex[mult] == 100) && value < 10) {
        value = value * _woIndex[mult]!;
        used++;
      }
      // fukk ak benn → 11 ; gnaar fukk ak juroom → 25
      if (value >= 10 && word(i + used) == 'ak' && _woIndex.containsKey(word(i + used + 1))) {
        final unit = readNumber(t, i + used + 1);
        if (unit != null && unit.$1 < 10) {
          value += unit.$1;
          used += 1 + unit.$2;
        }
      }
    } else if (_fr.containsKey(first)) {
      final fr = _frenchSequence(t, i);
      value = fr.$1;
      used = fr.$2;
    }

    // « deux et demi », « 1 kilo et demi » géré à part ; « deux et demi » ici.
    if (word(i + used) == 'et' && (word(i + used + 1) == 'demi' || word(i + used + 1) == 'demie')) {
      value += 0.5;
      used += 2;
    }
    return (value, used);
  }

  /// Nombre français en toutes lettres (« quatre vingt dix », « deux cent
  /// cinquante », « vingt et un ») ; s'arrête au premier mot qui ne prolonge
  /// pas le nombre (« trois deux » → 3).
  static (num, int) _frenchSequence(List<String> t, int i) {
    var total = 0;
    var current = 0;
    var k = i;
    while (k < t.length) {
      final w = t[k];
      if (w == 'et' &&
          current >= 20 &&
          current % 10 == 0 &&
          k + 1 < t.length &&
          {'un', 'une', 'onze'}.contains(t[k + 1])) {
        k++;
        continue;
      }
      final v = _fr[w];
      if (v == null) break;
      if (w == 'cent' || w == 'cents') {
        current = (current == 0 ? 1 : current) * 100;
      } else if (w == 'mille') {
        total += (current == 0 ? 1 : current) * 1000;
        current = 0;
      } else if ((w == 'vingt' || w == 'vingts') && current % 100 == 4) {
        current = current - 4 + 80;
      } else if (v < 20) {
        final tens = current % 100;
        final ok =
            current == 0 ||
            tens == 0 ||
            (tens >= 20 && tens % 10 == 0 && v < 10) ||
            ((tens == 60 || tens == 80) && v < 20) ||
            (tens == 10 && v >= 7 && v <= 9);
        if (!ok) break;
        current += v;
      } else {
        if (!(current == 0 || current % 100 == 0)) break;
        current += v;
      }
      k++;
    }
    return (total + current, math.max(1, k - i));
  }

  // ------------------------------------------------------------ Découpage

  /// Mots sans intérêt pour trouver l'article.
  static const stopWords = {
    'de',
    'du',
    'des',
    'la',
    'le',
    'les',
    'l',
    'd',
    'au',
    'aux',
    'en',
    'pour',
    'moi',
    'me',
    'mets',
    'met',
    'mettez',
    'donne',
    'donnez',
    'ajoute',
    'ajoutez',
    'il',
    'faut',
    'je',
    'veux',
    'voudrais',
    'aussi',
    's',
    'svp',
    'stp',
    'merci',
    'encore',
    'ci',
    'bi',
    'yi',
    'wi',
    'gi',
    'si',
    'mi',
    'li',
    'bu',
    'yu',
    'ma',
    'may',
    'jox',
    'joxal',
    'indil',
    'ndax',
    'na',
    'nga',
    'dama',
    'begg',
    'bëgg',
    'sama',
    'rek',
    'itam',
    'te',
    // Hésitations orales.
    'euh', 'heu', 'hum', 'bon', 'alors', 'voila', 'donc', 'oui', 'non', 'waaw', 'deedeet', 'ok', 'okay',
  };

  /// Liaisons qui séparent deux demandes (« et », wolof « ak »…).
  static const separators = {',', 'et', 'ak', 'puis', 'plus', 'avec', 'ensuite', 'aussi'};

  /// Unités de mesure : un nombre suivi d'une unité, quand la ligne a déjà sa
  /// quantité, décrit l'article (« huile 5 litres »).
  static const measures = {
    'l',
    'litre',
    'litres',
    'cl',
    'ml',
    'kg',
    'kilo',
    'kilos',
    'kilogramme',
    'kilogrammes',
    'g',
    'gr',
    'gramme',
    'grammes',
    'm',
    'metre',
    'metres',
    'cm',
    'mm',
  };

  /// Contenants : ne décrivent pas l'article, la quantité porte dessus.
  static const containers = {
    'sac',
    'sacs',
    'bidon',
    'bidons',
    'paquet',
    'paquets',
    'boite',
    'boites',
    'bouteille',
    'bouteilles',
    'carton',
    'cartons',
    'piece',
    'pieces',
    'unite',
    'unites',
    'pot',
    'pots',
    'sachet',
    'sachets',
    'tas',
    'barre',
    'barres',
    'plaquette',
    'plaquettes',
    'pack',
    'packs',
    'boule',
    'boules',
    'fois',
  };

  /// Découpe la phrase en demandes « quantité + article ».
  static List<VoiceItem> parse(String transcript) {
    final t = normalize(transcript).split(' ').where((w) => w.isNotEmpty).toList();
    final items = <VoiceItem>[];

    num? qty;
    var qtyAfterWords = false;
    final words = <String>[];
    final raw = <String>[];

    bool hasUseful() => words.any((w) => !stopWords.contains(w));

    void flush() {
      final useful = words.where((w) => !stopWords.contains(w)).toList();
      if (useful.isNotEmpty) {
        items.add(VoiceItem(quantity: qty ?? 1, words: useful, raw: raw.join(' '), explicitQuantity: qty != null));
      }
      qty = null;
      qtyAfterWords = false;
      words.clear();
      raw.clear();
    }

    var i = 0;
    while (i < t.length) {
      final w = t[i];

      // « et demi » après une quantité déjà lue : + 0,5.
      if (w == 'et' && i + 1 < t.length && (t[i + 1] == 'demi' || t[i + 1] == 'demie') && qty != null) {
        qty = qty! + 0.5;
        raw.addAll(['et', 'demi']);
        i += 2;
        continue;
      }

      final n = (w == 'et' || w == 'ak') ? null : readNumber(t, i);
      if (n != null) {
        final after = i + n.$2 < t.length ? t[i + n.$2] : null;
        final describesItem = qty != null && hasUseful() && after != null && measures.contains(after);
        if (describesItem) {
          // « huile 5 litres » : fait partie du nom.
          words.addAll([_fmt(n.$1), after]);
          raw.addAll(t.sublist(i, i + n.$2 + 1));
          i += n.$2 + 1;
          continue;
        }
        if (qty != null || (qtyAfterWords && hasUseful())) flush();
        if (!hasUseful()) {
          // Seulement des formules (« mets-moi », « jox ma ») : on les oublie.
          words.clear();
          raw.clear();
        } else if (qty == null) {
          // Quantité dite après l'article (« riz, deux sacs »).
          qtyAfterWords = true;
        }
        qty = n.$1;
        raw.addAll(t.sublist(i, i + n.$2));
        i += n.$2;
        continue;
      }

      if (separators.contains(w)) {
        if (hasUseful()) flush();
        i++;
        continue;
      }

      if (qtyAfterWords && hasUseful() && !containers.contains(w) && !measures.contains(w)) {
        // « riz deux, huile » : nouvel article après une quantité dite en fin.
        flush();
      }
      raw.add(w);
      if (!containers.contains(w)) words.add(w);
      i++;
    }
    flush();
    return items;
  }

  static String _fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // ------------------------------------------------------------ Rapprochement

  /// Similarité de deux mots (0 à 1) : égalité, préfixe, distance d'édition.
  static double wordSimilarity(String a, String b) {
    a = stem(a);
    b = stem(b);
    if (a == b) return 1;
    final minLen = math.min(a.length, b.length);
    if (minLen >= 3 && (a.startsWith(b) || b.startsWith(a))) return 0.9;
    if (minLen < 3) return 0;
    final d = _levenshtein(a, b);
    final sim = 1 - d / math.max(a.length, b.length);
    return sim >= 0.7 ? sim : 0;
  }

  static int _levenshtein(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// Score (0 à 1) d'un article pour une demande : part des mots demandés
  /// retrouvés dans le nom (les unités pèsent moins), petit bonus quand le nom
  /// est court (« Riz » plutôt que « Riz parfumé brisé » pour « riz »).
  static double score(List<String> query, String name) {
    final nameWords = normalize(name).split(' ').where((w) => w.isNotEmpty && w != ',').toList();
    if (nameWords.isEmpty || query.isEmpty) return 0;
    var total = 0.0;
    var got = 0.0;
    for (final q in query) {
      final weight = measures.contains(q) || num.tryParse(q) != null ? 0.4 : 1.0;
      total += weight;
      var best = 0.0;
      for (final w in nameWords) {
        best = math.max(best, wordSimilarity(q, w));
      }
      got += best * weight;
    }
    if (got == 0) return 0;
    final coverage = got / total;
    // Part du nom expliquée par la demande (départage les homonymes).
    final explained = nameWords.where((w) => query.any((q) => wordSimilarity(q, w) > 0)).length / nameWords.length;
    return math.min(1, coverage * 0.85 + explained * 0.15);
  }

  static VoiceMatch match(VoiceItem item, Iterable<VoiceCandidate> catalog) {
    final ranked = [
      for (final c in catalog)
        if (score(item.words, c.name) case final s when s > 0) (c, s),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return VoiceMatch(item: item, ranked: ranked.take(5).toList());
  }
}
