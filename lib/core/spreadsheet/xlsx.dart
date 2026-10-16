/// Fichiers tableur sans dépendance lourde : écriture de classeurs `.xlsx`
/// (Office Open XML minimal : en-têtes stylés, première ligne figée, filtres,
/// nombres réels) et lecture de la première feuille d'un `.xlsx` ou d'un
/// `.csv` (séparateur détecté).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Feuille à écrire : en-têtes + lignes (String, num, DateTime ou null).
class XlsxSheet {
  const XlsxSheet({required this.name, required this.headers, required this.rows, this.widths});

  final String name;
  final List<String> headers;
  final List<List<Object?>> rows;

  /// Largeurs de colonnes (en caractères) ; calculées si absentes.
  final List<double>? widths;
}

abstract final class Xlsx {
  static const mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  // ------------------------------------------------------------------ Écriture

  static Uint8List write(List<XlsxSheet> sheets) {
    assert(sheets.isNotEmpty);
    final archive = Archive();
    void add(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    final names = _uniqueNames(sheets.map((s) => s.name).toList());
    add('[Content_Types].xml', _contentTypes(sheets.length));
    add('_rels/.rels', _rootRels);
    add('xl/workbook.xml', _workbook(names));
    add('xl/_rels/workbook.xml.rels', _workbookRels(sheets.length));
    add('xl/styles.xml', _styles);
    for (final (i, sheet) in sheets.indexed) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheet(sheet));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      // Caractères de contrôle interdits en XML 1.0.
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

  /// « A », « B »… « Z », « AA »…
  static String column(int index) {
    var n = index + 1;
    final b = StringBuffer();
    while (n > 0) {
      final r = (n - 1) % 26;
      b.write(String.fromCharCode(65 + r));
      n = (n - 1) ~/ 26;
    }
    return b.toString().split('').reversed.join();
  }

  static List<String> _uniqueNames(List<String> raw) {
    final used = <String>{};
    return [
      for (final r in raw)
        () {
          var name = r.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
          if (name.isEmpty) name = 'Feuille';
          if (name.length > 31) name = name.substring(0, 31);
          var candidate = name;
          var k = 2;
          while (!used.add(candidate.toLowerCase())) {
            final suffix = ' ($k)';
            candidate = '${name.substring(0, (31 - suffix.length).clamp(0, name.length))}$suffix';
            k++;
          }
          return candidate;
        }(),
    ];
  }

  static String _contentTypes(int count) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '${[for (var i = 1; i <= count; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
      '</Types>';

  static const _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  static String _workbook(List<String> names) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
      '${[for (final (i, n) in names.indexed) '<sheet name="${_esc(n)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
      '</sheets></workbook>';

  static String _workbookRels(int count) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '${[for (var i = 1; i <= count; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
      '<Relationship Id="rId${count + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';

  /// Styles : 0 normal · 1 en-tête (gras blanc sur vert JËND) · 2 entier avec
  /// séparateur de milliers · 3 décimal · 4 date.
  static const _styles =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<numFmts count="1"><numFmt numFmtId="164" formatCode="dd/mm/yyyy hh:mm"/></numFmts>'
      '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>'
      '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FF1D4536"/><bgColor indexed="64"/></patternFill></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="5">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
      '<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';

  /// Jours depuis l'origine Excel (30/12/1899), fraction = heure.
  static double excelDate(DateTime d) {
    final local = d.isUtc ? d.toLocal() : d;
    final utc = DateTime.utc(local.year, local.month, local.day, local.hour, local.minute, local.second);
    return utc.difference(DateTime.utc(1899, 12, 30)).inSeconds / 86400;
  }

  static String _sheet(XlsxSheet s) {
    final b = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
      '</sheetView></sheetViews><cols>',
    );
    for (var c = 0; c < s.headers.length; c++) {
      final width =
          s.widths?.elementAtOrNull(c) ??
          [
            s.headers[c].length + 4,
            for (final r in s.rows.take(200))
              if (c < r.length && r[c] != null) '${r[c]}'.length + 2,
          ].reduce((a, b) => a > b ? a : b).clamp(8, 48).toDouble();
      b.write('<col min="${c + 1}" max="${c + 1}" width="$width" customWidth="1"/>');
    }
    b.write('</cols><sheetData>');

    void cell(int row, int col, Object? v, {bool header = false}) {
      final ref = '${column(col)}$row';
      switch (v) {
        case null:
          return;
        case int n:
          b.write('<c r="$ref" s="2"><v>$n</v></c>');
        case double n when n.isFinite:
          b.write('<c r="$ref" s="3"><v>$n</v></c>');
        case DateTime d:
          b.write('<c r="$ref" s="4"><v>${excelDate(d)}</v></c>');
        default:
          b.write(
            '<c r="$ref" t="inlineStr"${header ? ' s="1"' : ''}><is><t xml:space="preserve">${_esc('$v')}</t></is></c>',
          );
      }
    }

    b.write('<row r="1">');
    for (final (c, h) in s.headers.indexed) {
      cell(1, c, h, header: true);
    }
    b.write('</row>');
    for (final (i, r) in s.rows.indexed) {
      b.write('<row r="${i + 2}">');
      for (final (c, v) in r.indexed) {
        cell(i + 2, c, v);
      }
      b.write('</row>');
    }
    b.write('</sheetData>');
    if (s.headers.isNotEmpty) {
      b.write('<autoFilter ref="A1:${column(s.headers.length - 1)}${s.rows.length + 1}"/>');
    }
    b.write('</worksheet>');
    return b.toString();
  }

