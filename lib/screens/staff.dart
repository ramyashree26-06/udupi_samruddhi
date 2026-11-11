import 'package:flutter/material.dart';

import '../db2.dart';
import '../dialogs.dart';
import '../nav.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});
  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db2.staff();
    pinOn.value = await Db2.pinLoginOn();
    if (mounted) setState(() => rows = r);
  }

  Future<void> _edit([Map<String, Object?>? r]) async {
    final roles = [for (final x in await Db2.roles()) x['name'] as String];
    if (!mounted) return;
    final v = await askFields(context, r == null ? 'Add staff' : 'Edit staff', [
      FieldSpec('name', 'Name', initial: r == null ? '' : r['name'] as String),
      FieldSpec('role', 'Role',
          options: roles, initial: r == null ? 'Cashier' : r['role'] as String),
      FieldSpec('phone', 'Phone', initial: r == null ? '' : r['phone'] as String),
      FieldSpec('pin', 'PIN (4 to 6 numbers, leave empty for no PIN)',
          secret: true, number: true, initial: r == null ? '' : r['pin'] as String),
      FieldSpec('active', 'Status',
          options: const ['Active', 'Inactive'],
          initial: r == null || (r['active'] as int) == 1 ? 'Active' : 'Inactive'),
    ]);
    if (v == null || v['name']!.isEmpty) return;
    await Db2.saveStaff(
      r == null ? null : r['id'] as int,
      v['name']!,
      v['role']!.isEmpty ? 'Cashier' : v['role']!,
      v['phone']!,
      v['active'] != 'Inactive',
      v['pin']!,
    );
    await _load();
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
          PageHead('Staff & Users', actions: [orangeButton('Add Staff', _edit)]),
          Expanded(
            child: Box(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (!small)
                    const TableHead(['Name', 'Role', 'Phone', 'PIN', 'Status', ''],
                        [3, 2, 3, 1, 2, 2]),
                  Expanded(
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        final active = (r['active'] as int) == 1;
                        if (small) {
                          final pinOnRow = (r['pin'] as String).isNotEmpty;
                          return phoneRow(
                            icon: Icons.badge_outlined,
                            title: r['name'] as String,
                            sub: '${r['role']}${(r['phone'] as String).isEmpty ? '' : '  \u2022  ${r['phone']}'}${pinOnRow ? '  \u2022  PIN set' : ''}',
                            last: i == rows.length - 1,
                            trailing: [
                              statusPill(active ? 'Active' : 'Inactive', active ? kGreen : kRed),
                              IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () => _edit(r)),
                              IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.delete_outline, color: kRed, size: 20),
                                  onPressed: () async {
                                    final ok = await confirmBox(context, 'Delete', 'Delete ${r['name']}?');
                                    if (!ok) return;
                                    await Db2.deleteStaff(r['id'] as int);
                                    await _load();
                                  }),
                            ],
                          );
                        }
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: kLine))),
                          child: Row(children: [
                            Expanded(flex: 3, child: Text(r['name'] as String)),
                            Expanded(flex: 2, child: Text(r['role'] as String)),
                            Expanded(flex: 3, child: Text(r['phone'] as String)),
                            Expanded(
                                flex: 1,
                                child: Text((r['pin'] as String).isEmpty ? '-' : '****')),
                            Expanded(
                                flex: 2,
                                child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Pill(active ? 'Active' : 'Inactive',
                                        active ? kGreen : kRed))),
                            Expanded(
                              flex: 2,
                              child: Row(children: [
                                IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _edit(r)),
                                IconButton(
                                    icon: const Icon(Icons.delete_outline, color: kRed),
                                    onPressed: () async {
                                      final ok = await confirmBox(
                                          context, 'Delete', 'Delete ${r['name']}?');
                                      if (!ok) return;
                                      await Db2.deleteStaff(r['id'] as int);
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
          const SizedBox(height: 8),
          Text(
              'Once anyone has a PIN, the app asks for a PIN when it opens. ' +
                  (isAndroid
                      ? 'Forgot the PIN? Ask the Admin to change it here, or restore a backup.'
                      : 'Forgot the PIN? Make an empty file named reset_pin.txt in Documents\\HotelBilling and open the app again.'),
              style: const TextStyle(color: kMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
