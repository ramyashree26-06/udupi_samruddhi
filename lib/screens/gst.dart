import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../db.dart';
import '../db2.dart';
import '../dialogs.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

class GstScreen extends StatefulWidget {
  const GstScreen({super.key});
  @override
  State<GstScreen> createState() => _GstScreenState();
}

class _GstScreenState extends State<GstScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, double> totals = {};
  List<Map<String, Object?>> rows = [];

  String get _from => dayStr(month);
  String get _to => dayStr(DateTime(month.year, month.month + 1, 0));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await Db.reportTotals(_from, _to);
    final r = await Db2.gstBySection(_from, _to);
    if (mounted) {
      setState(() {
        totals = t;
        rows = r;
      });
    }
  }

  void _shift(int d) {
    setState(() => month = DateTime(month.year, month.month + d));
    _load();
  }

  Future<void> _export() async {
    final b = StringBuffer('﻿');
    b.writeln('GST report,$_from to $_to');
    b.writeln('GSTIN,${Db.s('gstin')}');
    b.writeln('HSN/SAC,Description,Taxable Value,CGST,SGST,Total GST,Total');
    for (final r in rows) {
      final tx = (r['taxable'] as num).toDouble();
      final g = (r['gst'] as num).toDouble();
      b.writeln('996331,"${r['sn']}",${money(tx)},${money(g / 2)},${money(g / 2)},${money(g)},${money(tx + g)}');
    }
    b.writeln();
    b.writeln('Taxable sales,${money((totals['subtotal'] ?? 0) - (totals['discount'] ?? 0))}');
    b.writeln('GST,${money(totals['gst'] ?? 0)}');
    b.writeln('Total sales,${money(totals['total'] ?? 0)}');
    final dir = Directory(p.join(Db.baseDir, 'Reports'));
    await dir.create(recursive: true);
    final f = File(p.join(dir.path, 'gst_${_from}_to_$_to.csv'));
    await f.writeAsString(b.toString());
    if (!mounted) return;
    snack(context, isAndroid ? 'Saved. Choose where to send it.' : 'Saved (opens in Excel): ${f.path}');
    if (isAndroid) await shareFile(f.path);
  }

  Widget _card(String t, String v, Color bg, {bool compact = false}) => Expanded(
        child: Container(
          padding: EdgeInsets.all(compact ? 10 : 16),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: kInk, fontSize: compact ? 11 : 14)),
              SizedBox(height: compact ? 2 : 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(v,
                    style: TextStyle(
                        fontSize: compact ? 15 : 24, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final taxable = (totals['subtotal'] ?? 0) - (totals['discount'] ?? 0);
    final small = isNarrow(context);
    return Padding(
      padding: small
          ? const EdgeInsets.fromLTRB(16, 0, 16, 10)
          : const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (small)
            phoneMonthBar(
              '${months[month.month - 1]} ${month.year}',
              () => _shift(-1),
              () => _shift(1),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: rows.isEmpty ? null : _export,
                child: Opacity(
                  opacity: rows.isEmpty ? 0.45 : 1,
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F4E8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x401B8A3B)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.table_chart_outlined, size: 18, color: Color(0xFF1B8A3B)),
                      SizedBox(width: 6),
                      Text('Excel',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: Color(0xFF1B8A3B))),
                    ]),
                  ),
                ),
              ),
            )
          else
          PageHead('GST Reports', inline: true, actions: [
            IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left)),
            Text('${months[month.month - 1]} ${month.year}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right)),
            if (small)
              IconButton(
                  tooltip: 'Save Excel',
                  onPressed: rows.isEmpty ? null : _export,
                  icon: const Icon(Icons.table_chart))
            else
              OutlinedButton.icon(
                  onPressed: rows.isEmpty ? null : _export,
                  icon: const Icon(Icons.table_chart),
                  label: const Text('Save Excel')),
          ]),
          Row(
            children: [
              _card(small ? 'Taxable' : 'Taxable Sales',
                  small ? '\u20B9 ${money0(taxable)}' : 'Rs. ${money(taxable)}', const Color(0xFFE6F6EA),
                  compact: small),
              SizedBox(width: small ? 8 : 12),
              _card('GST (${pctText(Db.d('gst_pct'))}%)',
                  small ? '\u20B9 ${money0(totals['gst'] ?? 0)}' : 'Rs. ${money(totals['gst'] ?? 0)}',
                  const Color(0xFFFFF1E0),
                  compact: small),
              SizedBox(width: small ? 6 : 12),
              _card('Total', small ? '\u20B9 ${money0(totals['total'] ?? 0)}' : 'Rs. ${money(totals['total'] ?? 0)}',
                  const Color(0xFFEDE9FB),
                  compact: small),
            ],
          ),
          SizedBox(height: small ? 8 : 14),
          Expanded(
            child: Box(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (!small)
                    const TableHead(
                        ['HSN / SAC', 'Description', 'Taxable Value', 'CGST', 'SGST', 'Total'],
                        [2, 4, 3, 2, 2, 3]),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(
                            child: Text('No sales this month', style: TextStyle(color: kMuted)))
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (_, i) {
                              final r = rows[i];
                              final tx = (r['taxable'] as num).toDouble();
                              final g = (r['gst'] as num).toDouble();
                              if (small) {
                                return phoneRow(
                                  icon: Icons.request_quote_outlined,
                                  title: r['sn'] as String,
                                  sub: 'HSN 996331  \u2022  Taxable \u20B9 ${money0(tx)}',
                                  last: i == rows.length - 1,
                                  trailing: [
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text('\u20B9 ${money(tx + g)}',
                                              style: const TextStyle(fontWeight: FontWeight.w800)),
                                          Text('CGST ${money0(g / 2)}  SGST ${money0(g / 2)}',
                                              style: const TextStyle(color: kMuted, fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: kLine))),
                                child: Row(children: [
                                  const Expanded(flex: 2, child: Text('996331')),
                                  Expanded(flex: 4, child: Text(r['sn'] as String)),
                                  Expanded(flex: 3, child: Text('Rs. ${money(tx)}')),
                                  Expanded(flex: 2, child: Text(money(g / 2))),
                                  Expanded(flex: 2, child: Text(money(g / 2))),
                                  Expanded(
                                      flex: 3,
                                      child: Text('Rs. ${money(tx + g)}',
                                          style: const TextStyle(fontWeight: FontWeight.w700))),
                                ]),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text('Figures are after any extra discount. HSN/SAC 996331 = restaurant service.',
              style: TextStyle(color: kMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
