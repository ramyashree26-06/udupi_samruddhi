import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db.dart';
import '../dialogs.dart';
import '../theme.dart';
import '../util.dart';

class RepRow {
  final List<String> cells; // item, qty, amount
  final int kind; // 0 dish, 1 section total, 2 heading
  RepRow(this.cells, this.kind);
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime from = DateTime.now();
  DateTime to = DateTime.now();
  bool dayWise = false;
  List<Map<String, Object?>> raw = [];
  List<RepRow> rows = [];
  Map<String, double> totals = {};
  Map<String, double> pays = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _f => dayStr(from);
  String get _t => dayStr(to);

  Future<void> _load() async {
    final r = await Db.reportRows(_f, _t, dayWise);
    final t = await Db.reportTotals(_f, _t);
    final pt = await Db.payTotals(_f, _t);
    if (!mounted) return;
    setState(() {
      pays = pt;
      raw = r;
      totals = t;
      rows = _group(r);
    });
  }

  List<RepRow> _group(List<Map<String, Object?>> data) {
    final out = <RepRow>[];
    String? cur;
    var curName = '';
    var q = 0;
    var a = 0.0;
    void flush() {
      if (cur != null) {
        out.add(RepRow(['Total - $curName', '$q', money(a)], 1));
      }
    }

    for (final r in data) {
      final d = r['d'] as String;
      final s = r['sn'] as String;
      final key = dayWise ? '$d|$s' : s;
      if (key != cur) {
        flush();
        cur = key;
        curName = s;
        q = 0;
        a = 0;
        out.add(RepRow([dayWise ? '${fmtDay(d)}  -  $s' : s, '', ''], 2));
      }
      final qty = (r['q'] as num).toInt();
      final amt = (r['a'] as num).toDouble();
      q += qty;
      a += amt;
      out.add(RepRow([r['n'] as String, '$qty', money(amt)], 0));
    }
    flush();
    return out;
  }

  Future<void> _pick(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isFrom ? from : to,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return;
    setState(() {
      if (isFrom) {
        from = d;
        if (to.isBefore(from)) to = from;
      } else {
        to = d;
        if (from.isAfter(to)) from = to;
      }
    });
    await _load();
  }

  Future<void> _quick(int daysBack) async {
    setState(() {
      to = DateTime.now();
      from = DateTime.now().subtract(Duration(days: daysBack));
    });
    await _load();
  }

  // ---------- export ----------
  Future<Directory> _outDir() async {
    final dir = Directory(p.join(Db.baseDir, 'Reports'));
    await dir.create(recursive: true);
    return dir;
  }

  String _q(String s) => '"${s.replaceAll('"', '""')}"';

  Future<void> _exportCsv() async {
    final b = StringBuffer('﻿'); // so Excel reads it properly
    b.writeln('Item-wise sales report,$_f to $_t');
    b.writeln(dayWise ? 'Date,Section,Item,Qty,Amount' : 'Section,Item,Qty,Amount');
    final secTotals = <String, List<double>>{};
    for (final r in raw) {
      final s = r['sn'] as String;
      final qty = (r['q'] as num).toDouble();
      final amt = (r['a'] as num).toDouble();
      final cells = <String>[
        if (dayWise) r['d'] as String,
        _q(s),
        _q(r['n'] as String),
        qty.toInt().toString(),
        money(amt),
      ];
      b.writeln(cells.join(','));
      final t = secTotals.putIfAbsent(s, () => [0, 0]);
      t[0] += qty;
      t[1] += amt;
    }
    b.writeln();
    b.writeln('Section totals,Qty,Amount');
    secTotals.forEach((s, v) {
      b.writeln('${_q(s)},${v[0].toInt()},${money(v[1])}');
    });
    b.writeln();
    b.writeln('Bills,${totals['bills']?.toInt() ?? 0}');
    b.writeln('Sales before GST,${money(totals['subtotal'] ?? 0)}');
    b.writeln('Discount,${money(totals['discount'] ?? 0)}');
    b.writeln('GST,${money(totals['gst'] ?? 0)}');
    pays.forEach((k, v) => b.writeln('${_q(k)},${money(v)}'));
    b.writeln('Grand total,${money(totals['total'] ?? 0)}');
    final dir = await _outDir();
    final file = File(p.join(dir.path, 'sales_${_f}_to_$_t.csv'));
    await file.writeAsString(b.toString());
    if (!mounted) return;
    snack(context, 'Saved (opens in Excel): ${file.path}');
  }

  Future<void> _exportPdf() async {
    final doc = pw.Document();
    pw.Widget cell(String t, double w, {bool bold = false, bool right = false}) =>
        pw.SizedBox(
          width: w,
          child: pw.Text(t,
              textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        );
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        pw.Text(Db.s('hotel_name'),
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text('Item-wise sales report: ${fmtDay(_f)} to ${fmtDay(_t)}'),
        pw.SizedBox(height: 10),
        for (final r in rows)
          pw.Container(
            color: r.kind == 2 ? PdfColors.grey300 : null,
            padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            child: pw.Row(children: [
              cell(r.cells[0], 300, bold: r.kind != 0),
              cell(r.cells[1], 60, bold: r.kind != 0, right: true),
              cell(r.cells[2], 100, bold: r.kind != 0, right: true),
            ]),
          ),
        pw.SizedBox(height: 14),
        pw.Text('Bills: ${totals['bills']?.toInt() ?? 0}'),
        pw.Text('Sales before GST: Rs. ${money(totals['subtotal'] ?? 0)}'),
        pw.Text('Discount: Rs. ${money(totals['discount'] ?? 0)}'),
        pw.Text('GST: Rs. ${money(totals['gst'] ?? 0)}'),
        for (final e in pays.entries) pw.Text('${e.key}: Rs. ${money(e.value)}'),
        pw.Text('Grand total: Rs. ${money(totals['total'] ?? 0)}',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      ],
    ));
    final dir = await _outDir();
    final file = File(p.join(dir.path, 'sales_${_f}_to_$_t.pdf'));
    await file.writeAsBytes(await doc.save());
    if (!mounted) return;
    snack(context, 'Saved: ${file.path}');
  }