  // ------------------------------------------------------------------ Lecture

  /// Première feuille d'un `.xlsx`, ou contenu d'un `.csv` : lignes de
  /// cellules texte (lignes vides ignorées). Lève [FormatException] si le
  /// fichier n'est pas lisible.
  static List<List<String>> readTable(Uint8List bytes, {required String fileName}) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.csv') || lower.endsWith('.txt')) return readCsv(bytes);
    if (lower.endsWith('.xlsx')) return readXlsx(bytes);
    throw const FormatException('Format non pris en charge : choisissez un fichier Excel (.xlsx) ou CSV.');
  }

  static List<List<String>> readXlsx(Uint8List bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('Fichier Excel illisible. Enregistrez-le au format .xlsx puis réessayez.');
    }
    String? text(String path) {
      final f = zip.findFile(path);
      return f == null ? null : utf8.decode(f.content as List<int>);
    }

    // Première feuille déclarée dans le classeur.
    var sheetPath = 'xl/worksheets/sheet1.xml';
    final workbook = text('xl/workbook.xml');
    final rels = text('xl/_rels/workbook.xml.rels');
    if (workbook != null && rels != null) {
      final first = XmlDocument.parse(workbook).findAllElements('sheet').firstOrNull;
      final rid = first?.attributes.where((a) => a.name.local == 'id').firstOrNull?.value;
      final target = XmlDocument.parse(
        rels,
      ).findAllElements('Relationship').where((r) => r.getAttribute('Id') == rid).firstOrNull?.getAttribute('Target');
      if (target != null) {
        sheetPath = target.startsWith('/') ? target.substring(1) : 'xl/${target.replaceFirst(RegExp(r'^\./'), '')}';
      }
    }
    final sheet = text(sheetPath);
    if (sheet == null) throw const FormatException('Aucune feuille trouvée dans ce fichier Excel.');

    final shared = <String>[];
    final sst = text('xl/sharedStrings.xml');
    if (sst != null) {
      for (final si in XmlDocument.parse(sst).findAllElements('si')) {
        shared.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }

    final rows = <List<String>>[];
    for (final row in XmlDocument.parse(sheet).findAllElements('row')) {
      final cells = <int, String>{};
      var next = 0;
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r');
        final col = ref == null ? next : _columnIndex(ref);
        next = col + 1;
        final type = c.getAttribute('t');
        final v = c.findElements('v').firstOrNull?.innerText;
        final value = switch (type) {
          's' => v == null ? '' : shared.elementAtOrNull(int.tryParse(v) ?? -1) ?? '',
          'inlineStr' => c.findAllElements('t').map((t) => t.innerText).join(),
          'b' => v == '1' ? 'VRAI' : 'FAUX',
          _ => _number(v ?? ''),
        };
        cells[col] = value.trim();
      }
      if (cells.values.every((v) => v.isEmpty)) continue;
      final width = cells.keys.fold<int>(0, (m, k) => k + 1 > m ? k + 1 : m);
      rows.add([for (var i = 0; i < width; i++) cells[i] ?? '']);
    }
    return rows;
  }

  /// « 1500.0 » → « 1500 » (Excel stocke les entiers en flottants).
  static String _number(String v) {
    final n = num.tryParse(v);
    if (n == null) return v;
    return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  }

  static int _columnIndex(String ref) {
    var n = 0;
    for (final ch in ref.toUpperCase().codeUnits) {
      if (ch < 65 || ch > 90) break;
      n = n * 26 + (ch - 64);
    }
    return n - 1;
  }

  static List<List<String>> readCsv(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    final firstLine = text.split(RegExp(r'\r?\n')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final sep = [
      ';',
      '\t',
      ',',
    ].reduce((a, b) => a.allMatches(firstLine).length >= b.allMatches(firstLine).length ? a : b);

    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == sep) {
        row.add(field.toString().trim());
        field.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(field.toString().trim());
        field.clear();
        if (row.any((v) => v.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(ch);
      }
    }
    row.add(field.toString().trim());
    if (row.any((v) => v.isNotEmpty)) rows.add(row);
    return rows;
  }
}
