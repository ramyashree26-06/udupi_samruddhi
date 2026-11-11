import 'package:flutter/material.dart';

import '../db2.dart';
import '../dialogs.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

/// How a supplier is shown everywhere: "Ramesh - Milk".
String supLabel(Map<String, Object?> r) {
  final n = '${r['name'] ?? ''}'.trim();
  final p = '${r['supplies'] ?? ''}'.trim();
  return p.isEmpty ? n : '$n - $p';
}

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});
  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db2.suppliers();
    if (mounted) setState(() => rows = r);
  }

  Future<void> _edit([Map<String, Object?>? r]) async {
    String g(String k) => r == null ? '' : '${r[k] ?? ''}';
    final v = await askFields(context, r == null ? 'Add supplier' : 'Edit supplier', [
      FieldSpec('name', 'Name (like Ramesh)', initial: g('name')),
      FieldSpec('supplies', 'Product (like Milk)', initial: g('supplies')),
      FieldSpec('phone', 'Mobile number', initial: g('phone')),
      FieldSpec('address', 'Address', initial: g('address')),
    ]);
    if (v == null || v['name']!.trim().isEmpty) return;
    await Db2.saveSupplier(r == null ? null : r['id'] as int, v['name']!.trim(), v['phone']!.trim(),
        supplies: v['supplies']!.trim(), address: v['address']!.trim());
    await _load();
  }

  Future<void> _delete(Map<String, Object?> r) async {
    final ok = await confirmBox(context, 'Delete', 'Delete ${supLabel(r)}? Old purchases stay.');
    if (!ok) return;
    await Db2.deleteSupplier(r['id'] as int);
    await _load();
  }

  /// Everything about one supplier: details, how much paid so far, how much owed, every purchase.
  Future<void> _open(Map<String, Object?> r) async {
    final list = await Db2.supplierPurchases(r['id'] as int);
    if (!mounted) return;
    final total = (r['total'] as num).toDouble();
    final pend = (r['pending'] as num).toDouble();
    final paid = total - pend;
    Widget kv(String k, String v, {Color? c}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Text(k, style: const TextStyle(color: kMuted)),
            const Spacer(),
            Text(v, style: TextStyle(fontWeight: FontWeight.w800, color: c)),
          ]),
        );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        title: Text(supLabel(r)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ('${r['supplies'] ?? ''}'.isNotEmpty) Text('Product: ${r['supplies']}'),
                if ('${r['phone'] ?? ''}'.isNotEmpty) Text('Mobile: ${r['phone']}'),
                if ('${r['address'] ?? ''}'.isNotEmpty) Text('Address: ${r['address']}'),
                const Divider(),
                kv('Total purchased so far', 'Rs. ${money0(total)}'),
                kv('Paid / received', 'Rs. ${money0(paid)}', c: kGreen),
                kv('Still to pay (Pending)', 'Rs. ${money0(pend)}', c: pend > 0 ? kRed : null),
                kv('Number of purchases', '${r['cnt']}'),
                const Divider(),
                if (list.isEmpty)
                  const Text('No purchases yet', style: TextStyle(color: kMuted)),
                for (final p in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(
                        child: Text('${fmtDay('${p['date']}')}  \u2022  ${p['items']}',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('Rs. ${money0((p['amount'] as num).toDouble())}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${p['status']}',
                            style: TextStyle(
                                fontSize: 11,
                                color: p['status'] == 'Pending' ? kRed : kGreen)),
                      ]),
                    ]),
                  ),
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
    final small = isNarrow(context);
    return Padding(
      padding: small
          ? const EdgeInsets.fromLTRB(16, 0, 16, 10)
          : const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHead('Supplier Management', actions: [orangeButton('Add Supplier', _edit)]),
          Expanded(
            child: Box(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (!small)
                    const TableHead(
                        ['Name', 'Product', 'Mobile', 'Total paid so far', 'Pending', ''],
                        [3, 3, 3, 3, 2, 2]),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(
                            child: Text('No suppliers yet', style: TextStyle(color: kMuted)))
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (_, i) {
                              final r = rows[i];
                              final pend = (r['pending'] as num).toDouble();
                              final total = (r['total'] as num).toDouble();
                              final supplies = '${r['supplies'] ?? ''}';
                              final phone = '${r['phone'] ?? ''}';
                              if (small) {
                                return phoneRow(
                                  icon: Icons.local_shipping_outlined,
                                  title: supLabel(r),
                                  sub: [
                                    if (phone.isNotEmpty) phone,
                                    'Paid so far \u20B9 ${money0(total)}'
                                        '${pend > 0 ? '   \u2022   Owe \u20B9 ${money0(pend)}' : ''}',
                                  ].join('\n'),
                                  subLines: 3,
                                  subColor: pend > 0 ? kRed : kMuted,
                                  last: i == rows.length - 1,
                                  onTap: () => _open(r),
                                  trailing: [
                                    PopupMenuButton<String>(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.more_vert, size: 22),
                                      onSelected: (v) {
                                        if (v == 'view') _open(r);
                                        if (v == 'edit') _edit(r);
                                        if (v == 'delete') _delete(r);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'view', child: Text('View')),
                                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                                        PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete', style: TextStyle(color: kRed))),
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
                                  Expanded(
                                      flex: 3,
                                      child: InkWell(
                                          onTap: () => _open(r),
                                          child: Text(r['name'] as String,
                                              style: const TextStyle(
                                                  decoration: TextDecoration.underline)))),
                                  Expanded(flex: 3, child: Text(supplies)),
                                  Expanded(flex: 3, child: Text(phone)),
                                  Expanded(
                                      flex: 3,
                                      child: Text('Rs. ${money0(total)}',
                                          style: const TextStyle(fontWeight: FontWeight.w700))),
                                  Expanded(
                                      flex: 2,
                                      child: Text('Rs. ${money0(pend)}',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: pend > 0 ? kRed : kInk))),
                                  Expanded(
                                    flex: 2,
                                    child: Row(children: [
                                      IconButton(
                                          icon: const Icon(Icons.visibility_outlined),
                                          onPressed: () => _open(r)),
                                      IconButton(
                                          icon: const Icon(Icons.edit_outlined),
                                          onPressed: () => _edit(r)),
                                      IconButton(
                                          icon: const Icon(Icons.delete_outline, color: kRed),
                                          onPressed: () => _delete(r)),
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
        ],
      ),
    );
  }
}
