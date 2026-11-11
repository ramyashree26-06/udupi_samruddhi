import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'db.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'util.dart';

/// Import / export the menu as an Excel (or CSV) sheet.
/// Columns:  Section | Category | Dish name | Price
/// (Category is optional - leave it empty if the dish has none.)
class MenuSheet {
  static const header = ['Section', 'Category', 'Dish name', 'Price'];

  // ------------------------------------------------------------ reading
  static String _cellText(Object? v) {
    if (v == null) return '';
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toString();
    }
    if (v is TextCellValue) {
      final x = v.value as Object;
      if (x is String) return x.trim();
      try {
        return ((x as dynamic).toPlainText() as String).trim();
      } catch (_) {
        return x.toString().trim();
      }
    }
    return v.toString().trim();
  }

  static List<List<String>> _readXlsx(List<int> bytes) {
    final ex = Excel.decodeBytes(bytes);
    if (ex.tables.isEmpty) return [];
    final sheet = ex.tables.values.first;
    return [
      for (final r in sheet.rows) [for (final c in r) _cellText(c?.value)]
    ];
  }

  static List<List<String>> _readCsv(String text) {
    if (text.startsWith('﻿')) text = text.substring(1);
    final first = text.split('\n').first;
    final sep = first.contains('\t')
        ? '\t'
        : (first.split(';').length > first.split(',').length ? ';' : ',');
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var q = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (q) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            q = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        q = true;
      } else if (ch == sep) {
        row.add(cell.toString().trim());
        cell.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString().trim());
        cell.clear();
        rows.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString().trim());
      rows.add(row);
    }
    return rows;
  }

  static double? _price(String s) {
    var t = s.replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  // ------------------------------------------------------------ writing
  static CellValue _num(double v) =>
      v == v.roundToDouble() ? IntCellValue(v.round()) : DoubleCellValue(v);

  static Future<String> _save(Excel ex, String name) async {
    final bytes = ex.save();
    final dir = Directory(p.join(Db.baseDir, 'Reports'));
    await dir.create(recursive: true);
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(bytes ?? <int>[]);
    return f.path;
  }

  static Excel _book(List<List<Object>> rows) {
    final ex = Excel.createExcel();
    final first = ex.getDefaultSheet() ?? 'Sheet1';
    ex.rename(first, 'Menu');
    final sh = ex['Menu'];
    sh.appendRow([for (final h in header) TextCellValue(h)]);
    for (final r in rows) {
      sh.appendRow([
        TextCellValue(r[0] as String),
        TextCellValue(r[1] as String),
        TextCellValue(r[2] as String),
        _num(r[3] as double),
      ]);
    }
    sh.setColumnWidth(0, 22);
    sh.setColumnWidth(1, 22);
    sh.setColumnWidth(2, 34);
    sh.setColumnWidth(3, 10);
    return ex;
  }

  static Future<void> _deliver(BuildContext context, String path) async {
    if (!context.mounted) return;
    if (isAndroid) {
      snack(context, 'Saved. Choose where to send it.');
      await shareFile(path);
    } else {
      snack(context, 'Saved: $path');
    }
  }

  static Future<void> sample(BuildContext context) async {
    final ex = _book([
      ['Tiffin', 'Dosa', 'Masala Dosa', 80.0],
      ['Tiffin', 'Dosa', 'Plain Dosa', 60.0],
      ['Tiffin', '', 'Idli (2 pcs)', 40.0],
      ['Meals', '', 'Full Meals', 120.0],
    ]);
    final path = await _save(ex, 'menu_sample.xlsx');
    await _deliver(context, path);
  }

  static Future<void> export(BuildContext context) async {
    final secs = await Db.sections();
    final dishes = await Db.dishes();
    final rows = <List<Object>>[];
    for (final s in secs) {
      for (final d in dishes.where((x) => x.sectionId == s.id)) {
        rows.add([s.name, d.group, d.name, d.price]);
      }
    }
    final ex = _book(rows);
    final path = await _save(ex, 'menu_${todayStr()}.xlsx');
    await _deliver(context, path);
  }

  // ------------------------------------------------------------ importing
  static Future<void> import(BuildContext context, Future<void> Function() onDone) async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Menu sheet', extensions: ['xlsx', 'csv']),
    ]);
    if (f == null) return;
    List<int>? bytes;
    try {
      bytes = await f.readAsBytes();
    } catch (_) {}
    if (bytes == null) {
      if (context.mounted) snack(context, 'Could not read that file');
      return;
    }
    List<List<String>> table;
    try {
      table = f.name.toLowerCase().endsWith('.csv')
          ? _readCsv(utf8.decode(bytes, allowMalformed: true))
          : _readXlsx(bytes);
    } catch (_) {
      if (context.mounted) snack(context, 'This file could not be opened. Use the sample sheet.');
      return;
    }
    if (!context.mounted) return;

    // skip the heading row
    var start = 0;
    if (table.isNotEmpty && table.first.isNotEmpty) {
      final h = table.first.join(' ').toLowerCase();
      if (h.contains('dish') || h.contains('price') || h.contains('section')) start = 1;
    }

    final secs = await Db.sections();
    final secByName = {for (final s in secs) s.name.toLowerCase(): s};
    final all = await Db.dishes();
    final existing = <String, dynamic>{
      for (final d in all) '${d.sectionName.toLowerCase()}|${d.name.toLowerCase()}': d
    };

    final good = <_Row>[];
    final problems = <String>[];
    final seen = <String>{};
    var dupInFile = 0;
    for (var i = start; i < table.length; i++) {
      final r = table[i];
      String c(int k) => k < r.length ? r[k].trim() : '';
      if (r.every((x) => x.trim().isEmpty)) continue;
      final sec = c(0), cat = c(1), name = c(2);
      final pr = _price(c(3));
      final line = i + 1;
      if (sec.isEmpty) {
        problems.add('Row $line: Section is empty');
        continue;
      }
      if (name.isEmpty) {
        problems.add('Row $line: Dish name is empty');
        continue;
      }
      if (pr == null) {
        problems.add('Row $line: Price is missing');
        continue;
      }
      final key = '${sec.toLowerCase()}|${name.toLowerCase()}';
      if (!seen.add(key)) {
        dupInFile++;
        continue;
      }
      good.add(_Row(sec, cat, name, pr, key));
    }

    var nNew = 0, nUpd = 0, nSame = 0;
    final newSecs = <String>{};
    for (final g in good) {
      if (!secByName.containsKey(g.section.toLowerCase())) newSecs.add(g.section);
      final e = existing[g.key];
      if (e == null) {
        nNew++;
      } else if ((e.price as double) != g.price) {
        nUpd++;
      } else {
        nSame++;
      }
    }

    if (good.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nothing to add'),
          content: Text(problems.isEmpty
              ? 'No dishes found in the file. Use the sample sheet: Section, Category, Dish name, Price.'
              : problems.take(6).join('\n')),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    var updatePrices = true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Widget line(String k, int n, {Color? c}) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Text(k),
                  const Spacer(),
                  Text('$n', style: TextStyle(fontWeight: FontWeight.w800, color: c)),
                ]),
              );
          final adds = nNew + (updatePrices ? nUpd : 0);
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            title: const Text('Check before adding'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.name, style: const TextStyle(color: kMuted, fontSize: 12)),
                    const SizedBox(height: 8),
                    line('New dishes', nNew, c: kGreen),
                    line('New sections', newSecs.length),
                    line('Already there, price changed', nUpd, c: kOrange),
                    line('Already there, same price', nSame),
                    if (dupInFile > 0) line('Repeated in the file (skipped)', dupInFile),
                    if (problems.isNotEmpty) line('Rows with a problem', problems.length, c: kRed),
                    if (nUpd > 0)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: updatePrices,
                        activeColor: kOrange,
                        title: const Text('Update the price of dishes that already exist'),
                        onChanged: (v) => setS(() => updatePrices = v),
                      ),
                    if (problems.isNotEmpty) ...[
                      const Divider(),
                      for (final t in problems.take(5))
                        Text(t, style: const TextStyle(color: kRed, fontSize: 12)),
                      if (problems.length > 5)
                        Text('...and ${problems.length - 5} more',
                            style: const TextStyle(color: kRed, fontSize: 12)),
                      const Text('These rows will be skipped.',
                          style: TextStyle(color: kMuted, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: adds == 0 ? null : () => Navigator.pop(ctx, true),
                child: Text('Add ($adds)'),
              ),
            ],
          );
        },
      ),
    );
    if (go != true) return;

    // create missing sections
    for (final name in newSecs) {
      await Db.addSection(name);
    }
    final fresh = {for (final s in await Db.sections()) s.name.toLowerCase(): s};
    var added = 0, updated = 0;
    for (final g in good) {
      final sec = fresh[g.section.toLowerCase()];
      if (sec == null) continue;
      final e = existing[g.key];
      if (e == null) {
        await Db.addDish(sec.id, g.name, g.price, group: g.category);
        added++;
      } else if (updatePrices && (e.price as double) != g.price) {
        await Db.setPrice(e.id as int, g.price);
        updated++;
      }
    }
    await onDone();
    if (context.mounted) {
      snack(context, 'Added $added dishes${updated > 0 ? ', updated $updated prices' : ''}');
    }
  }
}

class _Row {
  final String section, category, name, key;
  final double price;
  _Row(this.section, this.category, this.name, this.price, this.key);
}
