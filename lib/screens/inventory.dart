import 'package:flutter/material.dart';

import '../db2.dart';
import '../dialogs.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db2.stock();
    if (mounted) setState(() => rows = r);
  }

  bool _low(Map<String, Object?> r) =>
      (r['qty'] as num).toDouble() <= (r['min_qty'] as num).toDouble();

  Future<void> _edit([Map<String, Object?>? r]) async {
    final v = await askFields(context, r == null ? 'Add stock item' : 'Edit stock item', [
      FieldSpec('name', 'Item name', initial: r == null ? '' : r['name'] as String),
      FieldSpec('qty', 'Quantity available',
          number: true, initial: r == null ? '' : money0((r['qty'] as num).toDouble())),
      const FieldSpec('unit', 'Unit', options: ['kg', 'g', 'L', 'ml', 'pcs', 'packet']),
      FieldSpec('min', 'Low-stock level (warn at or below)',
          number: true, initial: r == null ? '' : money0((r['min_qty'] as num).toDouble())),
    ]);
    if (v == null || v['name']!.isEmpty) return;
    await Db2.saveStock(
      r == null ? null : r['id'] as int,
      v['name']!,
      double.tryParse(v['qty']!) ?? 0,
      v['unit']!.isEmpty ? (r == null ? 'kg' : r['unit'] as String) : v['unit']!,
      double.tryParse(v['min']!) ?? 0,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final lowCount = rows.where(_low).length;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHead('Inventory / Stock', actions: [
            if (lowCount > 0) Pill('Low Stock ($lowCount)', const Color(0xFFE0A100)),
            orangeButton('Add Stock', _edit),
          ]),
          Expanded(
            child: Box(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  const TableHead(['Item', 'Available', 'Unit', 'Status', ''], [4, 2, 2, 2, 2]),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(
                            child: Text('No stock items yet', style: TextStyle(color: kMuted)))
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (_, i) {
                              final r = rows[i];
                              final low = _low(r);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: kLine))),
                                child: Row(children: [
                                  Expanded(flex: 4, child: Text(r['name'] as String)),
                                  Expanded(
                                      flex: 2,
                                      child: Text(money0((r['qty'] as num).toDouble()),
                                          style: const TextStyle(fontWeight: FontWeight.w700))),
                                  Expanded(flex: 2, child: Text(r['unit'] as String)),
                                  Expanded(
                                      flex: 2,
                                      child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Pill(low ? 'Low Stock' : 'In Stock',
                                              low ? const Color(0xFFE0A100) : kGreen))),
                                  Expanded(
                                    flex: 2,
                                    child: Row(children: [
                                      IconButton(
                                          icon: const Icon(Icons.edit_outlined),
                                          onPressed: () => _edit(r)),
                                      IconButton(
                                          icon: const Icon(Icons.delete_outline, color: kRed),
                                          onPressed: () async {
                                            final ok = await confirmBox(context, 'Delete',
                                                'Delete ${r['name']}?');
                                            if (!ok) return;
                                            await Db2.deleteStock(r['id'] as int);
                                            await _load();
                                          }),
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
          const Text(
              'Stock is typed in by you (use Edit to change the quantity after buying or using).',
              style: TextStyle(color: kMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
