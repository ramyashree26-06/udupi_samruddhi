import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../charts.dart';
import '../db.dart';
import '../db2.dart';
import '../dialogs.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

class RepRow {
  final List<String> cells; // item, qty, amount
  final int kind; // 0 dish, 1 section total, 2 heading
  RepRow(this.cells, this.kind);
}

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  int view = 0; // 0 overview, 1 item-wise
  List<Map<String, Object?>> days = [];
  List<Map<String, Object?>> secs = [];
  double prevTotal = 0;

  DateTime from = DateTime.now();
  DateTime to = DateTime.now();
  bool dayWise = false;
  bool showDetails = false; // phone: bills, GST, cash... hidden until the arrow is tapped
  List<Map<String, Object?>> raw = [];
  List<RepRow> rows = [];
  Map<String, double> totals = {};
  Map<String, double> pays = {};
  Map<String, double> prof = {};

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
    final pf = await Db2.profit(_f, _t);
    final dy = await Db2.salesByDay(_f, _t);
    final sc = await Db2.salesBySection(_f, _t);
    final len = to.difference(from).inDays + 1;
    final pFrom = dayStr(from.subtract(Duration(days: len)));
    final pTo = dayStr(from.subtract(const Duration(days: 1)));
    final prev = await Db.reportTotals(pFrom, pTo);
    if (!mounted) return;
    setState(() {
      days = dy;
      secs = sc;
      prevTotal = prev['total'] ?? 0;
      pays = pt;
      prof = pf;
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
    snack(context, isAndroid ? 'Saved. Choose where to send it.' : 'Saved (opens in Excel): ${file.path}');
    if (isAndroid) await shareFile(file.path);
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
    snack(context, isAndroid ? 'Saved. Choose where to send it.' : 'Saved: ${file.path}');
    if (isAndroid) await shareFile(file.path);
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
    snack(context, isAndroid ? 'Saved. Choose where to send it.' : 'Saved (opens in Word): ${file.path}');
    if (isAndroid) await shareFile(file.path);
  }

  Future<void> _openFolder() async {
    final dir = await _outDir();
    final opened = await openFolder(dir.path);
    if (!opened && mounted) snack(context, 'Reports are saved inside the app: ${dir.path}');
  }

  Widget _overview() {
    final total = totals['total'] ?? 0;
    String change = '';
    if (prevTotal > 0) {
      final pct = (total - prevTotal) * 100 / prevTotal;
      change = '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(0)}% vs last period';
    }
    final labels = <String>[
      for (final d in days) (d['date'] as String).substring(8),
    ];
    final values = <double>[
      for (final d in days) (d['t'] as num).toDouble(),
    ];
    final small = isNarrow(context);
    final fullW = MediaQuery.of(context).size.width - 32;
    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Box(
              child: SizedBox(
                height: small ? 235.0 : 255.0,
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sales Overview',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(small ? '\u20B9 ${money0(total)}' : 'Rs. ${money0(total)}',
                      style: TextStyle(fontSize: small ? 20 : 24, fontWeight: FontWeight.w800)),
                  if (change.isNotEmpty)
                    Text(change,
                        style: TextStyle(
                            fontSize: 11,
                            color: prevTotal > 0 && total >= prevTotal ? kGreen : kRed,
                            fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  BarChart(labels: labels, values: values, height: small ? 130 : 150),
                  const Text('Day of the month', style: TextStyle(color: kMuted, fontSize: 10)),
                ],
              ),
              ),
            ),
          ),
          SizedBox(width: small ? 8 : 12),
          Expanded(
            flex: 2,
            child: Box(
              child: SizedBox(
                height: small ? 235.0 : 255.0,
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('By Category',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: DonutChart(compact: small, items: [
                          for (final e in secs)
                            MapEntry(e['sn'] as String, (e['a'] as num).toDouble()),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemsBody() => raw.isEmpty
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
                              SizedBox(width: 56, child: Text('Qty', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold))),
                              SizedBox(width: 90, child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold))),
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
                                width: 56,
                                child: Text(r.cells[1],
                                    textAlign: TextAlign.right,
                                    style: TextStyle(fontWeight: bold ? FontWeight.bold : null))),
                            SizedBox(
                                width: 90,
                                child: Text(r.cells[2],
                                    textAlign: TextAlign.right,
                                    style: TextStyle(fontWeight: bold ? FontWeight.bold : null))),
                          ]),
                        );
                      },
                    ),
                  );

  // ---------- screen ----------
  String _sd(String s) => fmtDay(s).substring(0, 5);

  Widget _smallControls() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  onPressed: () => _pick(true),
                  icon: const Icon(Icons.calendar_today, size: 14),
                  label: Text('From ${_sd(_f)}')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  onPressed: () => _pick(false),
                  icon: const Icon(Icons.calendar_today, size: 14),
                  label: Text('To ${_sd(_t)}')),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            for (final q in const [
              ['Today', 0],
              ['Yesterday', 1],
              ['7 days', 6],
              ['30 days', 29],
            ])
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 34),
                      textStyle: const TextStyle(fontSize: 12.5)),
                  onPressed: () => _quick(q[1] as int),
                  child: Text(q[0] as String),
                ),
              ),
          ]),
          Wrap(
            spacing: 6,
            children: [
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: const Text('Overview'),
                selected: view == 0,
                selectedColor: kOrange,
                labelStyle: TextStyle(color: view == 0 ? Colors.white : kInk),
                onSelected: (_) => setState(() => view = 0),
              ),
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: const Text('Items'),
                selected: view == 1,
                selectedColor: kOrange,
                labelStyle: TextStyle(color: view == 1 ? Colors.white : kInk),
                onSelected: (_) => setState(() => view = 1),
              ),
              FilterChip(
                visualDensity: VisualDensity.compact,
                label: const Text('Day by day'),
                selected: dayWise,
                onSelected: (v) {
                  setState(() => dayWise = v);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: raw.isEmpty ? null : _exportCsv,
                  icon: const Icon(Icons.table_chart, size: 16),
                  label: const Text('Excel')),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: raw.isEmpty ? null : _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf, size: 16),
                  label: const Text('PDF')),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: raw.isEmpty ? null : _exportWord,
                  icon: const Icon(Icons.description, size: 16),
                  label: const Text('Word')),
            ),
          ]),
        ],
      );

  Widget _dateField(String label, String day, bool from) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _pick(from),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kTan),
            ),
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$label ${fmtDay(day)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ]),
          ),
        ),
      );

  Widget _tabBtn(String label, bool on, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? kOrange : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: on ? kOrange : kTan),
            ),
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: on ? Colors.white : kInk)),
          ),
        ),
      );

  Widget _exportBtn(String label, IconData ic, Color bg, Color fg, VoidCallback f) =>
      Expanded(
        child: Opacity(
          opacity: raw.isEmpty ? 0.45 : 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: raw.isEmpty ? null : f,
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: fg.withOpacity(0.25)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(ic, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: fg)),
              ]),
            ),
          ),
        ),
      );

  Widget _phone() {
    const rs = '\u20B9';
    final sm = TextStyle(fontSize: 13, color: kInk);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _dateField('From', _f, true),
            const SizedBox(width: 10),
            _dateField('To', _t, false),
          ]),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final q in const [
                ['Today', 0],
                ['Yesterday', 1],
                ['7 Days', 6],
                ['30 Days', 29],
              ])
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: kOrange,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 34),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  onPressed: () => _quick(q[1] as int),
                  child: Text(q[0] as String),
                ),
            ],
          ),
          Row(children: [
            _tabBtn('Overview', view == 0, () => setState(() => view = 0)),
            const SizedBox(width: 8),
            _tabBtn('Items', view == 1 && !dayWise, () {
              setState(() {
                view = 1;
                dayWise = false;
              });
              _load();
            }),
            const SizedBox(width: 8),
            _tabBtn('Day by Day', view == 1 && dayWise, () {
              setState(() {
                view = 1;
                dayWise = true;
              });
              _load();
            }),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _exportBtn('Excel', Icons.table_chart_outlined, const Color(0xFFE3F4E8),
                const Color(0xFF1B8A3B), _exportCsv),
            const SizedBox(width: 8),
            _exportBtn('PDF', Icons.picture_as_pdf_outlined, const Color(0xFFFDE4E4),
                const Color(0xFFD32F2F), _exportPdf),
            const SizedBox(width: 8),
            _exportBtn('Word', Icons.description_outlined, const Color(0xFFE1ECFB),
                const Color(0xFF1E5FBF), _exportWord),
          ]),
          const SizedBox(height: 10),
          Expanded(child: view == 0 ? _overview() : _itemsBody()),
          const SizedBox(height: 8),
          Box(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showDetails) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bills : ${totals['bills']?.toInt() ?? 0}', style: sm),
                          const SizedBox(height: 3),
                          Text('Discount : $rs ${money0(totals['discount'] ?? 0)}', style: sm),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sales before GST : $rs ${money0(totals['subtotal'] ?? 0)}',
                              style: sm),
                          const SizedBox(height: 3),
                          Text('GST : $rs ${money0(totals['gst'] ?? 0)}', style: sm),
                        ],
                      ),
                    ),
                  ],
                ),
                if (pays.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                      [for (final e in pays.entries) '${e.key} : $rs ${money0(e.value)}']
                          .join('     '),
                      style: const TextStyle(fontSize: 12.5, color: kMuted)),
                ],
                if (prof.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                      'Purchases : $rs ${money0(prof['purchases'] ?? 0)}     Expenses : $rs ${money0(prof['expenses'] ?? 0)}',
                      style: const TextStyle(fontSize: 12.5, color: kMuted)),
                  const SizedBox(height: 3),
                  Text(
                      '${(prof['profit'] ?? 0) >= 0 ? 'Profit' : 'Loss'} : $rs ${money0((prof['profit'] ?? 0).abs())}',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: (prof['profit'] ?? 0) >= 0 ? kGreen : kRed)),
                ],
                  const SizedBox(height: 8),
                ],
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => showDetails = !showDetails),
                  child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD9AF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Text('Grand Total :',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: Color(0xFF8A4A00))),
                    const Spacer(),
                    Text('$rs ${money0(totals['total'] ?? 0)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            color: Color(0xFF8A4A00))),
                    const SizedBox(width: 4),
                    Icon(showDetails ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                        color: const Color(0xFF8A4A00)),
                  ]),
                ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final small = isNarrow(context);
    if (small) return _phone();
    return Padding(
      padding: EdgeInsets.all(small ? 10 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!small) ...[
            const Text('Sales Reports',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
          ],
          if (small) _smallControls() else
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
              ChoiceChip(
                label: const Text('Overview'),
                selected: view == 0,
                selectedColor: kOrange,
                labelStyle: TextStyle(color: view == 0 ? Colors.white : kInk),
                onSelected: (_) => setState(() => view = 0),
              ),
              ChoiceChip(
                label: const Text('Item-wise list'),
                selected: view == 1,
                selectedColor: kOrange,
                labelStyle: TextStyle(color: view == 1 ? Colors.white : kInk),
                onSelected: (_) => setState(() => view = 1),
              ),
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
          if (view == 0) Expanded(child: _overview()) else Expanded(
            child: _itemsBody(),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            color: Colors.white,
            child: Padding(
              padding: EdgeInsets.all(small ? 10 : 14),
              child: Wrap(
                spacing: small ? 16 : 32,
                runSpacing: small ? 4 : 8,
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
