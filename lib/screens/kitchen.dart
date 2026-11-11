import 'dart:async';

import 'package:flutter/material.dart';

import '../db2.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

/// Kitchen Display: orders sent with "KOT & Print" appear here.
class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});
  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  List<KOrder> orders = [];
  String tab = 'All';
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final o = await Db2.kitchenOrders();
    if (mounted) setState(() => orders = o);
  }

  int _n(String st) => orders.where((o) => o.kstatus == st).length;

  Future<void> _move(KOrder o, String st) async {
    await Db2.setKStatus(o.id, st);
    await _load();
  }

  Color _phoneColor(String k) => k == 'new'
      ? const Color(0xFF1E88E5)
      : (k == 'preparing' ? const Color(0xFFE0A100) : kGreen);

  Widget _phoneCard(KOrder o) {
    final color = _phoneColor(o.kstatus);
    final sub = o.label.isEmpty
        ? o.orderType
        : '${o.label.replaceFirst('Table: ', 'Table : T')}   ${o.orderType}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kWarmLine),
        boxShadow: const [BoxShadow(color: Color(0x0F8A5A2B), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF0E2), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.receipt_long_outlined, color: kOrange, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('#KOT-${o.id.toString().padLeft(4, '0')}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            Text(fmtTime(o.createdAt), style: const TextStyle(fontSize: 12.5, color: kMuted)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(sub,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kMuted, fontSize: 12.5)),
            ),
            statusPill(o.kstatus[0].toUpperCase() + o.kstatus.substring(1), color),
          ]),
          const Divider(height: 18, color: kWarmLine),
          for (final i in o.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${i.qty} \u00D7 ${i.name}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  if (i.note.isNotEmpty)
                    Text('Notes: ${i.note}',
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                ],
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  backgroundColor: o.kstatus == 'ready' ? kGreen : kOrange),
              onPressed: () => _move(
                  o,
                  o.kstatus == 'new'
                      ? 'preparing'
                      : (o.kstatus == 'preparing' ? 'ready' : 'done')),
              child: Text(o.kstatus == 'new'
                  ? 'Start'
                  : (o.kstatus == 'preparing' ? 'Mark Ready' : 'Completed')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phone(List<KOrder> shown) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in const ['All', 'New', 'Preparing', 'Ready'])
                      phoneChip(
                          t == 'All'
                              ? 'All (${orders.length})'
                              : '$t (${_n(t.toLowerCase())})',
                          tab == t,
                          () => setState(() => tab = t)),
                  ],
                ),
              ),
              IconButton(
                  onPressed: _load,
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh, size: 24)),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: shown.isEmpty
                  ? const Center(
                      child: Text('No orders in the kitchen', style: TextStyle(color: kMuted)))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, i) => _phoneCard(shown[i]),
                    ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final shown = tab == 'All'
        ? orders
        : orders.where((o) => o.kstatus == tab.toLowerCase()).toList();
    final small = isNarrow(context);
    if (small) return _phone(shown);
    return Padding(
      padding: EdgeInsets.all(small ? 10 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHead('Kitchen Orders (KOT)', inline: true, actions: [
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ]),
          Wrap(
            spacing: small ? 4 : 8,
            children: [
              for (final t in const ['All', 'New', 'Preparing', 'Ready'])
                ChoiceChip(
                  visualDensity: small ? VisualDensity.compact : null,
                  materialTapTargetSize:
                      small ? MaterialTapTargetSize.shrinkWrap : null,
                  labelPadding: small ? const EdgeInsets.symmetric(horizontal: 2) : null,
                  label: Text(t == 'All'
                      ? 'All (${orders.length})'
                      : '$t (${_n(t.toLowerCase())})'),
                  selected: tab == t,
                  selectedColor: kOrange,
                  labelStyle: TextStyle(color: tab == t ? Colors.white : kInk),
                  onSelected: (_) => setState(() => tab = t),
                ),
            ],
          ),
          SizedBox(height: small ? 8 : 14),
          Expanded(
            child: shown.isEmpty
                ? const Center(
                    child: Text('No orders in the kitchen',
                        style: TextStyle(color: kMuted)))
                : GridView.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: small ? 210 : 300,
                      mainAxisExtent: small ? 250 : 300,
                      crossAxisSpacing: small ? 8 : 14,
                      mainAxisSpacing: small ? 8 : 14,
                    ),
                    itemCount: shown.length,
                    itemBuilder: (_, i) => _card(shown[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(KOrder o) {
    final color = o.kstatus == 'new'
        ? const Color(0xFFE0A100)
        : (o.kstatus == 'preparing' ? kOrange : kGreen);
    final label = o.label.isEmpty ? o.orderType : o.label.replaceFirst('Table: ', 'Table ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color, width: 1.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Pill(o.kstatus[0].toUpperCase() + o.kstatus.substring(1), color),
          ]),
          Text(
              '${fmtTime(o.createdAt)}  (${DateTime.now().difference(o.createdAt).inMinutes} min ago)',
              style: const TextStyle(color: kMuted, fontSize: 12)),
          const Divider(),
          Expanded(
            child: ListView(
              children: [
                for (final i in o.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i.qty} x ${i.name}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (i.note.isNotEmpty)
                          Text('Notes: ${i.note}',
                              style: const TextStyle(color: kMuted, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: o.kstatus == 'ready' ? kGreen : kOrange),
              onPressed: () => _move(
                  o,
                  o.kstatus == 'new'
                      ? 'preparing'
                      : (o.kstatus == 'preparing' ? 'ready' : 'done')),
              child: Text(o.kstatus == 'new'
                  ? 'Start'
                  : (o.kstatus == 'preparing' ? 'Mark Ready' : 'Completed')),
            ),
          ),
        ],
      ),
    );
  }
}
