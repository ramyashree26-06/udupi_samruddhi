import 'dart:async';

import 'package:flutter/material.dart';

import 'db.dart';
import 'db2.dart';
import 'login.dart';
import 'nav.dart';
import 'screens/backup.dart';
import 'screens/billing.dart';
import 'screens/dashboard.dart';
import 'screens/expenses.dart';
import 'screens/gst.dart';
import 'screens/inventory.dart';
import 'screens/kitchen.dart';
import 'screens/menu.dart';
import 'screens/orders.dart';
import 'screens/permissions.dart';
import 'screens/purchases.dart';
import 'screens/sales.dart';
import 'screens/settings.dart';
import 'screens/staff.dart';
import 'screens/suppliers.dart';
import 'screens/tables.dart';
import 'theme.dart';
import 'util.dart';
import 'widgets.dart';
import 'watermark.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.init();
  try {
    await Db2.migrateRoles();
    await Db2.resetPinsIfAsked();
    await Db.backup(); // one automatic backup per day
  } catch (_) {}
  final on = await Db2.pinLoginOn();
  pinOn.value = on;
  locked.value = on; // ask for a PIN at start only when PINs exist
  runApp(const BillingApp());
}

class BillingApp extends StatelessWidget {
  const BillingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Udupi Samruddhi Billing',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) => Theme(
        data: buildTheme(phone: MediaQuery.of(context).size.width < 1000),
        child: child!,
      ),
      home: const LoginGate(child: Shell()),
    );
  }
}

