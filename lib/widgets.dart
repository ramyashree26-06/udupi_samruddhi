import 'dart:io';

import 'package:flutter/material.dart';

import 'models.dart';
import 'photos.dart';
import 'theme.dart';
import 'util.dart';

/// Round dish picture: the real photo if we have one, else an emoji.
class DishPic extends StatelessWidget {
  final Dish dish;
  final double size;
  const DishPic(this.dish, {super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    if (dish.photo.isNotEmpty && File(dish.photo).existsSync()) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kLine)),
        child: ClipOval(
          child: Image.file(File(dish.photo), width: size, height: size, fit: BoxFit.cover),
        ),
      );
    }
    final p = photoFor(dish.name);
    final emoji = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: kSoft, shape: BoxShape.circle),
      child: Text(emojiFor(dish.group, dish.sectionName),
          style: TextStyle(fontSize: size * 0.5)),
    );
    if (p == null) return emoji;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: kLine),
      ),
      child: ClipOval(
        child: Image.asset(
          p,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => emoji,
        ),
      ),
    );
  }
}

/// Round picture from a dish name only (used where we have no Dish object).
class NamePic extends StatelessWidget {
  final String name;
  final double size;
  const NamePic(this.name, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final p = photoFor(name);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: kSoft, shape: BoxShape.circle),
      child: Text('\u{1F37D}', style: TextStyle(fontSize: size * 0.5)),
    );
    if (p == null) return fallback;
    return ClipOval(
      child: Image.asset(p,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback),
    );
  }
}

/// A white box with a thin border, used on most pages.
class Box extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Box({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final phone = isNarrow(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(phone ? 16 : 14),
        border: Border.all(color: phone ? kWarmLine : kLine),
        boxShadow: phone
            ? const [BoxShadow(color: Color(0x0F8A5A2B), blurRadius: 8, offset: Offset(0, 2))]
            : null,
      ),
      child: child,
    );
  }
}

/// Small coloured pill like "Active", "Low Stock".
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      );
}

/// Title row at the top of a page: heading on the left, buttons on the right.
/// On a phone the top bar already shows the page name, so only the buttons
/// are shown (saves a whole line).
class PageHead extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  /// Kept for older calls; on a phone the buttons are always on one line.
  final bool inline;
  const PageHead(this.title,
      {super.key, this.actions = const [], this.inline = false});

  @override
  Widget build(BuildContext context) {
    if (isNarrow(context)) {
      if (actions.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: actions,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          ),
          for (final a in actions)
            Padding(padding: const EdgeInsets.only(left: 8), child: a),
        ],
      ),
    );
  }
}

Widget orangeButton(String text, VoidCallback onTap, {IconData icon = Icons.add}) =>
    Builder(builder: (context) {
      final small = isNarrow(context);
      return FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: kOrange,
            shape: small
                ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                : null,
            minimumSize: Size(0, small ? 38 : 42),
            padding: EdgeInsets.symmetric(horizontal: small ? 12 : 16),
            visualDensity: small ? VisualDensity.compact : null),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(text),
      );
    });

/// A table-like header line (grey text) and rows made from Expanded cells.
class TableHead extends StatelessWidget {
  final List<String> cols;
  final List<int> flex;
  const TableHead(this.cols, this.flex, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
            color: kSoft, border: Border(bottom: BorderSide(color: kLine))),
        child: Row(
          children: [
            for (var i = 0; i < cols.length; i++)
              Expanded(
                flex: flex[i],
                child: Text(cols[i],
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: kMuted, fontSize: 12.5)),
              ),
          ],
        ),
      );
}

/// Phone look: a small round-cornered chip (selected = orange).
Widget phoneChip(String text, bool on, VoidCallback onTap, {IconData? icon}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on ? kOrange : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: on ? kOrange : kTan),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (on && icon != null) ...[
            Icon(icon, size: 15, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : kInk)),
        ]),
      ),
    );

/// Phone look: status pill like Paid / Cancelled.
Widget statusPill(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
    );

/// Phone look: one list row (orange icon square, title, small text, extras).
Widget phoneRow({
  required IconData icon,
  required String title,
  String sub = '',
  Color subColor = kMuted,
  int subLines = 1,
  List<Widget> trailing = const [],
  bool last = false,
  VoidCallback? onTap,
}) =>
    InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: last ? Colors.transparent : kWarmLine)),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: const Color(0xFFFFF0E2), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: kOrange, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                if (sub.isNotEmpty)
                  Text(sub,
                      maxLines: subLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: subColor, fontSize: 12.5)),
              ],
            ),
          ),
          ...trailing,
        ]),
      ),
    );

/// Phone look: month picker (arrows) with one button on the right.
Widget phoneMonthBar(String label, VoidCallback prev, VoidCallback next, Widget action) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kTan),
          ),
          child: Row(children: [
            IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: prev,
                icon: const Icon(Icons.chevron_left)),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: next,
                icon: const Icon(Icons.chevron_right)),
          ]),
        ),
        const Spacer(),
        action,
      ]),
    );
