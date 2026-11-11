import 'package:flutter/material.dart';

import '../db.dart';
import '../db2.dart';
import '../dialogs.dart';
import '../models.dart';
import '../nav.dart';
import '../print.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});
  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  List<Section> sections = [];
  List<String> groups = [];
  List<Dish> dishes = [];
  int secIndex = 0;
  String group = ''; // '' = Show All
  bool editMode = false;
  bool _showOrder = false; // phone/small tablet: Menu and Order are two tabs
  int nextNo = 1;
  final search = TextEditingController();
  final searchFocus = FocusNode();

  bool get searching => search.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    sections = await Db.sections();
    if (secIndex >= sections.length) secIndex = 0;
    await _loadGroups();
    await _loadDishes();
    await _loadNo();
  }

  Future<void> _loadNo() async {
    final n = await Db.nextBillNo();
    if (mounted) setState(() => nextNo = n);
  }

  Future<void> _loadGroups() async {
    if (sections.isEmpty) {
      groups = [];
      return;
    }
    groups = await Db.groups(sections[secIndex].id);
    if (!groups.contains(group)) group = '';
  }

  Future<void> _loadDishes() async {
    List<Dish> list;
    if (searching) {
      list = await Db.dishes(search: search.text.trim());
    } else if (sections.isEmpty) {
      list = [];
    } else {
      list = await Db.dishes(sectionId: sections[secIndex].id);
      if (group.isNotEmpty) list = list.where((d) => d.group == group).toList();
    }
    if (mounted) setState(() => dishes = list);
  }

  void _addDish(Dish d) {
    if (d.closedToday && !editMode) {
      snack(context, '${d.name} is closed today');
      return;
    }
    cart.add(d);
  }

  // ---------------------------------------------------------------- totals
  double get _disc => cart.discount > cart.subtotal ? cart.subtotal : cart.discount;
  double get _gstAmt => r2((cart.subtotal - _disc) * Db.d('gst_pct') / 100);
  double get _total => r2(cart.subtotal - _disc + _gstAmt);

  // ---------------------------------------------------------------- actions
  Future<void> _kot() async {
    if (cart.isEmpty) {
      snack(context, 'Add some items first');
      return;
    }
    final head = cart.label.isEmpty ? cart.orderType : '${cart.orderType} - ${cart.label}';
    // save first, so the slip carries the same KOT number as the Kitchen screen
    cart.draftId = await Db.saveDraft(
      label: cart.label,
      orderType: cart.orderType,
      discount: cart.discount,
      lines: cart.list,
      draftId: cart.draftId,
      customerId: cart.customerId,
      kstatus: 'new',
    );
    String? err;
    for (final slip in Receipts.kitchenSlips(cart.list, head, kotNo: cart.draftId)) {
      err = await Receipts.printLines(slip);
      if (err != null) break;
    }
    if (!mounted) return;
    snack(context, err ?? 'Order sent to the kitchen');
  }

  Future<void> _draft() async {
    if (cart.isEmpty) {
      snack(context, 'Add some items first');
      return;
    }
    await Db.saveDraft(
      label: cart.label,
      orderType: cart.orderType,
      discount: cart.discount,
      lines: cart.list,
      draftId: cart.draftId,
      customerId: cart.customerId,
    );
    cart.clear();
    if (!mounted) return;
    setState(() => _showOrder = false); // back to the Menu to pick more items
    snack(context, 'Saved as draft. Open it from "Draft List".');
  }

  /// Online payment. The UPI ID is not connected yet, so a clear message is
  /// shown. Later: show the UPI ID / QR here and confirm automatically.
  Future<bool> _onlineDialog(double total) async {
    final upi = Db.s('upi_id').trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Online payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text('Rs. ${money(total)}',
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 14),
            if (upi.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFF1E0), borderRadius: BorderRadius.circular(10)),
                child: const Text(
                    'UPI ID is not added yet. It will be connected later, then the QR will show here.'),
              )
            else
              Text('Pay to UPI ID: $upi'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Payment received')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _showBill(BillData b) async {
    Widget row(String a, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null)),
            const Spacer(),
            Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null)),
          ]),
        );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        title: Text('${b.billNoText}  ${b.headline}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fmtDateTime(b.createdAt), style: const TextStyle(color: kMuted)),
                const SizedBox(height: 8),
                for (final i in b.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(child: Text('${i.qty} x ${i.name}')),
                      Text(money(i.amount)),
                    ]),
                  ),
                const Divider(),
                row('Sub total', money(b.subtotal)),
                if (b.discount > 0) row('Discount', '- ${money(b.discount)}'),
                row('GST ${pctText(b.gstPct)}%', money(b.gstAmt)),
                row('Total', money(b.total), bold: true),
                row('Paid by', b.payMode == 'UPI' ? 'Online (UPI)' : b.payMode),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton.icon(
            onPressed: () async {
              final err = await Receipts.printBillAndKot(b);
              if (ctx.mounted) snack(ctx, err ?? 'Sent to printer');
            },
            icon: const Icon(Icons.print),
            label: const Text('Print'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  /// Asks how much the customer pays in cash; the rest is paid online.
  Future<double?> _splitDialog(double total) {
    final recv = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final cash = double.tryParse(recv.text.trim()) ?? 0;
          final valid = cash > 0 && cash < total;
          return AlertDialog(
            scrollable: true,
            title: const Text('Cash + Online'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text('Total Rs. ${money(total)}',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: recv,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Paid in cash (Rs.)'),
                  onChanged: (_) => setS(() {}),
                ),
                const SizedBox(height: 10),
                if (cash > 0 && cash < total)
                  Text('Paid online: Rs. ${money(r2(total - cash))}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: kGreen))
                else if (cash >= total)
                  const Text('Cash must be less than the total. Use Bill & Cash instead.',
                      style: TextStyle(color: kRed)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                  onPressed: valid ? () => Navigator.pop(ctx, cash) : null,
                  child: const Text('Next')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _splitCheckout() async {
    if (cart.isEmpty) {
      snack(context, 'Add some items first');
      return;
    }
    final cash = await _splitDialog(_total);
    if (cash == null) return;
    if (!await _onlineDialog(r2(_total - cash))) return;
    await _checkout('Split', cash: cash);
  }

  /// [mode] is 'Cash' (paid by hand, no amount to type) or 'UPI' (online).
  Future<void> _checkout(String mode, {double? cash}) async {
    if (cart.isEmpty) {
      snack(context, 'Add some items first');
      return;
    }
    if (mode == 'UPI' && !await _onlineDialog(_total)) return;
    var label = cart.label;
    if (Db.s('order_mode') == 'token' && label.isEmpty) {
      label = 'Token: ${await Db.nextToken()}';
    }
    final id = await Db.saveBill(
      label: label,
      orderType: cart.orderType,
      payMode: mode,
      discount: cart.discount,
      lines: cart.list,
      gstPct: Db.d('gst_pct'),
      draftId: cart.draftId,
      customerId: cart.customerId,
      cashAmt: cash,
    );
    final b = await Db.getBill(id);
    cart.clear();
    await _loadNo();
    if (!mounted) return;
    setState(() => _showOrder = false);
    await _showBill(b); // the bill opens by itself, ready to print
  }

  Future<void> _draftList() async {
    final list = await Db.drafts();
    if (!mounted) return;
    var opened = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          title: const Text('Draft List'),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: list.isEmpty
                ? const Center(child: Text('No drafts'))
                : ListView(
                    children: [
                      for (final r in List<BillRow>.of(list))
                        ListTile(
                          title: Text(r.label.isEmpty ? r.orderType : '${r.orderType} - ${r.label}'),
                          subtitle: Text(fmtDateTime(r.createdAt)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Rs. ${money0(r.total)}'),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: kRed),
                                onPressed: () async {
                                  await Db.deleteDraft(r.id);
                                  setS(() => list.removeWhere((x) => x.id == r.id));
                                },
                              ),
                            ],
                          ),
                          onTap: () async {
                            await Db.openDraft(r.id);
                            opened = true;
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
    if (opened && mounted) await _draftChoice();
  }

  Future<void> _draftChoice() async {
    final go = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Draft opened'),
        content: Text('${cart.count} items are in the order. What next?'),
        actions: [
          OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'add'),
              icon: const Icon(Icons.add),
              label: const Text('Add items')),
          FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, 'bill'),
              icon: const Icon(Icons.receipt_long),
              label: const Text('Bill')),
        ],
      ),
    );
    if (go == null || !mounted) return;
    setState(() => _showOrder = go == 'bill');
  }

  Future<void> _editNote(CartLine l) async {
    final t = await askText(context, 'Note for ${l.dish.name}',
        initial: l.note, label: 'Example: less spicy');
    if (t != null) cart.setNote(l.dish.id, t);
  }

  Future<void> _editDiscount() async {
    final v = await askNumber(context, 'Extra discount', initial: cart.discount);
    if (v != null) cart.setDiscount(v);
  }

  Future<void> _changePrice(Dish d, double delta) async {
    final step = Db.d('price_step') > 0 ? Db.d('price_step') : 5;
    await Db.setPrice(d.id, d.price + delta * step);
    await _loadDishes();
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final small = MediaQuery.of(context).size.width < 800;
    return Padding(
      padding: small
          ? const EdgeInsets.fromLTRB(16, 4, 16, 10)
          : const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (small)
            ListenableBuilder(
              listenable: cart,
              builder: (context, _) => Row(
                children: [
                  _hdrBtn(Icons.table_restaurant_outlined, 'Table', false,
                      () => navIndex.value = 2),
                ],
              ),
            )
          else
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Point of Sale (POS)',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  SizedBox(height: 2),
                  Text('Dashboard  •  Pos', style: TextStyle(color: kMuted, fontSize: 12)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                    onPressed: () => navIndex.value = 2,
                    icon: const Icon(Icons.table_restaurant_outlined, size: 18),
                    label: const Text('Table Order'),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: small ? 8 : 12),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              if (c.maxWidth >= 760) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _panelBox(_menuSide())),
                    const SizedBox(width: 16),
                    SizedBox(width: 400, child: _panelBox(_orderPanel())),
                  ],
                );
              }
              // Phone / small tablet: two tabs, Menu and Order.
              return Column(
                children: [
                  Expanded(child: _showOrder ? _panelBox(_orderPanel()) : _menuSide()),
                  if (!_showOrder)
                    ListenableBuilder(
                      listenable: cart,
                      builder: (context, _) => cart.isEmpty
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Material(
                                color: kOrange,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => setState(() => _showOrder = true),
                                  child: Container(
                                    height: 52,
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.shopping_cart_outlined,
                                            color: Colors.white, size: 24),
                                        const SizedBox(width: 10),
                                        Text(
                                            '${cart.count} Items   |   \u20B9 ${money0(cart.subtotal)}',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15)),
                                        const Spacer(),
                                        const Text('View Cart',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15)),
                                        const SizedBox(width: 6),
                                        const Icon(Icons.arrow_forward,
                                            color: Colors.white, size: 20),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  static final ButtonStyle _softBtn = OutlinedButton.styleFrom(
    minimumSize: const Size(0, 42),
    backgroundColor: Colors.white,
    foregroundColor: kInk,
    side: const BorderSide(color: kTan),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  Widget _hdrBtn(IconData icon, String label, bool on, VoidCallback onTap,
      {int badge = 0}) {
    final fg = on ? Colors.white : kInk;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: on ? kOrange : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? kOrange : kTan),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12.5, color: fg)),
                if (badge > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: on ? Colors.white : kOrange,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('$badge',
                        style: TextStyle(
                            color: on ? kOrange : Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11)),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabBtn(String label, bool on, VoidCallback onTap, {int badge = 0}) {
    final kids = <Widget>[
      Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      if (badge > 0) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
              color: on ? Colors.white : kOrange, shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(12)),
          child: Text('$badge',
              style: TextStyle(
                  color: on ? kOrange : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12)),
        ),
      ],
    ];
    return SizedBox(
      height: 46,
      child: on
          ? FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: kOrange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: onTap,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: kids))
          : OutlinedButton(
              style: _softBtn,
              onPressed: onTap,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: kids)),
    );
  }

  Widget _panelBox(Widget child) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kLine),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(14), child: child),
      );

  Widget _sectionChips() => Row(
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  search.clear();
                  secIndex = i;
                  group = '';
                  await _loadGroups();
                  await _loadDishes();
                },
                child: Container(
                  height: 38,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: !searching && i == secIndex ? kOrange : Colors.white,
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(
                        color: !searching && i == secIndex ? kOrange : kTan),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(sections[i].name,
                        maxLines: 1,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: !searching && i == secIndex
                                ? Colors.white
                                : kInk)),
                  ),
                ),
              ),
            ),
          ],
        ],
      );

  Widget _groupDrop() => DropdownButtonFormField<String>(
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
          await _loadDishes();
        },
      );

  Widget _menuSide() {
    final small = isNarrow(context);
    return Padding(
      padding: small
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (small) ...[
            _sectionChips(),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  focusNode: searchFocus,
                  decoration: InputDecoration(
                    hintText: small
                        ? 'Search dishes...'
                        : 'Search in products (all sections), press Enter to add',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searching
                        ? IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              search.clear();
                              _loadDishes();
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => _loadDishes(),
                  onSubmitted: (_) {
                    if (dishes.isNotEmpty) _addDish(dishes.first);
                    searchFocus.requestFocus();
                  },
                ),
              ),
              if (!small) const SizedBox(width: 12),
              if (!small)
              FilterChip(
                label: const Text('Edit prices'),
                avatar: const Icon(Icons.edit, size: 16),
                selected: editMode,
                onSelected: (v) => setState(() => editMode = v),
              ),
            ],
          ),
          SizedBox(height: small ? 8 : 12),
          if (!small)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < sections.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _pill(
                      sections[i].name,
                      !searching && i == secIndex,
                      () async {
                        search.clear();
                        secIndex = i;
                        group = '';
                        await _loadGroups();
                        await _loadDishes();
                      },
                      dark: true,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: small ? 8 : 10),
          if (!searching && small)
            _groupDrop()
          else if (!searching)
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _pill('Show All', group.isEmpty, () async {
                      group = '';
                      await _loadDishes();
                    }),
                  ),
                  for (final g in groups)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _pill(g, group == g, () async {
                        group = g;
                        await _loadDishes();
                      }),
                    ),
                ],
              ),
            ),
          SizedBox(height: small ? 8 : 12),
          Expanded(
            child: dishes.isEmpty
                ? const Center(child: Text('No dishes found', style: TextStyle(color: kMuted)))
                : ListenableBuilder(
                    listenable: cart,
                    builder: (context, _) => GridView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: small ? 200 : 190,
                        mainAxisExtent: small
                            ? (editMode ? 256 : 202)
                            : (editMode ? 262 : 216),
                        crossAxisSpacing: small ? 12 : 12,
                        mainAxisSpacing: small ? 12 : 12,
                      ),
                      itemCount: dishes.length,
                      itemBuilder: (_, i) => _dishCard(dishes[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, bool sel, VoidCallback onTap, {bool dark = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: dark ? 18 : 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? (dark ? kInk : kOrange) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? Colors.transparent : kLine),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: sel ? Colors.white : kInk)),
      ),
    );
  }

  Widget _dishCard(Dish d) {
    final q = cart.qtyOf(d.id);
    final closed = d.closedToday;
    final small = isNarrow(context);
    return Opacity(
      opacity: closed ? 0.45 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(small ? 16 : 14),
        onTap: () => _addDish(d),
        child: Container(
          padding: small
              ? const EdgeInsets.fromLTRB(10, 10, 10, 10)
              : const EdgeInsets.fromLTRB(10, 12, 10, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(small ? 16 : 14),
            border: Border.all(
                color: q > 0 ? kOrange : (small ? kWarmLine : kLine),
                width: q > 0 ? 1.6 : 1),
          ),
          child: Column(
            crossAxisAlignment: small ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              if (small)
                Center(child: DishPic(d, size: 108))
              else
                DishPic(d, size: 112),
              SizedBox(height: small ? 6 : 8),
              Expanded(
                child: Text(d.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: small ? TextAlign.left : TextAlign.center,
                    style: TextStyle(
                        fontSize: small ? 12 : 12,
                        fontWeight: small ? FontWeight.w700 : FontWeight.w600,
                        height: 1.2)),
              ),
              if (closed)
                const Text('Closed today',
                    style: TextStyle(color: kRed, fontSize: 11, fontWeight: FontWeight.w700)),
              Row(
                children: [
                  Text(small ? '\u20B9 ${money0(d.price)}' : 'Rs. ${money0(d.price)}',
                      style: TextStyle(
                          color: small ? const Color(0xFFD9530A) : kRed,
                          fontWeight: FontWeight.w800,
                          fontSize: small ? 15 : 14)),
                  const Spacer(),
                  if (q > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text('x$q',
                          style: const TextStyle(
                              color: kOrange, fontWeight: FontWeight.w800)),
                    ),
                  Container(
                    width: small ? 24 : 22,
                    height: small ? 24 : 22,
                    decoration: const BoxDecoration(color: kOrange, shape: BoxShape.circle),
                    child: Icon(Icons.add, color: Colors.white, size: small ? 16 : 15),
                  ),
                ],
              ),
              if (editMode) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _sq(Icons.remove, () => _changePrice(d, -1)),
                    const SizedBox(width: 10),
                    const Text('price', style: TextStyle(fontSize: 11, color: kMuted)),
                    const SizedBox(width: 10),
                    _sq(Icons.add, () => _changePrice(d, 1)),
                  ],
                ),
                SizedBox(
                  height: 28,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Closed today', style: TextStyle(fontSize: 11)),
                      Transform.scale(
                        scale: 0.7,
                        child: Switch(
                          value: closed,
                          onChanged: (v) async {
                            await Db.setClosedToday(d.id, v);
                            await _loadDishes();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sq(IconData ic, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
              border: Border.all(color: kLine), borderRadius: BorderRadius.circular(6)),
          child: Icon(ic, size: 15),
        ),
      );

  // ---------------------------------------------------------------- order panel
  Widget _orderPanel() {
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        final mode = Db.s('order_mode');
        final tables = Db2.tableList();
        final showTable = mode == 'table' && cart.orderType == 'Dine In';
        final tableVal = tables.any((t) => 'Table: ${t.name}' == cart.label) ? cart.label : null;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: cart.orderType,
                      isDense: true,
                      decoration: const InputDecoration(labelText: 'Select Dining'),
                      items: const [
                        DropdownMenuItem(value: 'Dine In', child: Text('Dine In')),
                        DropdownMenuItem(value: 'Parcel', child: Text('Parcel')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        cart.setOrderType(v);
                        if (v != 'Dine In' && mode == 'table') cart.setLabel('');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: showTable
                        ? DropdownButtonFormField<String>(
                            value: tableVal,
                            isDense: true,
                            decoration: const InputDecoration(labelText: 'Select Table'),
                            items: [
                              for (final t in tables)
                                DropdownMenuItem(
                                    value: 'Table: ${t.name}', child: Text('Table ${t.name}')),
                            ],
                            onChanged: (v) {
                              cart.setLabel(v ?? '');
                              setState(() {});
                            },
                          )
                        : InputDecorator(
                            decoration: InputDecoration(
                                labelText: mode == 'token' ? 'Token' : 'Table'),
                            child: Text(
                                mode == 'token' ? 'Auto at billing' : 'Not needed',
                                style: const TextStyle(color: kMuted)),
                          ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: isNarrow(context)
                  ? const EdgeInsets.fromLTRB(14, 6, 14, 4)
                  : const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  const Icon(Icons.shopping_bag_outlined, color: kOrange),
                  const SizedBox(width: 8),
                  Text('Order #$nextNo',
                      style: TextStyle(
                          fontSize: isNarrow(context) ? 15 : 18,
                          fontWeight: FontWeight.w800)),
                  if (MediaQuery.of(context).size.width < 800) ...[
                    const Spacer(),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: kOrange),
                      onPressed: () => setState(() => _showOrder = false),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Add items'),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: cart.isEmpty
                  ? const Center(
                      child: Text('Tap a dish to add it', style: TextStyle(color: kMuted)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      itemCount: cart.list.length,
                      itemBuilder: (_, i) => _line(cart.list[i]),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: isNarrow(context)
                  ? const EdgeInsets.fromLTRB(14, 4, 14, 2)
                  : const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Column(
                children: [
                  _tot('Sub total :', 'Rs. ${money(cart.subtotal)}'),
                  InkWell(
                    onTap: _editDiscount,
                    child: _tot('Extra Discount :', '✎  Rs. ${money(_disc)}'),
                  ),
                  _tot('GST (${pctText(Db.d('gst_pct'))}%) :', 'Rs. ${money(_gstAmt)}'),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text('Total :',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Text('Rs. ${money(_total)}',
                          style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w800, color: kRed)),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: isNarrow(context)
                  ? const EdgeInsets.fromLTRB(10, 2, 10, 8)
                  : const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                              minimumSize: Size(0, isNarrow(context) ? 40 : 46),
                              padding: const EdgeInsets.symmetric(horizontal: 6)),
                          onPressed: _draft,
                          child: const Text('Draft'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: kOrange, minimumSize: Size(0, isNarrow(context) ? 40 : 46)),
                          onPressed: () => _checkout('UPI'),
                          child: const Text('Bill & Online'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: kGreen, minimumSize: Size(0, isNarrow(context) ? 40 : 46)),
                          onPressed: () => _checkout('Cash'),
                          child: const Text('Bill & Cash'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          minimumSize: Size(0, isNarrow(context) ? 40 : 46)),
                      onPressed: _splitCheckout,
                      child: const Text('Cash + Online (part payment)'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _tot(String a, String b) => Padding(
        padding: EdgeInsets.symmetric(vertical: isNarrow(context) ? 1 : 3),
        child: Row(
          children: [
            Text(a, style: const TextStyle(color: kInk, fontSize: 14)),
            const Spacer(),
            Text(b, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ],
        ),
      );

  Widget _stepBtn(IconData ic, VoidCallback onTap, {bool fill = false}) => InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
              color: fill ? kOrange : const Color(0xFFF1E8DE), shape: BoxShape.circle),
          child: Icon(ic, size: 18, color: fill ? Colors.white : kInk),
        ),
      );

  Widget _line(CartLine l) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0E6DA)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _editNote(l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.dish.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.2)),
                  const SizedBox(height: 2),
                  Text(
                      l.note.isEmpty
                          ? '\u20B9${money0(l.dish.price)} each  \u00B7  \u270E note'
                          : '\u20B9${money0(l.dish.price)} each  \u00B7  \u270E ${l.note}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: l.note.isEmpty ? kMuted : kOrange)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          _stepBtn(Icons.remove, () => cart.dec(l.dish.id)),
          SizedBox(
            width: 28,
            child: Text('${l.qty}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          _stepBtn(Icons.add, () => cart.add(l.dish), fill: true),
          SizedBox(
            width: 64,
            child: Text('\u20B9${money0(l.amount)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => cart.remove(l.dish.id),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, size: 18, color: kRed),
            ),
          ),
        ],
      ),
    );
  }
}
