import 'package:flutter/material.dart';

import '../db2.dart';
import '../dialogs.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

const List<String> kExpenseCats = [
  'Salary', 'Food & Groceries', 'Utilities', 'Staff', 'Maintenance', 'Rent', 'Other'
];

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, Object?>> rows = [];
  double total = 0;

  String get _from => dayStr(month);
  String get _to => dayStr(DateTime(month.year, month.month + 1, 0));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db2.expenses(_from, _to);
    final t = await Db2.expenseTotal(_from, _to);
    if (mounted) {
      setState(() {
        rows = r;
        total = t;
      });
    }
  }

  void _shift(int d) {
    setState(() => month = DateTime(month.year, month.month + d));
    _load();
  }

  Future<void> _add() async {
    final v = await askFields(context, 'Add expense', [
      FieldSpec('date', 'Date (yyyy-mm-dd)', initial: todayStr()),
      const FieldSpec('cat', 'Category', options: kExpenseCats, initial: 'Food & Groceries'),
      const FieldSpec('desc', 'Description'),
      const FieldSpec('amt', 'Amount (Rs.)', number: true),
    ]);
    if (v == null) return;
    final amt = double.tryParse(v['amt']!) ?? 0;
    DateTime? d;
    try {
      d = DateTime.parse(v['date']!);
    } catch (_) {}
    if (amt <= 0 || d == null) {
      if (mounted) snack(context, 'Please enter a correct date and amount');
      return;
    }
    await Db2.addExpense(dayStr(d), v['cat']!.isEmpty ? 'Other' : v['cat']!, v['desc']!, amt);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final small = isNarrow(context);
    return Padding(
      padding: small
          ? const EdgeInsets.fromLTRB(16, 0, 16, 10)
          : const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (small)
            phoneMonthBar('${months[month.month - 1]} ${month.year}', () => _shift(-1),
                () => _shift(1), orangeButton('Add Expense', _add))
          else
          PageHead('Expenses', actions: [
            IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
            Text('${months[month.month - 1]} ${month.year}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
            orangeButton('Add Expense', _add),
          ]),
          if (small)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE9E5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                const Text('Total this month', style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('\u20B9 ${money0(total)}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: kRed)),
              ]),
            )
          else
          Text('Total this month: Rs. ${money(total)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kRed)),
          const SizedBox(height: 12),
          Expanded(
            child: Box(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (!small)
                    const TableHead(['Date', 'Category', 'Description', 'Amount', ''],
                        [2, 3, 4, 2, 1]),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(
                            child: Text('No expenses', style: TextStyle(color: kMuted)))
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (_, i) {
                              final r = rows[i];
                              if (small) {
                                return phoneRow(
                                  icon: Icons.payments_outlined,
                                  title: r['category'] as String,
                                  sub: '${fmtDay(r['date'] as String)}  \u2022  ${r['description']}',
                                  subLines: 2,
                                  last: i == rows.length - 1,
                                  trailing: [
                                    Text('\u20B9 ${money0((r['amount'] as num).toDouble())}',
                                        style: const TextStyle(fontWeight: FontWeight.w800)),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.delete_outline, color: kRed, size: 20),
                                      onPressed: () async {
                                        final ok = await confirmBox(context, 'Delete', 'Delete this expense?');
                                        if (!ok) return;
                                        await Db2.deleteExpense(r['id'] as int);
                                        await _load();
                                      },
                                    ),
                                  ],
                                );
                              }
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: kLine))),
                                child: Row(children: [
                                  Expanded(flex: 2, child: Text(fmtDay(r['date'] as String))),
                                  Expanded(flex: 3, child: Text(r['category'] as String)),
                                  Expanded(flex: 4, child: Text(r['description'] as String)),
                                  Expanded(
                                      flex: 2,
                                      child: Text('Rs. ${money0((r['amount'] as num).toDouble())}',
                                          style: const TextStyle(fontWeight: FontWeight.w700))),
                                  Expanded(
                                    flex: 1,
                                    child: IconButton(
                                      icon: const Icon(Icons.delete_outline, color: kRed),
                                      onPressed: () async {
                                        final ok = await confirmBox(
                                            context, 'Delete', 'Delete this expense?');
                                        if (!ok) return;
                                        await Db2.deleteExpense(r['id'] as int);
                                        await _load();
                                      },
                                    ),
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
