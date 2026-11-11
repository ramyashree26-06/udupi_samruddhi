import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../db.dart';
import '../db2.dart';
import '../dialogs.dart';
import '../models.dart';
import '../nav.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

/// Table floor: Free, Occupied (has a saved order), Reserved, Cleaning.
class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});
  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  Map<String, BillRow> running = {};
  Map<int, Map<String, Object?>> states = {};
  bool listView = false;
  bool editMode = false; // true: tables can be dragged and edited
  int? selId; // (not used any more)
  int? moveId; // table being moved right now
  Offset? moveFrom; // where it was when the move started
  List<TableDef> list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await Db.drafts();
    final m = <String, BillRow>{};
    for (final r in d) {
      if (r.label.startsWith('Table: ')) m[r.label] = r;
    }
    final st = await Db2.tableStates();
    if (mounted) {
      setState(() {
        running = m;
        states = st;
        list = Db2.tableList();
      });
    }
  }

  String _state(TableDef t) {
    if (running.containsKey('Table: ${t.name}')) return 'Occupied';
    final s = states[t.id];
    return s == null ? 'Free' : s['state'] as String;
  }

  Color _color(String s) {
    switch (s) {
      case 'Occupied':
        return kRed;
      case 'Reserved':
        return const Color(0xFF7B4DD8);
      case 'Cleaning':
        return const Color(0xFFE0A100);
      default:
        return kGreen;
    }
  }

  /// Add a table: number, chairs, shape and size are chosen right here.
  Future<void> _add() => _editTable(null);

  void _upd(TableDef t, TableDef n, {bool save = true}) {
    setState(() => list = [for (final x in list) x.id == t.id ? n : x]);
    if (save) Db2.saveTableList(list);
  }

  /// Edit panel: sits UNDER the floor so the table stays visible while you change it.
  Widget _panel() {
    final i = list.indexWhere((x) => x.id == selId);
    if (i < 0) return const SizedBox.shrink();
    final t = list[i];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kOrange),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            SizedBox(
              width: 86,
              child: TextFormField(
                key: ValueKey('name${t.id}'),
                initialValue: t.name,
                decoration: const InputDecoration(
                    labelText: 'Number', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) {
                  final n = v.trim();
                  if (n.isEmpty) return;
                  if (list.any((x) => x.id != t.id && x.name.toLowerCase() == n.toLowerCase())) {
                    return;
                  }
                  _upd(list.firstWhere((x) => x.id == t.id), list.firstWhere((x) => x.id == t.id).copy(name: n));
                },
              ),
            ),
            const SizedBox(width: 6),
            const Text('Chairs', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: t.chairs > 1 ? () => _upd(t, t.copy(chairs: t.chairs - 1)) : null,
            ),
            Text('${t.chairs}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_circle_outline),
              onPressed: t.chairs < 12 ? () => _upd(t, t.copy(chairs: t.chairs + 1)) : null,
            ),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => selId = null),
            ),
          ]),
          Row(children: [
            ChoiceChip(
                label: const Text('Square'),
                visualDensity: VisualDensity.compact,
                selected: t.shape == 'square',
                onSelected: (_) => _upd(t, t.copy(shape: 'square'))),
            const SizedBox(width: 6),
            ChoiceChip(
                label: const Text('Round'),
                visualDensity: VisualDensity.compact,
                selected: t.shape == 'round',
                onSelected: (_) => _upd(t, t.copy(shape: 'round'))),
            Expanded(
              child: Slider(
                value: t.size.clamp(0.4, 2.0).toDouble(),
                min: 0.4,
                max: 2.0,
                divisions: 16,
                label: '${(t.size * 100).round()}%',
                activeColor: kOrange,
                onChanged: (v) => _upd(t, t.copy(size: v), save: false),
                onChangeEnd: (_) => Db2.saveTableList(list),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Delete table',
              icon: const Icon(Icons.delete_outline, color: kRed),
              onPressed: () => _delete(t),
            ),
          ]),
        ],
      ),
    );
  }

  /// Add a table (t == null) or edit one: number/name, chairs, shape.
  Future<void> _editTable(TableDef? t) async {
    var next = list.length + 1;
    while (list.any((x) => x.name == '$next')) {
      next++;
    }
    final nameC = TextEditingController(text: t?.name ?? '$next');
    var chairs = t?.chairs ?? 4;
    var shape = t?.shape ?? 'square';
    var size = t?.size ?? 1.0;
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          scrollable: true,
          title: Text(t == null ? 'Add table' : 'Edit table'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameC,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Table number or name'),
                ),
                const SizedBox(height: 16),
                const Text('Chairs', style: TextStyle(fontWeight: FontWeight.w800)),
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: chairs > 1 ? () => setS(() => chairs--) : null,
                  ),
                  Text('$chairs',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: chairs < 12 ? () => setS(() => chairs++) : null,
                  ),
                ]),
                Wrap(spacing: 8, children: [
                  for (final c in const [2, 4, 6, 8])
                    ChoiceChip(
                      label: Text('$c'),
                      selected: chairs == c,
                      onSelected: (_) => setS(() => chairs = c),
                    ),
                ]),
                const SizedBox(height: 16),
                const Text('Shape', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  ChoiceChip(
                      label: const Text('Square'),
                      selected: shape == 'square',
                      onSelected: (_) => setS(() => shape = 'square')),
                  ChoiceChip(
                      label: const Text('Round'),
                      selected: shape == 'round',
                      onSelected: (_) => setS(() => shape = 'round')),
                ]),
                const SizedBox(height: 16),
                Text('Size  (${(size * 100).round()}%)',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Row(children: [
                  const Icon(Icons.table_restaurant_outlined, size: 16),
                  Expanded(
                    child: Slider(
                      value: size,
                      min: 0.4,
                      max: 2.0,
                      divisions: 16,
                      activeColor: kOrange,
                      onChanged: (v) => setS(() => size = v),
                    ),
                  ),
                  const Icon(Icons.table_restaurant_outlined, size: 28),
                ]),
              ],
            ),
          ),
          actions: [
            if (t != null)
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'delete'),
                  child: const Text('Delete', style: TextStyle(color: kRed))),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (res == null) return;
    if (res == 'delete' && t != null) {
      await _delete(t);
      return;
    }
    final name = nameC.text.trim();
    if (name.isEmpty) return;
    if (list.any((x) => x.id != t?.id && x.name.toLowerCase() == name.toLowerCase())) {
      if (mounted) snack(context, 'A table with this name already exists');
      return;
    }
    if (t == null) {
      final id = list.isEmpty ? 1 : list.map((x) => x.id).reduce((p, q) => p > q ? p : q) + 1;
      await Db2.saveTableList(
          [...list, TableDef(id, name, chairs: chairs, shape: shape, size: size)]);
    } else {
      await Db2.saveTableList([
        for (final x in list)
          x.id == t.id ? x.copy(name: name, chairs: chairs, shape: shape, size: size) : x
      ]);
    }
    await _load();
  }

  Future<void> _delete(TableDef t) async {
    final ok = await confirmBox(context, 'Delete table',
        'Delete Table ${t.name}? Old bills are not changed.');
    if (!ok) return;
    await Db2.setTableState(t.id, 'Free', '');
    if (selId == t.id) selId = null;
    await Db2.saveTableList([for (final x in list) if (x.id != t.id) x]);
    await _load();
  }

  Future<void> _tap(TableDef t) async {
    if (editMode) {
      setState(() => selId = t.id);
      return;
    }
    final label = 'Table: ${t.name}';
    final st = _state(t);
    if (st == 'Occupied') {
      await Db.openDraft(running[label]!.id);
      navIndex.value = 1;
      return;
    }
    final pick = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Table ${t.name}  ($st)'),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'order'),
              child: const Text('Start an order')),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'Reserved'),
              child: const Text('Mark Reserved')),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'Cleaning'),
              child: const Text('Mark Cleaning')),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'Free'),
              child: const Text('Mark Free')),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'rename'),
              child: const Text('Edit table (number, chairs, shape, size)')),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Text('Delete table')),
        ],
      ),
    );
    if (pick == null) return;
    if (pick == 'order') {
      cart.setLabel(label);
      cart.setOrderType('Dine In');
      await Db2.setTableState(t.id, 'Free', '');
      navIndex.value = 1;
      return;
    }
    if (pick == 'rename') {
      await _editTable(t);
      return;
    }
    if (pick == 'delete') {
      await _delete(t);
      return;
    }
    await Db2.setTableState(t.id, pick, '');
    await _load();
  }

  Widget _viewBtn(String label, IconData ic, bool on, VoidCallback onTap) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: on ? const Color(0xFFFFEEDD) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: on ? kOrange : kTan, width: on ? 1.6 : 1),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(ic, size: 19, color: on ? kOrange : kInk),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: on ? kOrange : kInk)),
            ]),
          ),
        ),
      );

  IconData _icon(String s) =>
      s == 'Cleaning' ? Icons.cleaning_services_outlined : Icons.table_restaurant_outlined;

  Widget _phone() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: orangeButton('Add Table', _add)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _viewBtn('Floor View', Icons.grid_view_rounded, !listView,
                  () => setState(() => listView = false)),
              const SizedBox(width: 10),
              _viewBtn('List View', Icons.view_list_outlined, listView,
                  () => setState(() => listView = true)),
            ]),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final s in const ['Free', 'Occupied', 'Reserved', 'Cleaning'])
                  Row(children: [
                    Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(color: _color(s), shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(s, style: const TextStyle(fontSize: 12.5)),
                  ]),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: listView ? _list() : _floorPhone()),
          ],
        ),
      );

  Widget _floorPhone() => _floor();

  @override
  Widget build(BuildContext context) {
    if (isNarrow(context)) return _phone();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHead('Table Management', actions: [
            orangeButton('Add Table', _add),
            ChoiceChip(
                label: const Text('Floor View'),
                selected: !listView,
                selectedColor: kOrange,
                labelStyle: TextStyle(color: !listView ? Colors.white : kInk),
                onSelected: (_) => setState(() => listView = false)),
            ChoiceChip(
                label: const Text('List View'),
                selected: listView,
                selectedColor: kOrange,
                labelStyle: TextStyle(color: listView ? Colors.white : kInk),
                onSelected: (_) => setState(() => listView = true)),
          ]),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                for (final s in const ['Free', 'Occupied', 'Reserved', 'Cleaning'])
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Row(children: [
                      Container(
                          width: 10,
                          height: 10,
                          decoration:
                              BoxDecoration(color: _color(s), shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text(s, style: const TextStyle(fontSize: 13)),
                    ]),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: listView ? _list() : _floor()),
        ],
      ),
    );
  }

  Widget _floor() => _canvas();

  /// One table: the table with its chairs around it.
  Widget _tableBox(TableDef t) {
    final st = _state(t);
    final c = _color(st);
    final r = running['Table: ${t.name}'];
    final round = t.shape == 'round';
    return CustomPaint(
      painter: _ChairPainter(t.chairs, c, t.size),
      child: Center(
        child: Container(
          width: 68 * t.size,
          height: 68 * t.size,
          padding: EdgeInsets.all(4 * t.size),
          decoration: BoxDecoration(
            color: c.withOpacity(0.12),
            border: Border.all(color: c, width: 2),
            shape: round ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: round ? null : BorderRadius.circular(12),
          ),
          child: FittedBox(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('T${t.name}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text(
                    r != null ? '${DateTime.now().difference(r.createdAt).inMinutes} min' : st,
                    style: TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The floor: tables sit where you put them. In Edit layout mode they can be
  /// dragged; the place is saved.
  Widget _canvas() => LayoutBuilder(builder: (context, cons) {
        const s = 120.0;
        final w = cons.maxWidth, h = cons.maxHeight;
        final cols = math.max(1, ((w - 10) / (s + 6)).floor());
        final rowsN = (list.length / cols).ceil();
        final stepY = rowsN <= 1 ? s + 6 : ((h - s - 10) / (rowsN - 1)).clamp(60.0, s + 6);
        double maxX(TableDef t) => math.max(0.0, w - s * t.size);
        double maxY(TableDef t) => math.max(0.0, h - s * t.size);
        Offset pos(int i, TableDef t) {
          if (t.fx != null && t.fy != null) {
            return Offset(t.fx! * maxX(t), t.fy! * maxY(t));
          }
          return Offset(((i % cols) * (s + 6) + 5).clamp(0.0, maxX(t)).toDouble(),
              ((i ~/ cols) * stepY + 5).clamp(0.0, maxY(t)).toDouble());
        }

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFAF7F2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: editMode ? kOrange : kLine, width: editMode ? 2 : 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              children: [
                if (list.isEmpty)
                  const Center(child: Text('No tables yet. Press Add Table.')),
                if (list.isNotEmpty)
                  const Positioned(
                    left: 12,
                    bottom: 6,
                    child: Text('Press and hold a table, then drag to move it',
                        style: TextStyle(color: kMuted, fontSize: 11.5)),
                  ),
                for (var i = 0; i < list.length; i++)
                  Positioned(
                    left: pos(i, list[i]).dx,
                    top: pos(i, list[i]).dy,
                    width: s * list[i].size,
                    height: s * list[i].size,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _tap(list[i]),
                      onLongPressStart: (_) => setState(() {
                        moveId = list[i].id;
                        moveFrom = pos(i, list[i]);
                      }),
                      onLongPressMoveUpdate: (d) {
                        if (moveFrom == null) return;
                        final tx = maxX(list[i]), ty = maxY(list[i]);
                        final np = moveFrom! + d.offsetFromOrigin;
                        final nx = tx <= 0 ? 0.0 : (np.dx / tx).clamp(0.0, 1.0);
                        final ny = ty <= 0 ? 0.0 : (np.dy / ty).clamp(0.0, 1.0);
                        setState(() => list[i] = list[i].copy(fx: nx, fy: ny));
                      },
                      onLongPressEnd: (_) {
                        setState(() {
                          moveId = null;
                          moveFrom = null;
                        });
                        Db2.saveTableList(list);
                      },
                      child: Container(
                        decoration: moveId == list[i].id
                            ? BoxDecoration(
                                border: Border.all(color: kOrange, width: 2),
                                borderRadius: BorderRadius.circular(12))
                            : null,
                        child: Stack(children: [
                          Positioned.fill(child: _tableBox(list[i])),
                          Positioned(
                            right: 4,
                            top: 4,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => _editTable(list[i]),
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: kTan)),
                                child: const Icon(Icons.edit, size: 14, color: kInk),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      });

  Widget _list() => Box(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            const TableHead(['Table', 'Status', 'Amount', 'Open for'], [2, 3, 2, 2]),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final t = list[i];
                  final st = _state(t);
                  final r = running['Table: ${t.name}'];
                  return InkWell(
                    onTap: () => _tap(t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: kLine))),
                      child: Row(children: [
                        Expanded(flex: 2, child: Text('Table ${t.name}')),
                        Expanded(
                            flex: 3,
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: Pill(st, _color(st)))),
                        Expanded(flex: 2, child: Text(r == null ? '-' : 'Rs. ${money0(r.total)}')),
                        Expanded(
                            flex: 2,
                            child: Text(r == null
                                ? '-'
                                : '${DateTime.now().difference(r.createdAt).inMinutes} min')),
                        IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Edit table',
                            onPressed: () => _editTable(t),
                            icon: const Icon(Icons.edit_outlined, size: 18)),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
}


/// Draws the chairs evenly around a table.
class _ChairPainter extends CustomPainter {
  final int n;
  final Color color;
  final double scale;
  _ChairPainter(this.n, this.color, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color.withOpacity(0.55);
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + 2 * math.pi * i / n;
      canvas.save();
      canvas.translate(c.dx + 47 * scale * math.cos(a), c.dy + 47 * scale * math.sin(a));
      canvas.rotate(a + math.pi / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 20 * scale, height: 12 * scale),
            const Radius.circular(4)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ChairPainter o) => o.n != n || o.color != color || o.scale != scale;
}