const Color kSide = Color(0xFF1E1F24);
const Color kSideText = Color(0xFFD9DAE0);

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  Timer? timer;
  String lastBackupDay = '';
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  bool narrow = false; // phone or small tablet: menu opens from a button

  @override
  void initState() {
    super.initState();
    // Daily backup at the time set in Settings (while the app is open).
    timer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (Db.s('auto_backup') != '1') return;
      final now = DateTime.now();
      final hm =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      if (hm == Db.s('backup_time') && lastBackupDay != todayStr()) {
        lastBackupDay = todayStr();
        try {
          await Db.backup(force: true);
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Widget _page(String key) {
    switch (key) {
      case 'dashboard':
        return const DashboardScreen();
      case 'tables':
        return const TablesScreen();
      case 'orders':
        return const OrdersScreen();
      case 'kitchen':
        return const KitchenScreen();
      case 'menu':
        return const MenuScreen();
      case 'inventory':
        return const InventoryScreen();
      case 'purchase':
        return const PurchasesScreen();
      case 'suppliers':
        return const SuppliersScreen();
      case 'expenses':
        return const ExpensesScreen();
      case 'staff':
        return const StaffScreen();
      case 'sales':
        return const SalesScreen();
      case 'gst':
        return const GstScreen();
      case 'settings':
        return const SettingsScreen();
      case 'permissions':
        return const PermissionsScreen();
      case 'backup':
        return const BackupScreen();
      default:
        return const BillingScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pages are rebuilt when you switch, so they always show fresh data.
    // The order you are making is kept safe in `cart`.
    return ValueListenableBuilder<Set<String>>(
      valueListenable: allowed,
      builder: (context, allOk, _) => ValueListenableBuilder<int>(
        valueListenable: navIndex,
        builder: (context, index, _) {
          final ok = allOk.difference(hiddenModules);
          var key = keyAt(index);
          if (!ok.contains(key)) {
            key = Db2.allModules.firstWhere(ok.contains, orElse: () => 'pos');
          }
          narrow = MediaQuery.of(context).size.width < 1000;
          final body = Column(
            children: [
              _topBar(key),
              if (narrow) _titleStrip(key),
              Expanded(
                child: Watermark(
                  child: Container(
                      color: narrow ? kCream : Colors.white, child: _page(key)),
                ),
              ),
            ],
          );
          return Scaffold(
            key: scaffoldKey,
            backgroundColor: narrow ? kCream : Colors.white,
            drawer: narrow
                ? Drawer(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    width: 280,
                    child: _sidebar(key, ok),
                  )
                : null,
            bottomNavigationBar: narrow ? _bottomNav(key, ok) : null,
            body: narrow
                ? SafeArea(bottom: false, child: body)
                : Row(
                    children: [
                      _sidebar(key, ok),
                      Expanded(child: body),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _sidebar(String current, Set<String> ok) {
    return Container(
      width: narrow ? null : 224,
      color: narrow ? null : kSide,
      decoration: narrow
          ? const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF5A2D12), Color(0xFF3A1B0A)],
              ),
              borderRadius: BorderRadius.only(
                  topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
            )
          : null,
      padding: narrow
          ? EdgeInsets.fromLTRB(
              12, MediaQuery.of(context).padding.top + 18, 12, 12)
          : const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (narrow)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(children: [
                Image.asset('assets/logo_icon.png', height: 64),
                const SizedBox(height: 6),
                Text(Db.s('hotel_name'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19)),
                const SizedBox(height: 2),
                const Text('- Hotel & Restaurant -',
                    style: TextStyle(color: kTan, fontSize: 12)),
              ]),
            )
          else
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Image.asset('assets/logo_icon.png'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(Db.s('hotel_name'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          height: 1.15)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final k in Db2.allModules)
                  if (ok.contains(k)) _item(k, k == current),
              ],
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: pinOn,
            builder: (context, on, _) => on
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: kSideText),
                      onPressed: () => locked.value = true,
                      icon: const Icon(Icons.lock_outline, size: 18),
                      label: const Text('Lock / Change user'),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _item(String k, bool sel) {
    final info = kModuleInfo[k]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: sel ? kOrange : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () {
            navIndex.value = Db2.allModules.indexOf(k);
            if (narrow) scaffoldKey.currentState?.closeDrawer();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(info.icon, size: 19, color: sel ? Colors.white : kSideText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(info.menu,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: sel ? Colors.white : kSideText,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _titleStrip(String key) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        child: Row(children: [
          Expanded(
            child: Text(kModuleInfo[key]!.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          if (key == 'dashboard') ...[
            Text('Today, ${fmtDay(todayStr())}',
                style: const TextStyle(fontSize: 12.5, color: kInk)),
            const SizedBox(width: 6),
            const Icon(Icons.calendar_today_outlined, size: 16),
          ],
        ]),
      );

  Widget _bottomNav(String current, Set<String> ok) {
    const items = [
      ['dashboard', 'Home', Icons.home_outlined],
      ['pos', 'Billing', Icons.description_outlined],
      ['tables', 'Tables', Icons.table_restaurant_outlined],
      ['orders', 'Orders', Icons.receipt_long_outlined],
      ['sales', 'Reports', Icons.bar_chart_rounded],
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: kWarmLine)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            children: [
              for (final it in items)
                if (ok.contains(it[0] as String))
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => navIndex.value = Db2.allModules.indexOf(it[0] as String),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: current == it[0] ? kOrange : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(it[2] as IconData,
                                size: 23,
                                color: current == it[0] ? Colors.white : kInk),
                            const SizedBox(height: 2),
                            Text(it[1] as String,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: current == it[0] ? Colors.white : kInk)),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(String key) {
    if (narrow) {
      return Container(
        color: kCream,
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 2),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.menu, size: 27),
            tooltip: 'Menu',
            onPressed: () => scaffoldKey.currentState?.openDrawer(),
          ),
          Image.asset('assets/logo_icon.png',
              height: 44, fit: BoxFit.contain, filterQuality: FilterQuality.high),
          const SizedBox(width: 10),
          Expanded(
            child: Text(Db.s('hotel_name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF5A2E0E))),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, size: 26),
            tooltip: 'Notifications',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No new notifications'))),
          ),
        ]),
      );
    }
    return Container(
      height: narrow ? 50 : 58,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: kLine)),
      ),
      child: Row(
        children: [
          if (narrow)
            IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Menu',
              onPressed: () => scaffoldKey.currentState?.openDrawer(),
            ),
          Expanded(
            child: Text(kModuleInfo[key]!.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: narrow ? 17 : 19, fontWeight: FontWeight.w800)),
          ),
          if (!narrow) ...[
            Text(fmtDay(todayStr()), style: const TextStyle(color: kMuted)),
            const SizedBox(width: 16),
          ],
          Image.asset('assets/logo_full.png', height: narrow ? 28 : 34),
        ],
      ),
    );
  }
}
