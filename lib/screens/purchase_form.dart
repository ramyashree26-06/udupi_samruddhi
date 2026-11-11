import 'package:flutter/material.dart';

import '../db2.dart';
import '../dialogs.dart';
import '../pics.dart';
import '../theme.dart';
import '../util.dart';
import 'suppliers.dart' show supLabel;

class _ItemRow {
  final name = TextEditingController();
  final qty = TextEditingController();
  final amt = TextEditingController();
  String unit = 'kg';
}

/// Add an outside purchase: items (name, quantity, unit, amount typed by
/// hand), who it was bought from, how it was paid, and a photo of the slip.
class PurchaseForm extends StatefulWidget {
  /// null = new purchase. Otherwise the purchase row being edited.
  final Map<String, Object?>? purchase;
  const PurchaseForm({super.key, this.purchase});
  @override
  State<PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends State<PurchaseForm> {
  static const units = ['kg', 'g', 'L', 'ml', 'pcs', 'packet', 'dozen', 'box'];
  DateTime date = DateTime.now();
  final shop = TextEditingController();
  final note = TextEditingController();
  final rows = <_ItemRow>[_ItemRow()];
  String payMode = 'Cash';
  String slip = '';
  List<String> suppliers = [];
  List<Map<String, Object?>> supList = [];
  String status = 'Received';
  bool get editing => widget.purchase != null;

  @override
  void initState() {
    super.initState();
    final p = widget.purchase;
    if (p != null) {
      date = DateTime.tryParse('${p['date']}') ?? DateTime.now();
      final sh = (p['shop'] ?? '') as String;
      final su = (p['supplier'] ?? '') as String;
      shop.text = sh.isNotEmpty ? sh : (su == '-' ? '' : su);
      note.text = (p['note'] ?? '') as String;
      payMode = ((p['pay_mode'] ?? 'Cash') as String) == 'Online' ? 'Online' : 'Cash';
      slip = (p['slip'] ?? '') as String;
      status = (p['status'] ?? 'Received') as String;
      Db2.purchaseItems(p['id'] as int).then((l) {
        if (!mounted) return;
        setState(() {
          rows.clear();
          for (final i in l) {
            final r = _ItemRow();
            r.name.text = '${i['name']}';
            final q = (i['qty'] as num?) ?? 0;
            r.qty.text = q <= 0 ? '' : (q == q.roundToDouble() ? q.toStringAsFixed(0) : '$q');
            final a = (i['amount'] as num?) ?? 0;
            r.amt.text = a == a.roundToDouble() ? a.toStringAsFixed(0) : '$a';
            final u = '${i['unit']}';
            r.unit = units.contains(u) ? u : 'kg';
            rows.add(r);
          }
          if (rows.isEmpty) rows.add(_ItemRow());
        });
      });
    }
    Db2.suppliers().then((l) {
      if (mounted) {
        setState(() {
          supList = l;
          suppliers = [for (final s in l) supLabel(s)];
        });
      }
    });
  }

  double get total => rows.fold(0.0, (a, r) => a + (double.tryParse(r.amt.text.trim()) ?? 0));

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => date = d);
  }

  Future<void> _save() async {
    final items = <Map<String, Object?>>[];
    for (final r in rows) {
      final n = r.name.text.trim();
      final a = double.tryParse(r.amt.text.trim()) ?? 0;
      if (n.isEmpty && a <= 0) continue;
      if (n.isEmpty || a <= 0) {
        snack(context, 'Each item needs a name and an amount');
        return;
      }
      items.add({
        'name': n,
        'qty': double.tryParse(r.qty.text.trim()) ?? 0,
        'unit': r.unit,
        'amount': a,
      });
    }
    if (items.isEmpty) {
      snack(context, 'Add at least one item with its amount');
      return;
    }
    // link the purchase to a saved supplier when the name matches
    int? supId;
    final typed = shop.text.trim().toLowerCase();
    if (typed.isNotEmpty) {
      for (final sp in supList) {
        if (supLabel(sp).toLowerCase() == typed) supId = sp['id'] as int;
      }
      if (supId == null) {
        for (final sp in supList) {
          if ('${sp['name']}'.trim().toLowerCase() == typed) supId = sp['id'] as int;
        }
      }
    }
    if (editing) {
      await Db2.updatePurchaseFull(
        supplierId: supId,
        id: widget.purchase!['id'] as int,
        date: dayStr(date),
        shop: shop.text.trim(),
        items: items,
        total: r2(total),
        payMode: payMode,
        slip: slip,
        note: note.text.trim(),
        status: status,
      );
      if (mounted) Navigator.pop(context, true);
      return;
    }
    await Db2.addPurchaseFull(
      supplierId: supId,
      date: dayStr(date),
      shop: shop.text.trim(),
      items: items,
      total: r2(total),
      payMode: payMode,
      slip: slip,
      note: note.text.trim(),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit purchase' : 'Add purchase')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('Date: ${fmtDay(dayStr(date))}'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: shop,
              decoration: const InputDecoration(labelText: 'Bought from (pick a name below or type)'),
            ),
            if (suppliers.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in suppliers)
                    ActionChip(label: Text(s), onPressed: () => setState(() => shop.text = s)),
                ],
              ),
            ],
            const SizedBox(height: 18),
            const Text('Items', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            for (var i = 0; i < rows.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: kLine),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: rows[i].name,
                          decoration: InputDecoration(labelText: 'Item ${i + 1} (like Milk)'),
                        ),
                      ),
                      if (rows.length > 1)
                        IconButton(
                          icon: const Icon(Icons.close, color: kRed),
                          onPressed: () => setState(() => rows.removeAt(i)),
                        ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: rows[i].qty,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Quantity'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: rows[i].unit,
                          decoration: const InputDecoration(labelText: 'Unit'),
                          items: [for (final u in units) DropdownMenuItem(value: u, child: Text(u))],
                          onChanged: (v) => setState(() => rows[i].unit = v ?? 'kg'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: rows[i].amt,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Amount (Rs.)'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () => setState(() => rows.add(_ItemRow())),
              icon: const Icon(Icons.add),
              label: const Text('Add another item'),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD9AF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Text('Total',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                Text('Rs. ${money(r2(total))}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              ]),
            ),
            const SizedBox(height: 16),
            const Text('Paid by', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final m in const ['Cash', 'Online'])
                ChoiceChip(
                  label: Text(m),
                  selected: payMode == m,
                  selectedColor: kOrange,
                  labelStyle: TextStyle(color: payMode == m ? Colors.white : kInk),
                  onSelected: (_) => setState(() => payMode = m),
                ),
            ]),
            if (editing) ...[
              const SizedBox(height: 16),
              const Text('Goods', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final m in const ['Received', 'Pending'])
                  ChoiceChip(
                    label: Text(m),
                    selected: status == m,
                    selectedColor: kOrange,
                    labelStyle: TextStyle(color: status == m ? Colors.white : kInk),
                    onSelected: (_) => setState(() => status = m),
                  ),
              ]),
              const Text('Received = items have come. Pending = not delivered yet.',
                  style: TextStyle(color: kMuted, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            const Text('Bill / slip photo', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Row(children: [
              if (slip.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: fileImage(slip, width: 72, height: 72),
                ),
              if (slip.isNotEmpty) const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final r = await Pics.pick(context, 'slip');
                  if (r != null) setState(() => slip = r);
                },
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(slip.isEmpty ? 'Add slip photo' : 'Change photo'),
              ),
              if (slip.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => slip = ''),
                  child: const Text('Remove'),
                ),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: kGreen, minimumSize: const Size(0, 50)),
              onPressed: _save,
              child: Text(editing ? 'Save changes' : 'Save purchase'),
            ),
          ],
        ),
      ),
    );
  }
}
