import 'package:flutter/material.dart';

import 'models.dart';
import 'pics.dart';
import 'theme.dart';

Future<String?> askText(BuildContext context, String title,
    {String initial = '', String label = 'Name', int lines = 1}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: c,
          autofocus: true,
          maxLines: lines,
          decoration: InputDecoration(labelText: label),
          onSubmitted: lines == 1 ? (v) => Navigator.pop(ctx, v.trim()) : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Save')),
      ],
    ),
  );
}

Future<double?> askNumber(BuildContext context, String title,
    {double initial = 0, String label = 'Amount (Rs.)'}) {
  final c = TextEditingController(text: initial == 0 ? '' : _plain(initial));
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, double.tryParse(v.trim()) ?? 0),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.trim()) ?? 0),
            child: const Text('OK')),
      ],
    ),
  );
}

Future<bool> confirmBox(BuildContext context, String title, String message) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
      ],
    ),
  );
  return r ?? false;
}

class DishForm {
  final String name;
  final double price;
  final String group;
  final int sectionId;
  final String photo;
  DishForm(this.name, this.price, this.group, this.sectionId, [this.photo = '']);
}

/// Add or edit a dish: name, price, section and group (like "Dosa").
Future<DishForm?> askDishForm(
  BuildContext context, {
  required String title,
  required List<Section> sections,
  required int sectionId,
  required Future<List<String>> Function(int sectionId) groupsOf,
  String name = '',
  double? price,
  String group = '',
  String photo = '',
}) async {
  var pic = photo;
  final n = TextEditingController(text: name);
  final p = TextEditingController(text: price == null ? '' : _plain(price));
  final g = TextEditingController(text: group);
  var sec = sectionId;
  var groups = await groupsOf(sec);
  if (!context.mounted) return null;
  return showDialog<DishForm>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: n,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Dish name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: p,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Price (Rs.)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: sec,
                decoration: const InputDecoration(labelText: 'Section'),
                items: [
                  for (final s in sections)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  final gl = await groupsOf(v);
                  setS(() {
                    sec = v;
                    groups = gl;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: g,
                decoration: const InputDecoration(
                    labelText: 'Group (like Dosa, Starters). Pick one below or type a new one'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final x in groups)
                    ActionChip(label: Text(x), onPressed: () => setS(() => g.text = x)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (pic.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: fileImage(pic, width: 64, height: 64),
                    )
                  else
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                          color: kSoft, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.image_outlined, color: kMuted),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final r = await Pics.pick(ctx, 'dish');
                            if (r != null) setS(() => pic = r);
                          },
                          icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                          label: Text(pic.isEmpty ? 'Add photo' : 'Change photo'),
                        ),
                        if (pic.isNotEmpty)
                          TextButton(
                              onPressed: () => setS(() => pic = ''),
                              child: const Text('Remove')),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final nm = n.text.trim();
              final pr = double.tryParse(p.text.trim());
              if (nm.isEmpty || pr == null || pr < 0) return;
              Navigator.pop(ctx, DishForm(nm, pr, g.text.trim(), sec, pic));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

String _plain(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

void snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));
}

/// One input in [askFields]. Give [options] to make it a drop-down list.
class FieldSpec {
  final String key;
  final String label;
  final String initial;
  final bool number;
  final bool secret;
  final List<String>? options;
  const FieldSpec(this.key, this.label,
      {this.initial = '', this.number = false, this.secret = false, this.options});
}

/// A small form. Returns the typed values by key, or null if cancelled.
Future<Map<String, String>?> askFields(
    BuildContext context, String title, List<FieldSpec> fields) {
  final ctrls = {for (final f in fields) f.key: TextEditingController(text: f.initial)};
  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < fields.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: fields[i].options != null
                      ? StatefulBuilder(
                          builder: (ctx, setS) => DropdownButtonFormField<String>(
                            value: fields[i].options!.contains(ctrls[fields[i].key]!.text)
                                ? ctrls[fields[i].key]!.text
                                : null,
                            decoration: InputDecoration(labelText: fields[i].label),
                            items: [
                              for (final o in fields[i].options!)
                                DropdownMenuItem(value: o, child: Text(o)),
                            ],
                            onChanged: (v) =>
                                setS(() => ctrls[fields[i].key]!.text = v ?? ''),
                          ),
                        )
                      : TextField(
                          controller: ctrls[fields[i].key],
                          autofocus: i == 0,
                          obscureText: fields[i].secret,
                          keyboardType: fields[i].number
                              ? const TextInputType.numberWithOptions(decimal: true)
                              : TextInputType.text,
                          decoration: InputDecoration(labelText: fields[i].label),
                        ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, {
            for (final f in fields) f.key: ctrls[f.key]!.text.trim(),
          }),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
