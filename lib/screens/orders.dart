import 'package:flutter/material.dart';

import '../db.dart';
import '../db2.dart';
import '../dialogs.dart';
import '../models.dart';
import '../print.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

/// Orders & Bills: every bill and saved order of a day.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  DateTime day = DateTime.now();
  List<BillRow> rows = [];
  String filter = 'All'; // All, Dine In, Takeaway, Cancelled
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  bool _matches(BillRow r) {
    final q = search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      r.status == 'draft'
          ? 'draft'
          : '${r.billNo} b-${r.billNo.toString().padLeft(4, '0')} ord-${r.billNo.toString().padLeft(4, '0')}',
      r.label,
      r.label.replaceFirst('Table: ', 'T'),
      r.orderType,
      r.payMode,
      r.statusText,
      r.total.toStringAsFixed(0),
      money(r.total),
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final paid = await Db.billsOn(dayStr(day));
    final drafts = day.day == DateTime.now().day && dayStr(day) == todayStr()
        ? await Db.drafts()
        : <BillRow>[];
    final all = [...drafts, ...paid];
    if (mounted) setState(() => rows = all);
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

  Color _statusColor(String s) {
    switch (s) {
      case 'Preparing':
        return const Color(0xFFE0A100);
      case 'Ready':
        return const Color(0xFF1E88E5);
      case 'Cancelled':
        return kRed;
      case 'Open':
        return kMuted;
      default:
        return kGreen;
    }
  }

  List<BillRow> get _shown {
    return rows.where(_matches).where((r) {
      switch (filter) {
        case 'Dine In':
          return r.orderType == 'Dine In' && r.status != 'void';
        case 'Parcel':
          return r.orderType != 'Dine In' && r.status != 'void';
        case 'Cancelled':
          return r.status == 'void';
        default:
          return true;
      }
    }).toList();
  }

  int _count(String f) {
    switch (f) {
      case 'Dine In':
        return rows.where((r) => r.orderType == 'Dine In' && r.status != 'void').length;
      case 'Parcel':
        return rows.where((r) => r.orderType != 'Dine In' && r.status != 'void').length;
      case 'Cancelled':
        return rows.where((r) => r.status == 'void').length;
      default:
        return rows.length;
    }
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
                    child: Row(children: [
                      Expanded(child: Text('${i.qty} x ${i.name}')),
                      Text(money(i.amount)),
                    ]),
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
                    child: Text('CANCELLED',
                        style: TextStyle(color: kRed, fontWeight: FontWeight.w800)),
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
          if (b.status != 'draft')
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

  /// Testing stage: remove all orders and bills.
  Future<void> _clearAll() async {
    final ok = await confirmBox(context, 'Clear all orders',
        'Delete ALL orders and bills of every date?\nA backup is saved first. This cannot be undone from here.');
    if (!ok) return;
    try {
      await Db2.clearAllOrders();
      await _load();
      if (!mounted) return;
      snack(context, 'All orders cleared');
    } catch (e) {
      if (!mounted) return;
      snack(context, 'Could not clear: $e');
    }
  }

  Widget _row(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null)),
          const Spacer(),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null)),
        ]),
      );

  Widget _phone(List<BillRow> list) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pick,
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kTan),
                    ),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(fmtDay(dayStr(day)),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      const Icon(Icons.keyboard_arrow_down, size: 22),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    backgroundColor: Colors.white,
                    foregroundColor: kRed,
                    side: const BorderSide(color: kRed)),
                onPressed: _clearAll,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear'),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search order no., table, amount...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => search.clear()),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in const ['All', 'Dine In', 'Parcel', 'Cancelled'])
                  phoneChip(
                    f == 'All' ? 'All Orders (${_count(f)})' : '$f (${_count(f)})',
                    filter == f,
                    () => setState(() => filter = f),
                    icon: Icons.check,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Box(
                padding: EdgeInsets.zero,
                child: list.isEmpty
                    ? const Center(child: Text('No orders', style: TextStyle(color: kMuted)))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final r = list[i];
                          final st = r.statusText;
                          final id = r.status == 'draft'
                              ? 'Draft'
                              : '#ORD-${r.billNo.toString().padLeft(4, '0')}';
                          final sub = r.label.isEmpty
                              ? r.orderType
                              : '${r.label.replaceFirst('Table: ', 'Table : T')}   ${r.orderType}';
                          return InkWell(
                            onTap: () => _open(r),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                              decoration: BoxDecoration(
                                  border: Border(
                                      bottom: BorderSide(
                                          color: i == list.length - 1
                                              ? Colors.transparent
                                              : kWarmLine))),
                              child: Row(children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF0E2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.receipt_long_outlined,
                                      color: kOrange, size: 21),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(id,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800, fontSize: 14.5)),
                                      const SizedBox(height: 2),
                                      Text(sub,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: kMuted, fontSize: 12.5)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(fmtTime(r.createdAt),
                                        style: const TextStyle(fontSize: 12, color: kMuted)),
                                    const SizedBox(height: 4),
                                    statusPill(st, _statusColor(st)),
                                  ],
                                ),
                                const Icon(Icons.chevron_right, size: 20, color: kMuted),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final list = _shown;
    final small = isNarrow(context);
    if (small) return _phone(list);
    return Padding(
      padding: EdgeInsets.all(small ? 10 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHead('Orders & Bills', actions: [
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(fmtDay(dayStr(day))),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: kRed, side: const BorderSide(color: kRed)),
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Clear'),
            ),
          ]),
          SizedBox(
            width: small ? double.infinity : 380,
            child: TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search order no., table, amount, status...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => search.clear()),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: small ? 0 : 4,
            children: [
              for (final f in const ['All', 'Dine In', 'Parcel', 'Cancelled'])
                ChoiceChip(
                  visualDensity: small ? VisualDensity.compact : null,
                  label: Text(f == 'All'
                      ? (small ? 'All (${_count(f)})' : 'All Orders (${_count(f)})')
                      : '$f (${_count(f)})'),
                  selected: filter == f,
                  selectedColor: kOrange,
                  labelStyle: TextStyle(color: filter == f ? Colors.white : kInk),
                  onSelected: (_) => setState(() => filter = f),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Box(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (!small)
                    const TableHead(
                        ['Order #', 'Type', 'Table', 'Amount', 'Status', 'Time'],
                        [2, 2, 2, 2, 2, 2]),
                  Expanded(
                    child: list.isEmpty
                        ? const Center(
                            child: Text('No orders', style: TextStyle(color: kMuted)))
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final r = list[i];
                              final st = r.statusText;
                              if (small) {
                                final tbl = r.label.isEmpty
                                    ? ''
                                    : '  \u2022  ${r.label.replaceFirst('Table: ', 'T')}';
                                return InkWell(
                                  onTap: () => _open(r),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: const BoxDecoration(
                                        border: Border(bottom: BorderSide(color: kLine))),
                                    child: Row(children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                r.status == 'draft' ? 'Draft' : '#${r.billNo}',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w800)),
                                            Text('${r.orderType}$tbl  \u2022  ${fmtTime(r.createdAt)}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    color: kMuted, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text('Rs. ${money0(r.total)}',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w800)),
                                          const SizedBox(height: 2),
                                          Pill(st, _statusColor(st)),
                                        ],
                                      ),
                                    ]),
                                  ),
                                );
                              }
                              return InkWell(
                                onTap: () => _open(r),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: const BoxDecoration(
                                      border: Border(bottom: BorderSide(color: kLine))),
                                  child: Row(children: [
                                    Expanded(
                                        flex: 2,
                                        child: Text(
                                            r.status == 'draft'
                                                ? 'Draft'
                                                : '#${r.billNo}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800))),
                                    Expanded(flex: 2, child: Text(r.orderType)),
                                    Expanded(
                                        flex: 2,
                                        child: Text(r.label.isEmpty
                                            ? '-'
                                            : r.label.replaceFirst('Table: ', 'T'))),
                                    Expanded(
                                        flex: 2, child: Text('Rs. ${money0(r.total)}')),
                                    Expanded(
                                        flex: 2,
                                        child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Pill(st, _statusColor(st)))),
                                    Expanded(flex: 2, child: Text(fmtTime(r.createdAt))),
                                  ]),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
