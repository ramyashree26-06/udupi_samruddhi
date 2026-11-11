import 'package:flutter/material.dart';

import '../db.dart';
import '../dialogs.dart';
import '../models.dart';
import '../print.dart';
import '../theme.dart';
import '../util.dart';

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});
  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  DateTime day = DateTime.now();
  List<BillRow> rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db.billsOn(dayStr(day));
    if (mounted) setState(() => rows = r);
  }

  Future<void> _pick() async {
    final d = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return;
    day = d;
    await _load();
  }

  Future<void> _open(BillRow r) async {
    final b = await Db.getBill(r.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${b.billNoText}  ${b.headline}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fmtDateTime(b.createdAt), style: const TextStyle(color: kMuted)),
                const SizedBox(height: 8),
                for (final i in b.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text('${i.qty} x ${i.name}')),
                        Text(money(i.amount)),
                      ],
                    ),
                  ),
                const Divider(),
                _row('Sub total', money(b.subtotal)),
                if (b.discount > 0) _row('Discount', '- ${money(b.discount)}'),
                _row('GST ${pctText(b.gstPct)}%', money(b.gstAmt)),
                _row('Total', money(b.total), bold: true),
                _row('Paid by', b.payMode.isEmpty ? '-' : b.payMode),
                if (b.status == 'void')
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('CANCELLED', style: TextStyle(color: kRed, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (b.status == 'paid')
            TextButton(
              onPressed: () async {
                final ok = await confirmBox(ctx, 'Cancel bill',
                    'Cancel this bill? It will be left out of reports.');
                if (!ok) return;
                await Db.voidBill(b.id);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Cancel bill', style: TextStyle(color: kRed)),
            ),
          FilledButton.icon(
            onPressed: () async {
              final err = await Receipts.printLines(Receipts.billLines(b));
              if (ctx.mounted) snack(ctx, err ?? 'Sent to printer');
            },
            icon: const Icon(Icons.print),
            label: const Text('Reprint'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
    await _load();
  }

  Widget _row(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null)),
            const Spacer(),
            Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final paid = rows.where((r) => r.status == 'paid');
    final sum = paid.fold<double>(0, (a, r) => a + r.total);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(fmtDay(dayStr(day))),
              ),
              const SizedBox(width: 12),
              Text('${paid.length} bills   Total Rs. ${money(sum)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No bills on this day', style: TextStyle(color: kMuted)))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      return ListTile(
                        onTap: () => _open(r),
                        title: Text(
                            '${r.billNoText}   ${r.label.isEmpty ? r.orderType : '${r.orderType} - ${r.label}'}',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                decoration:
                                    r.status == 'void' ? TextDecoration.lineThrough : null)),
                        subtitle: Text('${fmtTime(r.createdAt)}   ${r.payMode}'),
                        trailing: Text(
                            r.status == 'void' ? 'Cancelled' : 'Rs. ${money(r.total)}',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: r.status == 'void' ? kRed : kInk)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