  Future<void> _exportWord() async {
    String esc(String x) => x.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
    final b = StringBuffer(
        '<html><head><meta charset="utf-8"></head><body>'
        '<h2>${esc(Db.s('hotel_name'))}</h2>'
        '<p>Item-wise sales report: ${fmtDay(_f)} to ${fmtDay(_t)}</p>'
        '<table border="1" cellspacing="0" cellpadding="4" width="100%">'
        '<tr><th align="left">Item</th><th align="right">Qty</th><th align="right">Amount</th></tr>');
    for (final r in rows) {
      final tag = r.kind == 0 ? 'td' : 'th';
      final bg = r.kind == 2 ? ' bgcolor="#EEEEEE"' : '';
      b.write('<tr$bg><$tag align="left">${esc(r.cells[0])}</$tag>'
          '<$tag align="right">${r.cells[1]}</$tag>'
          '<$tag align="right">${r.cells[2]}</$tag></tr>');
    }
    b.write('</table><p>Bills: ${totals['bills']?.toInt() ?? 0}<br>'
        'Sales before GST: Rs. ${money(totals['subtotal'] ?? 0)}<br>'
        'Discount: Rs. ${money(totals['discount'] ?? 0)}<br>'
        'GST: Rs. ${money(totals['gst'] ?? 0)}<br>'
        '<b>Grand total: Rs. ${money(totals['total'] ?? 0)}</b></p></body></html>');
    final dir = await _outDir();
    final file = File(p.join(dir.path, 'sales_${_f}_to_$_t.doc'));
    await file.writeAsString(b.toString());
    if (!mounted) return;
    snack(context, 'Saved (opens in Word): ${file.path}');
  }

  Future<void> _openFolder() async {
    final dir = await _outDir();
    final opened = await openFolder(dir.path);
    if (!opened && mounted) snack(context, 'Reports are saved inside the app: ${dir.path}');
  }

  // ---------- screen ----------
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Item-wise sales report', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                  onPressed: () => _pick(true),
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text('From ${fmtDay(_f)}')),
              OutlinedButton.icon(
                  onPressed: () => _pick(false),
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text('To ${fmtDay(_t)}')),
              TextButton(onPressed: () => _quick(0), child: const Text('Today')),
              TextButton(onPressed: () => _quick(1), child: const Text('Yesterday + Today')),
              TextButton(onPressed: () => _quick(6), child: const Text('Last 7 days')),
              TextButton(onPressed: () => _quick(29), child: const Text('Last 30 days')),
              FilterChip(
                label: const Text('Show day by day'),
                selected: dayWise,
                onSelected: (v) {
                  setState(() => dayWise = v);
                  _load();
                },
              ),
              FilledButton.tonalIcon(
                  onPressed: raw.isEmpty ? null : _exportCsv,
                  icon: const Icon(Icons.table_chart),
                  label: const Text('Save Excel')),
              FilledButton.tonalIcon(
                  onPressed: raw.isEmpty ? null : _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Save PDF')),
              FilledButton.tonalIcon(
                  onPressed: raw.isEmpty ? null : _exportWord,
                  icon: const Icon(Icons.description),
                  label: const Text('Save Word')),
              TextButton.icon(
                  onPressed: _openFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open reports folder')),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: raw.isEmpty
                ? const Center(child: Text('No sales in these dates'))
                : Card(
                    margin: EdgeInsets.zero,
                    child: ListView.builder(
                      itemCount: rows.length + 1,
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return const Padding(
                            padding: EdgeInsets.all(10),
                            child: Row(children: [
                              Expanded(child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
                              SizedBox(width: 80, child: Text('Qty sold', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold))),
                              SizedBox(width: 120, child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold))),
                            ]),
                          );
                        }
                        final r = rows[i - 1];
                        final bold = r.kind != 0;
                        return Container(
                          color: r.kind == 2
                              ? const Color(0xFFFFE9D6)
                              : (r.kind == 1 ? kSoft : null),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(children: [
                            Expanded(
                                child: Text(r.cells[0],
                                    style: TextStyle(fontWeight: bold ? FontWeight.bold : null))),
                            SizedBox(
                                width: 80,
                                child: Text(r.cells[1],
                                    textAlign: TextAlign.right,
                                    style: TextStyle(fontWeight: bold ? FontWeight.bold : null))),
                            SizedBox(
                                width: 120,
                                child: Text(r.cells[2],
                                    textAlign: TextAlign.right,
                                    style: TextStyle(fontWeight: bold ? FontWeight.bold : null))),
                          ]),
                        );
                      },
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 32,
                runSpacing: 8,
                children: [
                  Text('Bills: ${totals['bills']?.toInt() ?? 0}'),
                  Text('Sales before GST: Rs. ${money(totals['subtotal'] ?? 0)}'),
                  Text('Discount: Rs. ${money(totals['discount'] ?? 0)}'),
                  Text('GST: Rs. ${money(totals['gst'] ?? 0)}'),
                  for (final e in pays.entries)
                    Text('${e.key}: Rs. ${money(e.value)}'),
                  Text('Grand total: Rs. ${money(totals['total'] ?? 0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
