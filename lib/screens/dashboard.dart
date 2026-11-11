import 'package:flutter/material.dart';

import '../charts.dart';
import '../db.dart';
import '../db2.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, double> t = {};
  Map<String, double> pay = {};
  List<Map<String, Object?>> top = [];
  Map<int, double> hours = {};
  Map<String, double> prof = {};
  int open = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = todayStr();
    final a = await Db.reportTotals(d, d);
    final b = await Db.payTotals(d, d);
    final rows = List<Map<String, Object?>>.of(await Db.reportRows(d, d, false));
    rows.sort((x, y) => (y['q'] as num).compareTo(x['q'] as num));
    final h = await Db2.salesByHour(d);
    final o = await Db2.openTables();
    final pf = await Db2.profit(d, d);
    if (!mounted) return;
    setState(() {
      t = a;
      pay = b;
      top = rows.take(30).toList();
      hours = h;
      open = o;
      prof = pf;
    });
  }

  Widget _card(String title, String value, Color bg, Color fg,
          {bool compact = false}) =>
      Expanded(
        child: Container(
          padding: EdgeInsets.all(compact ? 8 : 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: TextStyle(
                        fontSize: compact ? 17 : 24,
                        fontWeight: FontWeight.w800,
                        color: fg)),
              ),
              SizedBox(height: compact ? 2 : 4),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: kInk, fontSize: compact ? 11 : 14, height: 1.15)),
            ],
          ),
        ),
      );

  Widget _stat(IconData ic, String value, String label, Color bg, Color fg) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: fg.withOpacity(0.16), shape: BoxShape.circle),
            child: Icon(ic, color: fg, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                Text(label, style: const TextStyle(fontSize: 12.5, color: kMuted)),
              ],
            ),
          ),
        ]),
      );

  /// Small, short card: label on top, amount below.
  Widget _mini(String label, String value, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11.5, color: kMuted)),
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: fg)),
            ),
          ],
        ),
      );

  Widget _phone() {
    final labels = <String>[];
    final values = <double>[];
    for (var h = 6; h <= 23; h++) {
      values.add(hours[h] ?? 0);
      if ((h - 6) % 2 == 0) {
        labels.add(h < 12 ? '${h}AM' : (h == 12 ? '12PM' : '${h - 12}PM'));
      } else {
        labels.add('');
      }
    }
    return RefreshIndicator(
      color: kOrange,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // banner
            Container(
              height: 116,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                    colors: [Color(0xFF3A1B0A), Color(0xFF5A2D10)]),
              ),
              child: LayoutBuilder(builder: (context, c) {
                return Stack(children: [
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: c.maxWidth * 0.62,
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (r) => const LinearGradient(
                        colors: [Color(0x00000000), Color(0xFF000000)],
                        stops: [0.0, 0.45],
                      ).createShader(r),
                      child: Image.asset('assets/banner_dish.jpg',
                          fit: BoxFit.cover, alignment: Alignment.center),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    top: 0,
                    bottom: 0,
                    width: c.maxWidth * 0.5,
                    child: Row(children: [
                      Image.asset('assets/logo_icon.png', height: 48),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(Db.s('hotel_name'),
                                maxLines: 2,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    height: 1.1)),
                            const SizedBox(height: 4),
                            const Text('Hotel & Restaurant',
                                style: TextStyle(color: kTan, fontSize: 11)),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ]);
              }),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: _mini('Cash', '\u20B9 ${money0(pay['Cash'] ?? 0)}',
                      const Color(0xFFE2EFFB), const Color(0xFF1E6FD0))),
              const SizedBox(width: 8),
              Expanded(
                  child: _mini('Online', '\u20B9 ${money0((pay['UPI'] ?? 0) + (pay['Card'] ?? 0))}',
                      const Color(0xFFEDE7FB), const Color(0xFF6B45D6))),
              const SizedBox(width: 8),
              Expanded(
                  child: _mini('Total Sales', '\u20B9 ${money0(t['total'] ?? 0)}',
                      const Color(0xFFE2F4E7), kGreen)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: _mini('Orders', '${(t['bills'] ?? 0).toInt()}',
                      const Color(0xFFFFE8D5), kOrange)),
              const SizedBox(width: 8),
              Expanded(
                  child: _mini('Profit', '\u20B9 ${money0(prof['profit'] ?? 0)}',
                      const Color(0xFFE2F4E7), (prof['profit'] ?? 0) >= 0 ? kGreen : kRed)),
            ]),
            const SizedBox(height: 14),
            Box(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sales Trend (by Hour)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  LineChart(labels: labels, values: values, height: 170),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Box(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Top Dishes Today',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  if (top.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('No sales yet today', style: TextStyle(color: kMuted)),
                    ),
                  ConstrainedBox(
 constraints: const BoxConstraints(maxHeight: 280),
 child: SingleChildScrollView(
 child: Column(children: [
 for (final r in top)
 Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        NamePic(r['n'] as String, size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(r['n'] as String,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14.5)),
                        ),
                        Text('${(r['q'] as num).toInt()} orders',
                            style: const TextStyle(color: kInk, fontSize: 13)),
                        const Icon(Icons.chevron_right, size: 20, color: kMuted),
                      ]),
                    ),
 ]),
 ),
 ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labels = <String>[];
    final values = <double>[];
    for (var h = 6; h <= 23; h++) {
      labels.add(h <= 12 ? '$h${h == 12 ? 'p' : 'a'}' : '${h - 12}p');
      values.add(hours[h] ?? 0);
    }
    final small = isNarrow(context);
    if (small) return _phone();
    final boxW = MediaQuery.of(context).size.width - 24;
    final cards = <Widget>[
      _card(small ? 'Sales' : "Today's Sales", 'Rs. ${money0(t['total'] ?? 0)}',
          const Color(0xFFE6F6EA), kGreen, compact: small),
      _card('Orders', '${(t['bills'] ?? 0).toInt()}',
          const Color(0xFFEDE9FB), const Color(0xFF5B3FD0), compact: small),
      _card(small ? 'Cash' : 'Cash Collections', 'Rs. ${money0(pay['Cash'] ?? 0)}',
          const Color(0xFFFFF1E0), kOrange, compact: small),
      _card('Online', 'Rs. ${money0((pay['UPI'] ?? 0) + (pay['Card'] ?? 0))}',
          const Color(0xFFEDE7FB), const Color(0xFF6B45D6), compact: small),
      _card(small ? 'Profit' : "Today's Profit",
          'Rs. ${money0(prof['profit'] ?? 0)}', const Color(0xFFE2F4E7), kGreen, compact: small),
    ];
    return SingleChildScrollView(
      padding: EdgeInsets.all(small ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHead('Dashboard', inline: true, actions: [
            Text('Today, ${fmtDay(todayStr())}', style: const TextStyle(color: kMuted)),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ]),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cards[0],
                SizedBox(width: small ? 6 : 12),
                cards[1],
                SizedBox(width: small ? 6 : 12),
                cards[2],
                SizedBox(width: small ? 6 : 12),
                cards[3],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              SizedBox(
                width: small ? boxW : 640,
                child: Box(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sales Trend (by hour)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      BarChart(labels: labels, values: values, height: 230),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: small ? boxW : 380,
                child: Box(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Top Dishes',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      if (top.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('No sales yet today', style: TextStyle(color: kMuted)),
                        ),
                      ConstrainedBox(
 constraints: const BoxConstraints(maxHeight: 240),
 child: SingleChildScrollView(
 child: Column(children: [
 for (final r in top)
 Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              NamePic(r['n'] as String, size: 38),
                              const SizedBox(width: 10),
                              Expanded(child: Text(r['n'] as String)),
                              Text('${(r['q'] as num).toInt()}',
                                  style: const TextStyle(fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
 ]),
 ),
 ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
