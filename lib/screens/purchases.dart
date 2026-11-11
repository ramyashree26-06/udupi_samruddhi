import 'package:flutter/material.dart';

import '../db2.dart';
import '../dialogs.dart';
import '../theme.dart';
import '../pics.dart';
import '../util.dart';
import 'purchase_form.dart';
import '../widgets.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, Object?>> rows = [];

  String get _from => dayStr(month);
  String get _to => dayStr(DateTime(month.year, month.month + 1, 0));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db2.purchases(_from, _to);
    if (mounted) setState(() => rows = r);
  }

  void _shift(int d) {
    setState(() => month = DateTime(month.year, month.month + d));
    _load();
  }

  Future<void> _add() async {
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const PurchaseForm()));
    if (ok == true) await _load();
  }

  Future<void> _edit(Map<String, Object?> r) async {
    final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PurchaseForm(purchase: r)));
    if (ok == true) await _load();
  }

  Future<void> _delete(Map<String, Object?> r) async {
    final ok = await confirmBox(context, 'Delete', 'Delete this purchase?');
    if (!ok) return;
    await Db2.deletePurchase(r['id'] as int);
    await _load();
  }

  String _q(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> _open(Map<String, Object?> r) async {
    final items = await Db2.purchaseItems(r['id'] as int);
    if (!mounted) return;
    final slip = (r['slip'] ?? '') as String;
    final note = (r['note'] ?? '') as String;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        title: Text('${r['supplier']}  \u2022  ${fmtDay(r['date'] as String)}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (items.isEmpty) Text('${r['items']}'),
                for (final i in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(
                        child: Text(((i['qty'] as num?) ?? 0) > 0
                            ? '${i['name']}  (${_q(i['qty'] as num)} ${i['unit']})'
                            : '${i['name']}'),
                      ),
                      Text('Rs. ${money((i['amount'] as num).toDouble())}'),
                    ]),
                  ),
                const Divider(),
                Row(children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('Rs. ${money((r['amount'] as num).toDouble())}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 4),
                Text('Paid by: ${(r['pay_mode'] ?? 'Cash')}',
                    style: const TextStyle(color: kMuted)),
                if (note.isNotEmpty) Text('Note: $note', style: const TextStyle(color: kMuted)),
                if (slip.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  fileImage(slip, height: 280, fit: BoxFit.contain),
                ],
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final small = isNarrow(context);
    return Padding(
      padding: small
          ? const EdgeInsets.fromLTRB(16, 0, 16, 10)
          : const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (small)
            phoneMonthBar('${months[month.month - 1]} ${month.year}', () => _shift(-1),
                () => _shift(1), orangeButton('Add Purchase', _add))
          else
          PageHead('Purchases', actions: [
            IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
            Text('${months[month.month - 1]} ${month.year}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
            orangeButton('Add Purchase', _add),
          ]),
          Expanded(
            child: Box(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (!small)
                    Row(children: const [
                      Expanded(
                          child: TableHead(
                              ['Date', 'Supplier', 'Items', 'Amount', 'Status'],
                              [2, 3, 4, 2, 2])),
                      SizedBox(width: 120),
                    ]),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(
                            child: Text('No purchases', style: TextStyle(color: kMuted)))
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (_, i) {
                              final r = rows[i];
                              final pending = r['status'] == 'Pending';
                              if (small) {
                                return phoneRow(
                                  icon: Icons.shopping_cart_outlined,
                                  title: r['supplier'] as String,
                                  sub: '${fmtDay(r['date'] as String)}  \u2022  ${r['items']}',
                                  subLines: 2,
                                  last: i == rows.length - 1,
                                  trailing: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('\u20B9 ${money0((r['amount'] as num).toDouble())}',
                                            style: const TextStyle(fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 3),
                                        statusPill(r['status'] as String,
                                            pending ? const Color(0xFFE0A100) : kGreen),
                                      ],
                                    ),
                                    PopupMenuButton<String>(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.more_vert, size: 22),
                                      onSelected: (v) {
                                        if (v == 'view') _open(r);
                                        if (v == 'edit') _edit(r);
                                        if (v == 'delete') _delete(r);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'view',
                                            child: Text('View')),
                                        PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Edit')),
                                        PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete',
                                                style: TextStyle(color: kRed))),
                                      ],
                                    ),
                                  ],
                                );
                              }
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: kLine))),
                                child: Row(children: [
                                  Expanded(flex: 2, child: Text(fmtDay(r['date'] as String))),
                                  Expanded(flex: 3, child: Text(r['supplier'] as String)),
                                  Expanded(
                                      flex: 4,
                                      child: InkWell(
                                        onTap: () => _open(r),
                                        child: Text(
                                            '${r['items']}${((r['slip'] ?? '') as String).isEmpty ? '' : '  \u{1F4CE}'}',
                                            style: const TextStyle(
                                                decoration: TextDecoration.underline)),
                                      )),
                                  Expanded(
                                      flex: 2,
                                      child: Text(
                                          'Rs. ${money0((r['amount'] as num).toDouble())}',
                                          style: const TextStyle(fontWeight: FontWeight.w700))),
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Pill(r['status'] as String,
                                          pending ? const Color(0xFFE0A100) : kGreen),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Row(children: [
                                      IconButton(
                                        tooltip: 'View',
                                        icon: const Icon(Icons.visibility_outlined, size: 20),
                                        onPressed: () => _open(r),
                                      ),
                                      IconButton(
                                        tooltip: 'Edit',
                                        icon: const Icon(Icons.edit_outlined, size: 20),
                                        onPressed: () => _edit(r),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete',
                                        icon: const Icon(Icons.delete_outline, color: kRed, size: 20),
                                        onPressed: () => _delete(r),
                                      ),
                                    ]),
                                  ),
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
          const Text('Tip: use the three dots (View, Edit, Delete) to open a purchase, change it or see its slip photo.',
              style: TextStyle(color: kMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
