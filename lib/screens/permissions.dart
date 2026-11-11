import 'package:flutter/material.dart';

import '../db2.dart';
import '../dialogs.dart';
import '../nav.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});
  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db2.roles();
    if (mounted) setState(() => rows = r);
  }

  Future<void> _edit([Map<String, Object?>? r]) async {
    final isAdmin = r != null && r['name'] == 'Admin';
    var name = r == null ? '' : r['name'] as String;
    final nameCtrl = TextEditingController(text: name);
    final picked = r == null
        ? <String>{}
        : Db2.permSet(r['perms'] as String).toSet();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(r == null ? 'Add role' : 'Edit role'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    enabled: !isAdmin,
                    decoration: const InputDecoration(labelText: 'Role name'),
                  ),
                  const SizedBox(height: 10),
                  const Text('Pages this role can open:'),
                  if (isAdmin)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Admin can always open every page.',
                          style: TextStyle(color: kMuted)),
                    )
                  else
                    for (final k in Db2.allModules)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(kModuleInfo[k]!.title),
                        value: picked.contains(k),
                        onChanged: (v) => setS(() {
                          if (v == true) {
                            picked.add(k);
                          } else {
                            picked.remove(k);
                          }
                        }),
                      ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (result != true || name.isEmpty) return;
    await Db2.saveRole(
      r == null ? null : r['id'] as int,
      name,
      isAdmin ? 'all' : Db2.allModules.where(picked.contains).join(','),
    );
    await _load();
  }

  String _summary(String perms) {
    final s = Db2.permSet(perms);
    if (s.length == Db2.allModules.length) return 'All pages';
    return Db2.allModules
        .where(s.contains)
        .map((k) => kModuleInfo[k]!.menu)
        .join(', ');
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
          PageHead('User Roles & Permissions', actions: [orangeButton('Add Role', _edit)]),
          Expanded(
            child: Box(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (!small) const TableHead(['Role', 'Access Permissions', ''], [2, 8, 2]),
                  Expanded(
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        final protected = r['name'] == 'Admin';
                        if (small) {
                          return phoneRow(
                            icon: Icons.admin_panel_settings_outlined,
                            title: r['name'] as String,
                            sub: _summary(r['perms'] as String),
                            subLines: 3,
                            last: i == rows.length - 1,
                            trailing: [
                              IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () => _edit(r)),
                              if (!protected)
                                IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.delete_outline, color: kRed, size: 20),
                                    onPressed: () async {
                                      final ok = await confirmBox(context, 'Delete', 'Delete role ${r['name']}?');
                                      if (!ok) return;
                                      await Db2.deleteRole(r['id'] as int);
                                      await _load();
                                    }),
                            ],
                          );
                        }
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: kLine))),
                          child: Row(children: [
                            Expanded(
                                flex: 2,
                                child: Text(r['name'] as String,
                                    style: const TextStyle(fontWeight: FontWeight.w700))),
                            Expanded(flex: 8, child: Text(_summary(r['perms'] as String))),
                            Expanded(
                              flex: 2,
                              child: Row(children: [
                                IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _edit(r)),
                                if (!protected)
                                  IconButton(
                                      icon: const Icon(Icons.delete_outline, color: kRed),
                                      onPressed: () async {
                                        final ok = await confirmBox(
                                            context, 'Delete', 'Delete role ${r['name']}?');
                                        if (!ok) return;
                                        await Db2.deleteRole(r['id'] as int);
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
        ],
      ),
    );
  }
}
