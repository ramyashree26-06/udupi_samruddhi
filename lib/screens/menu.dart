import 'package:flutter/material.dart';

import '../db.dart';
import '../dialogs.dart';
import '../menu_import.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});
  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  List<Section> sections = [];
  List<String> groups = [];
  List<Dish> dishes = [];
  int idx = 0;
  String group = '';
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Section? get sec => sections.isEmpty ? null : sections[idx];

  Future<void> _init() async {
    sections = await Db.sections();
    if (idx >= sections.length) idx = 0;
    await _reload();
  }

  Future<void> _reload() async {
    if (sec == null) {
      setState(() {
        groups = [];
        dishes = [];
      });
      return;
    }
    final g = await Db.groups(sec!.id);
    if (!g.contains(group)) group = '';
    var list = await Db.dishes(sectionId: sec!.id, search: search.text.trim());
    if (group.isNotEmpty) list = list.where((d) => d.group == group).toList();
    if (mounted) {
      setState(() {
        groups = g;
        dishes = list;
      });
    }
  }


  Future<void> _addSection() async {
    final n = await askText(context, 'New section', label: 'Section name');
    if (n == null || n.isEmpty) return;
    await Db.addSection(n);
    idx = sections.length;
    await _init();
  }

  Future<void> _renameSection() async {
    final s = sec;
    if (s == null) return;
    final n = await askText(context, 'Rename section', initial: s.name);
    if (n == null || n.isEmpty) return;
    await Db.renameSection(s.id, n);
    await _init();
  }

  Future<void> _deleteSection() async {
    final s = sec;
    if (s == null) return;
    final ok = await confirmBox(context, 'Delete section',
        'Delete "${s.name}" and all its dishes? Old bills stay safe.');
    if (!ok) return;
    await Db.deleteSection(s.id);
    idx = 0;
    await _init();
  }

  Future<void> _addDish() async {
    final s = sec;
    if (s == null) return;
    final f = await askDishForm(context,
        title: 'Add dish',
        sections: sections,
        sectionId: s.id,
        groupsOf: Db.groups,
        group: group);
    if (f == null) return;
    await Db.addDish(f.sectionId, f.name, f.price, group: f.group, photo: f.photo);
    await _reload();
  }

  Future<void> _editDish(Dish d) async {
    final f = await askDishForm(context,
        title: 'Edit dish',
        sections: sections,
        sectionId: d.sectionId,
        groupsOf: Db.groups,
        name: d.name,
        price: d.price,
        group: d.group,
        photo: d.photo);
    if (f == null) return;
    await Db.updateDish(d.id,
        name: f.name, price: f.price, group: f.group, sectionId: f.sectionId, photo: f.photo);
    await _reload();
  }

  Future<void> _deleteDish(Dish d) async {
    final ok = await confirmBox(context, 'Delete dish', 'Delete "${d.name}"?');
    if (!ok) return;
    await Db.deleteDish(d.id);
    await _reload();
  }

  Widget _phone() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // sections: ONE line, slide sideways
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < sections.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: phoneChip(sections[i].name, i == idx, () async {
                        idx = i;
                        group = '';
                        await _reload();
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // add dish + search + more, all in one line
            Row(children: [
              orangeButton('Add Dish', _addDish),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: search,
                    decoration: const InputDecoration(
                        hintText: 'Search...',
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 20)),
                    onChanged: (_) => _reload(),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                tooltip: 'More',
                icon: const Icon(Icons.more_vert),
                onSelected: (v) async {
                  if (v == 'new') await _addSection();
                  if (v == 'rename') await _renameSection();
                  if (v == 'delete') await _deleteSection();
                  if (v == 'import') await MenuSheet.import(context, _init);
                  if (v == 'export') await MenuSheet.export(context);
                  if (v == 'sample') await MenuSheet.sample(context);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'new', child: Text('New section')),
                  PopupMenuItem(value: 'rename', child: Text('Rename section')),
                  PopupMenuItem(value: 'delete', child: Text('Delete section')),
                  PopupMenuItem(value: 'import', child: Text('Import from Excel')),
                  PopupMenuItem(value: 'export', child: Text('Export menu to Excel')),
                  PopupMenuItem(value: 'sample', child: Text('Download sample sheet')),
                ],
              ),
            ]),
            if (groups.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: const Text('All'),
                        visualDensity: VisualDensity.compact,
                        selected: group.isEmpty,
                        onSelected: (_) async {
                          group = '';
                          await _reload();
                        },
                      ),
                    ),
                    for (final g in groups)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(g),
                          visualDensity: VisualDensity.compact,
                          selected: group == g,
                          onSelected: (_) async {
                            group = g;
                            await _reload();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: Box(
                padding: EdgeInsets.zero,
                child: dishes.isEmpty
                    ? const Center(child: Text('No dishes', style: TextStyle(color: kMuted)))
                    : ListView.separated(
                        itemCount: dishes.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: kWarmLine),
                        itemBuilder: (_, i) {
                          final d = dishes[i];
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
                            child: Row(children: [
                              DishPic(d, size: 76),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800, fontSize: 14.5)),
                                    if (d.group.isNotEmpty)
                                      Text(d.group,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: kMuted, fontSize: 12)),
                                    const SizedBox(height: 2),
                                    Text('\u20B9 ${money0(d.price)}',
                                        style: const TextStyle(
                                            color: Color(0xFFD9530A),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14.5)),
                                  ],
                                ),
                              ),
                              Tooltip(
                                message: d.closedToday ? 'Closed today' : 'Available',
                                child: Transform.scale(
                                  scale: 0.6,
                                  child: Switch(
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    value: !d.closedToday,
                                    activeColor: Colors.white,
                                    activeTrackColor: kGreen,
                                    onChanged: (v) async {
                                      await Db.setClosedToday(d.id, !v);
                                      await _reload();
                                    },
                                  ),
                                ),
                              ),
                              IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Edit',
                                  onPressed: () => _editDish(d),
                                  icon: const Icon(Icons.edit_outlined, size: 18)),
                              IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Delete',
                                  onPressed: () => _deleteDish(d),
                                  icon: const Icon(Icons.delete_outline, color: kRed, size: 18)),
                            ]),
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
    final small = isNarrow(context);
    if (small) return _phone();
    return Padding(
      padding: EdgeInsets.all(small ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (small) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < sections.length; i++)
                  ChoiceChip(
                    label: Text(sections[i].name),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    selected: i == idx,
                    selectedColor: kInk,
                    labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: i == idx ? Colors.white : kInk),
                    onSelected: (_) async {
                      idx = i;
                      group = '';
                      await _reload();
                    },
                  ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'New section',
                    onPressed: _addSection,
                    icon: const Icon(Icons.add_box_outlined)),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Rename section',
                    onPressed: _renameSection,
                    icon: const Icon(Icons.drive_file_rename_outline)),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Delete section',
                    onPressed: _deleteSection,
                    icon: const Icon(Icons.delete_outline, color: kRed)),
              ],
            ),
          ] else
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < sections.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(sections[i].name),
                            selected: i == idx,
                            selectedColor: kInk,
                            labelStyle:
                                TextStyle(color: i == idx ? Colors.white : kInk),
                            onSelected: (_) async {
                              idx = i;
                              group = '';
                              await _reload();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(tooltip: 'New section', onPressed: _addSection, icon: const Icon(Icons.add_box_outlined)),
              IconButton(tooltip: 'Rename section', onPressed: _renameSection, icon: const Icon(Icons.drive_file_rename_outline)),
              IconButton(tooltip: 'Delete section', onPressed: _deleteSection, icon: const Icon(Icons.delete_outline, color: kRed)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: small ? MediaQuery.of(context).size.width - 32 : 280,
                child: TextField(
                  controller: search,
                  decoration: const InputDecoration(
                      hintText: 'Search in this section', prefixIcon: Icon(Icons.search)),
                  onChanged: (_) => _reload(),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kOrange),
                onPressed: _addDish,
                icon: const Icon(Icons.add),
                label: const Text('Add dish'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (small)
            DropdownButtonFormField<String>(
              value: groups.contains(group) ? group : '',
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Show All')),
                for (final g in groups) DropdownMenuItem(value: g, child: Text(g)),
              ],
              onChanged: (v) async {
                group = v ?? '';
                await _reload();
              },
            )
          else
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Show All'),
                    selected: group.isEmpty,
                    onSelected: (_) async {
                      group = '';
                      await _reload();
                    },
                  ),
                ),
                for (final g in groups)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(g),
                      selected: group == g,
                      onSelected: (_) async {
                        group = g;
                        await _reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: dishes.isEmpty
                ? const Center(child: Text('No dishes', style: TextStyle(color: kMuted)))
                : ListView.separated(
                    itemCount: dishes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final d = dishes[i];
                      final info = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(d.group,
                              style: const TextStyle(color: kMuted, fontSize: 12)),
                        ],
                      );
                      final controls = <Widget>[
                        SizedBox(
                          width: 80,
                          child: Text('Rs. ${money0(d.price)}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: kRed, fontWeight: FontWeight.w800)),
                        ),
                      ];
                      final tail = <Widget>[
                        const Text('Closed today', style: TextStyle(fontSize: 12)),
                        Transform.scale(
                          scale: 0.7,
                          child: Switch(
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          value: d.closedToday,
                          onChanged: (v) async {
                            await Db.setClosedToday(d.id, v);
                            await _reload();
                          },
                        )),
                        IconButton(
                            tooltip: 'Edit',
                            onPressed: () => _editDish(d),
                            icon: const Icon(Icons.edit_outlined)),
                        IconButton(
                            tooltip: 'Delete',
                            onPressed: () => _deleteDish(d),
                            icon: const Icon(Icons.delete_outline, color: kRed)),
                      ];
                      if (small) {
                        // Phone: name on one line, buttons on the next.
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                DishPic(d, size: 64),
                                const SizedBox(width: 10),
                                Expanded(child: info),
                              ]),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [...controls, const SizedBox(width: 8), ...tail],
                              ),
                            ],
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            DishPic(d, size: 64),
                            const SizedBox(width: 10),
                            Expanded(child: info),
                            ...controls,
                            const SizedBox(width: 8),
                            ...tail,
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
