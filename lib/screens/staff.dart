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
    if (mounted) setState(() => rows = r);
  }

  bool get _isAdmin => currentRole.value == 'Admin';

  Future<void> _edit([Map<String, Object?>? r]) async {
    final roles = [for (final x in await Db2.roles()) x['name'] as String];
    if (!mounted) return;
    final isMainAdmin =
        r != null && (r['username'] as String).toLowerCase() == 'admin';
    final hasLogin = r != null && (r['pass_hash'] as String).isNotEmpty;
    final v = await askFields(context, r == null ? 'Add staff' : 'Edit staff', [
      FieldSpec('name', 'Name', initial: r == null ? '' : r['name'] as String),
      FieldSpec('role', 'Role',
          options: isMainAdmin ? const ['Admin'] : roles,
          initial: isMainAdmin ? 'Admin' : (r == null ? 'Cashier' : r['role'] as String)),
      FieldSpec('phone', 'Phone', initial: r == null ? '' : r['phone'] as String),
      // Only the Admin can see and change login names and passwords.
      if (_isAdmin && !isMainAdmin)
        FieldSpec('username', 'Username (required)',
            initial: r == null ? '' : r['username'] as String),
      if (_isAdmin)
        FieldSpec('password',
            hasLogin ? 'New password (leave empty to keep the old one)' : 'Password (required)',
            secret: true),
      FieldSpec('active', 'Status',
          options: isMainAdmin ? const ['Active'] : const ['Active', 'Inactive'],
          initial: r == null || (r['active'] as int) == 1 ? 'Active' : 'Inactive'),
    ]);
    if (v == null || v['name']!.isEmpty) return;
    String? username;
    String? password;
    if (_isAdmin) {
      username = isMainAdmin ? null : (v['username'] ?? '').trim();
      password = v['password'] ?? '';
      final uname = isMainAdmin ? 'admin' : username!;
      if (password.isNotEmpty && password.length < 4) {
        if (mounted) snack(context, 'Password must be at least 4 characters.');
        return;
      }
      if (uname.isNotEmpty && await Db2.usernameTaken(uname, r == null ? null : r['id'] as int)) {
        if (mounted) snack(context, 'That username is already used.');
        return;
      }
      if (uname.isEmpty) {
        if (mounted) snack(context, 'Username is required for every employee.');
        return;
      }
      if (password.isEmpty && !hasLogin) {
        if (mounted) snack(context, 'Password is required for every employee.');
        return;
      }
    }
    await Db2.saveStaff(
      r == null ? null : r['id'] as int,
      v['name']!,
      isMainAdmin ? 'Admin' : (v['role']!.isEmpty ? 'Cashier' : v['role']!),
      v['phone']!,
      isMainAdmin ? true : v['active'] != 'Inactive',
      r == null ? '' : r['pin'] as String,
      username: username,
      password: password,
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
          PageHead('Staff & Users',
              actions: [if (_isAdmin) orangeButton('Add Staff', _edit)]),
          Expanded(
            child: Box(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (!small)
                    const TableHead(['Name', 'Role', 'Phone', 'Username', 'Status', ''],
                        [3, 2, 3, 1, 2, 2]),
                  Expanded(
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        final active = (r['active'] as int) == 1;
                        if (small) {
                          final uname = r['username'] as String;
                          return phoneRow(
                            icon: Icons.badge_outlined,
                            title: r['name'] as String,
                            sub: '${r['role']}${(r['phone'] as String).isEmpty ? '' : '  \u2022  ${r['phone']}'}${uname.isEmpty ? '  \u2022  NO LOGIN YET' : '  \u2022  $uname'}',
                            last: i == rows.length - 1,
                            trailing: [
                              statusPill(active ? 'Active' : 'Inactive', active ? kGreen : kRed),
                              if (_isAdmin)
                              IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () => _edit(r)),
                              if (_isAdmin && (r['username'] as String).toLowerCase() != 'admin')
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
                                child: Text((r['username'] as String).isEmpty ? 'No login' : r['username'] as String)),
                            Expanded(
                                flex: 2,
                                child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Pill(active ? 'Active' : 'Inactive',
                                        active ? kGreen : kRed))),
                            Expanded(
                              flex: 2,
                              child: Row(children: [
                                if (_isAdmin)
                                IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _edit(r)),
                                if (_isAdmin && (r['username'] as String).toLowerCase() != 'admin')
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
          const Text(
              'Everyone signs in with a username and password. Only the Admin can add users or change passwords here.',
              style: const TextStyle(color: kMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
