import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'db.dart';
import 'db2.dart';
import 'util.dart';

/// Numbers for one day, used by the daily closing report.
class DayReport {
  final String day;
  final int bills;
  final int voided;
  final double subtotal, discount, gst, total;
  final Map<String, double> pays;
  final List<Map<String, Object?>> sections;
  final List<Map<String, Object?>> expenses;
  final List<Map<String, Object?>> purchases;
  final double expenseTotal, purchaseTotal;

  DayReport({
    required this.day,
    required this.bills,
    required this.voided,
    required this.subtotal,
    required this.discount,
    required this.gst,
    required this.total,
    required this.pays,
    required this.sections,
    required this.expenses,
    required this.purchases,
    required this.expenseTotal,
    required this.purchaseTotal,
  });

  /// Sales without GST (GST is the government's money, not income).
  double get netSales => total - gst;

  /// Profit = sales (without GST) - purchases - expenses.
  double get profit => netSales - purchaseTotal - expenseTotal;

  static Future<DayReport> load(String day) async {
    final t = await Db.reportTotals(day, day);
    final pays = await Db.payTotals(day, day);
    final secs = await Db2.salesBySection(day, day);
    final exp = await Db2.expenses(day, day);
    final pur = await Db2.purchases(day, day);
    final v = await Db.db.rawQuery(
        "SELECT COUNT(*) AS c FROM bills WHERE date = ? AND status = 'void'",
        [day]);
    double sum(List<Map<String, Object?>> l) =>
        l.fold(0.0, (a, r) => a + ((r['amount'] as num?)?.toDouble() ?? 0));
    return DayReport(
      day: day,
      bills: (t['bills'] ?? 0).toInt(),
      voided: (v.first['c'] as num).toInt(),
      subtotal: t['subtotal'] ?? 0,
      discount: t['discount'] ?? 0,
      gst: t['gst'] ?? 0,
      total: t['total'] ?? 0,
      pays: pays,
      sections: secs,
      expenses: exp,
      purchases: pur,
      expenseTotal: sum(exp),
      purchaseTotal: sum(pur),
    );
  }

  /// Makes the PDF in HotelBilling/Reports and returns its path.
  Future<String> savePdf() async {
    final doc = pw.Document();
    final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
    pw.Widget line(String a, String b, {bool strong = false, double size = 11}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(a,
                    style: pw.TextStyle(
                        fontSize: size,
                        fontWeight: strong ? pw.FontWeight.bold : null)),
                pw.Text(b,
                    style: pw.TextStyle(
                        fontSize: size,
                        fontWeight: strong ? pw.FontWeight.bold : null)),
              ]),
        );
    pw.Widget head(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
          child: pw.Text(t,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        );
    String rs(double v) => 'Rs. ${money(v)}';

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(30),
      build: (ctx) => [
        pw.Text(Db.s('hotel_name'),
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text('Daily closing report: ${fmtDay(day)}'),
        pw.Divider(),
        head('Sales'),
        line('Number of bills', '$bills'),
        line('Sales before GST', rs(subtotal)),
        line('Discount given', rs(discount)),
        line('GST collected', rs(gst)),
        line('Total collected', rs(total), strong: true),
        if (voided > 0) line('Cancelled (void) bills', '$voided'),
        head('Payment mode'),
        if (pays.isEmpty) pw.Text('No sales'),
        for (final e in pays.entries) line(e.key, rs(e.value)),
        head('Sales by section'),
        if (sections.isEmpty) pw.Text('No sales'),
        for (final r in sections)
          line('${r['sn']}', rs((r['a'] as num).toDouble())),
        head('Purchases'),
        if (purchases.isEmpty) pw.Text('None'),
        for (final r in purchases)
          line('${r['supplier']}  ${r['items']}',
              rs((r['amount'] as num).toDouble())),
        line('Total purchases', rs(purchaseTotal), strong: true),
        head('Expenses'),
        if (expenses.isEmpty) pw.Text('None'),
        for (final r in expenses)
          line('${r['category']}  ${r['description']}',
              rs((r['amount'] as num).toDouble())),
        line('Total expenses', rs(expenseTotal), strong: true),
        pw.Divider(),
        line('Sales (without GST)', rs(netSales)),
        line('Less purchases', rs(purchaseTotal)),
        line('Less expenses', rs(expenseTotal)),
        line(profit >= 0 ? 'PROFIT' : 'LOSS', rs(profit.abs()),
            strong: true, size: 14),
        pw.SizedBox(height: 8),
        pw.Text(
            'Profit counts only what was entered in the app. Salary, rent and other costs are not included unless entered as expenses.',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.Text('', style: bold),
      ],
    ));
    final dir = Directory(p.join(Db.baseDir, 'Reports'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'daily_report_$day.pdf'));
    await file.writeAsBytes(await doc.save());
    return file.path;
  }
}
