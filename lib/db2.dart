import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db.dart';
import 'util.dart';

/// All the "extra" modules: expenses, suppliers, purchases, stock,
/// customers, staff, roles, table states and the kitchen screen.
class KItem {
  final String name;
  final int qty;
  final String note;
  KItem(this.name, this.qty, this.note);
}

class KOrder {
  final int id;
  final String label;
  final String orderType;
  final String kstatus; // new, preparing, ready
  final DateTime createdAt;
  final List<KItem> items;
  KOrder(this.id, this.label, this.orderType, this.kstatus, this.createdAt, this.items);
}

class Db2 {
  static Database get _d => Db.db;

  /// All pages, in the order shown in the left menu.
  static const List<String> allModules = [
    'dashboard', 'pos', 'tables', 'orders', 'kitchen', 'menu', 'inventory',
    'purchase', 'suppliers', 'expenses', 'staff', 'sales', 'gst',
    'settings', 'permissions', 'backup',
  ];

  /// Older data had a "Kitchen" role. It becomes "Waiter" (takes orders,
  /// sees tables and the kitchen screen). Staff keep their link.
  static Future<void> migrateRoles() async {
    final k = await _d.query('roles', where: 'name = ?', whereArgs: ['Kitchen']);
    if (k.isEmpty) return;
    final w = await _d.query('roles', where: 'name = ?', whereArgs: ['Waiter']);
    if (w.isEmpty) {
      await _d.update('roles', {'name': 'Waiter', 'perms': 'pos,tables,kitchen'},
          where: 'name = ?', whereArgs: ['Kitchen']);
    } else {
      await _d.delete('roles', where: 'name = ?', whereArgs: ['Kitchen']);
    }
    await _d.update('staff', {'role': 'Waiter'}, where: 'role = ?', whereArgs: ['Kitchen']);
  }

  /// Testing stage only: removes every order and bill (all dates) and the
  /// table states. A backup is saved first. Menu, staff and settings stay.
  static Future<void> clearAllOrders() async {
    await Db.backup(force: true);
    await _d.transaction((t) async {
      await t.delete('bill_items');
      await t.delete('bills');
      await t.delete('table_state');
    });
    try {
      await _d.rawDelete(
          "DELETE FROM sqlite_sequence WHERE name IN ('bills','bill_items')");
    } catch (_) {}
  }

  static Future<void> createTables(Database d) async {
    await d.execute(
        'CREATE TABLE IF NOT EXISTS expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, category TEXT NOT NULL, description TEXT NOT NULL DEFAULT \'\', amount REAL NOT NULL)');
    await d.execute(
        'CREATE TABLE IF NOT EXISTS suppliers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT NOT NULL DEFAULT \'\')');
    await d.execute(
        'CREATE TABLE IF NOT EXISTS purchases(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, supplier_id INTEGER, items TEXT NOT NULL DEFAULT \'\', amount REAL NOT NULL, status TEXT NOT NULL DEFAULT \'Received\')');
    await d.execute(
        'CREATE TABLE IF NOT EXISTS inventory(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, qty REAL NOT NULL DEFAULT 0, unit TEXT NOT NULL DEFAULT \'kg\', min_qty REAL NOT NULL DEFAULT 0)');
    await d.execute(
        'CREATE TABLE IF NOT EXISTS customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT NOT NULL DEFAULT \'\')');
    await d.execute(
        'CREATE TABLE IF NOT EXISTS roles(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, perms TEXT NOT NULL DEFAULT \'\')');
    await d.execute(
        'CREATE TABLE IF NOT EXISTS staff(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, role TEXT NOT NULL, phone TEXT NOT NULL DEFAULT \'\', active INTEGER NOT NULL DEFAULT 1, pin TEXT NOT NULL DEFAULT \'\')');
    await d.execute(
        'CREATE TABLE IF NOT EXISTS table_state(num INTEGER PRIMARY KEY, state TEXT NOT NULL, note TEXT NOT NULL DEFAULT \'\')');
    await _loginCols(d);
    final r = await d.rawQuery('SELECT COUNT(*) AS c FROM roles');
    if ((r.first['c'] as int) == 0) {
      await d.insert('roles', {'name': 'Admin', 'perms': 'all'});
      await d.insert('roles', {
        'name': 'Manager',
        'perms':
            'dashboard,pos,tables,orders,kitchen,menu,inventory,purchase,suppliers,expenses,staff,sales,gst'
      });
      await d.insert('roles',
          {'name': 'Cashier', 'perms': 'pos,tables,orders'});
      await d.insert('roles', {'name': 'Waiter', 'perms': 'pos,tables,kitchen'});
      await d.insert(
          'staff', {'name': 'Owner', 'role': 'Admin', 'phone': '', 'active': 1, 'pin': ''});
    }
  }

  // ------------------------------------------------------------ expenses
  static Future<List<Map<String, Object?>>> expenses(String from, String to) =>
      _d.query('expenses',
          where: 'date BETWEEN ? AND ?',
          whereArgs: [from, to],
          orderBy: 'date DESC, id DESC');

  static Future<void> addExpense(
      String date, String category, String desc, double amount) async {
    await _d.insert('expenses', {
      'date': date,
      'category': category,
      'description': desc,
      'amount': amount,
    });
  }

  static Future<void> deleteExpense(int id) async {
    await _d.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  static Future<double> expenseTotal(String from, String to) async {
    final r = await _d.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS t FROM expenses WHERE date BETWEEN ? AND ?',
        [from, to]);
    return (r.first['t'] as num).toDouble();
  }

  // ------------------------------------------------------------ suppliers
  static Future<List<Map<String, Object?>>> suppliers() => _d.rawQuery(
      'SELECT s.*, '
      "COALESCE((SELECT SUM(amount) FROM purchases WHERE supplier_id = s.id AND status = 'Pending'),0) AS pending, "
      'COALESCE((SELECT SUM(amount) FROM purchases WHERE supplier_id = s.id),0) AS total, '
      'COALESCE((SELECT COUNT(*) FROM purchases WHERE supplier_id = s.id),0) AS cnt, '
      "COALESCE((SELECT MAX(date) FROM purchases WHERE supplier_id = s.id),'') AS last_date "
      'FROM suppliers s ORDER BY s.name');

  static Future<List<Map<String, Object?>>> supplierPurchases(int id) => _d.query(
      'purchases',
      where: 'supplier_id = ?',
      whereArgs: [id],
      orderBy: 'date DESC, id DESC');

  static Future<void> saveSupplier(int? id, String name, String phone,
      {String supplies = '', String address = ''}) async {
    final m = {'name': name, 'phone': phone, 'supplies': supplies, 'address': address};
    if (id == null) {
      await _d.insert('suppliers', m);
    } else {
      await _d.update('suppliers', m, where: 'id = ?', whereArgs: [id]);
    }
  }

  static Future<void> deleteSupplier(int id) async {
    await _d.delete('suppliers', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------ purchases
  static Future<List<Map<String, Object?>>> purchases(String from, String to) =>
      _d.rawQuery(
          'SELECT pu.*, COALESCE(NULLIF(pu.shop, \'\'), s.name, \'-\') AS supplier FROM purchases pu '
          'LEFT JOIN suppliers s ON s.id = pu.supplier_id '
          'WHERE pu.date BETWEEN ? AND ? ORDER BY pu.date DESC, pu.id DESC',
          [from, to]);

  static Future<void> addPurchase(String date, int? supplierId, String items,
      double amount, String status) async {
    await _d.insert('purchases', {
      'date': date,
      'supplier_id': supplierId,
      'items': items,
      'amount': amount,
      'status': status,
    });
  }

  /// An outside purchase with item lines, how it was paid and a slip photo.
  static Future<void> addPurchaseFull({
    required String date,
    required String shop,
    required List<Map<String, Object?>> items,
    required double total,
    required String payMode,
    required String slip,
    required String note,
    int? supplierId,
  }) async {
    await _d.transaction((txn) async {
      final id = await txn.insert('purchases', {
        'date': date,
        'supplier_id': supplierId,
        'shop': shop,
        'items': items.map((i) => i['name']).join(', '),
        'amount': total,
        'status': 'Received',
        'pay_mode': payMode,
        'slip': slip,
        'note': note,
      });
      for (final i in items) {
        await txn.insert('purchase_items', {
          'purchase_id': id,
          'name': i['name'],
          'qty': i['qty'],
          'unit': i['unit'],
          'amount': i['amount'],
        });
      }
    });
  }

  static Future<void> updatePurchaseFull({
    required int id,
    required String date,
    required String shop,
    required List<Map<String, Object?>> items,
    required double total,
    required String payMode,
    required String slip,
    required String note,
    required String status,
    int? supplierId,
  }) async {
    await _d.transaction((txn) async {
      await txn.update(
          'purchases',
          {
            'supplier_id': supplierId,
            'date': date,
            'shop': shop,
            'items': items.map((i) => i['name']).join(', '),
            'amount': total,
            'status': status,
            'pay_mode': payMode,
            'slip': slip,
            'note': note,
          },
          where: 'id = ?',
          whereArgs: [id]);
      await txn.delete('purchase_items', where: 'purchase_id = ?', whereArgs: [id]);
      for (final i in items) {
        await txn.insert('purchase_items', {
          'purchase_id': id,
          'name': i['name'],
          'qty': i['qty'],
          'unit': i['unit'],
          'amount': i['amount'],
        });
      }
    });
  }

  static Future<List<Map<String, Object?>>> purchaseItems(int id) =>
      _d.query('purchase_items', where: 'purchase_id = ?', whereArgs: [id], orderBy: 'id');

  /// Profit = sales (without GST) - purchases - all expenses (salary, rent...).
  static Future<Map<String, double>> profit(String from, String to) async {
    final t = await Db.reportTotals(from, to);
    final pur = await purchases(from, to);
    final exp = await expenses(from, to);
    double sum(List<Map<String, Object?>> l) =>
        l.fold(0.0, (a, r) => a + ((r['amount'] as num?)?.toDouble() ?? 0));
    final net = (t['total'] ?? 0) - (t['gst'] ?? 0);
    final p = sum(pur);
    final e = sum(exp);
    return {'net': net, 'purchases': p, 'expenses': e, 'profit': net - p - e};
  }

  static Future<void> setPurchaseStatus(int id, String status) async {
    await _d.update('purchases', {'status': status},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deletePurchase(int id) async {
    await _d.delete('purchase_items', where: 'purchase_id = ?', whereArgs: [id]);
    await _d.delete('purchases', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------ inventory
  static Future<List<Map<String, Object?>>> stock() =>
      _d.query('inventory', orderBy: 'name');

  static Future<void> saveStock(
      int? id, String name, double qty, String unit, double minQty) async {
    final m = {'name': name, 'qty': qty, 'unit': unit, 'min_qty': minQty};
    if (id == null) {
      await _d.insert('inventory', m);
    } else {
      await _d.update('inventory', m, where: 'id = ?', whereArgs: [id]);
    }
  }

  static Future<void> deleteStock(int id) async {
    await _d.delete('inventory', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------ customers
  static Future<List<Map<String, Object?>>> customers([String search = '']) =>
      _d.rawQuery(
          'SELECT c.*, COALESCE(SUM(b.total),0) AS spent, COUNT(b.id) AS visits '
          'FROM customers c LEFT JOIN bills b ON b.customer_id = c.id AND b.status = \'paid\' '
          'WHERE c.name LIKE ? OR c.phone LIKE ? GROUP BY c.id ORDER BY c.name',
          ['%$search%', '%$search%']);

  static Future<int> saveCustomer(int? id, String name, String phone) async {
    if (id == null) {
      return _d.insert('customers', {'name': name, 'phone': phone});
    }
    await _d.update('customers', {'name': name, 'phone': phone},
        where: 'id = ?', whereArgs: [id]);
    return id;
  }

  static Future<void> deleteCustomer(int id) async {
    await _d.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  static Future<String> customerName(int? id) async {
    if (id == null) return '';
    final r = await _d.query('customers', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? '' : r.first['name'] as String;
  }

  // ------------------------------------------------------------ staff + roles
  static Future<List<Map<String, Object?>>> staff() =>
      _d.query('staff', orderBy: 'name');

  static Future<void> saveStaff(int? id, String name, String role, String phone,
      bool active, String pin,
      {String? username, String? password}) async {
    final m = <String, Object?>{
      'name': name,
      'role': role,
      'phone': phone,
      'active': active ? 1 : 0,
      'pin': pin,
    };
    if (username != null) m['username'] = username.trim();
    if (password != null && password.isNotEmpty) m['pass_hash'] = hashPass(password);
    if (id == null) {
      await _d.insert('staff', m);
    } else {
      await _d.update('staff', m, where: 'id = ?', whereArgs: [id]);
    }
  }

  /// True when another staff member already uses this username.
  static Future<bool> usernameTaken(String username, int? exceptId) async {
    final r = await _d.query('staff',
        where: 'LOWER(username) = ? AND id != ?',
        whereArgs: [username.trim().toLowerCase(), exceptId ?? -1]);
    return r.isNotEmpty;
  }

  static Future<void> deleteStaff(int id) async {
    await _d.delete('staff', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<Map<String, Object?>>> roles() =>
      _d.query('roles', orderBy: 'id');

  static Future<void> saveRole(int? id, String name, String perms) async {
    if (id == null) {
      await _d.insert('roles', {'name': name, 'perms': perms});
    } else {
      await _d.update('roles', {'name': name, 'perms': perms},
          where: 'id = ?', whereArgs: [id]);
    }
  }

  static Future<void> deleteRole(int id) async {
    await _d.delete('roles', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------ login
  /// Starting password of the admin user. The Admin can change it in Staff.
  static const String _defaultAdminPass = 'admin@123';

  static String hashPass(String pass) =>
      sha256.convert(utf8.encode('udupi|$pass')).toString();

  static Future<void> _loginCols(Database d) async {
    final cols = await d.rawQuery('PRAGMA table_info(staff)');
    final names = {for (final c in cols) c['name'] as String};
    if (!names.contains('username')) {
      await d.execute("ALTER TABLE staff ADD COLUMN username TEXT NOT NULL DEFAULT ''");
    }
    if (!names.contains('pass_hash')) {
      await d.execute("ALTER TABLE staff ADD COLUMN pass_hash TEXT NOT NULL DEFAULT ''");
    }
  }

  /// Makes sure the user "admin" exists (role Admin, sees everything).
  static Future<void> ensureAdminLogin() async {
    await _loginCols(_d);
    final role = await _d.query('roles', where: 'name = ?', whereArgs: ['Admin']);
    if (role.isEmpty) await _d.insert('roles', {'name': 'Admin', 'perms': 'all'});
    final a = await _d.query('staff', where: "LOWER(username) = 'admin'");
    if (a.isNotEmpty) return;
    final h = hashPass(_defaultAdminPass);
    final owner = await _d.query('staff',
        where: "role = 'Admin' AND username = ''", orderBy: 'id', limit: 1);
    if (owner.isNotEmpty) {
      await _d.update('staff', {'username': 'admin', 'pass_hash': h, 'active': 1},
          where: 'id = ?', whereArgs: [owner.first['id']]);
    } else {
      await _d.insert('staff', {
        'name': 'Admin',
        'role': 'Admin',
        'phone': '',
        'active': 1,
        'pin': '',
        'username': 'admin',
        'pass_hash': h,
      });
    }
  }

  /// Checks username + password. Returns name, role and the pages allowed,
  /// or null when they do not match (or the user is Inactive).
  static Future<Map<String, Object?>?> login(String user, String pass) async {
    await ensureAdminLogin();
    final u = user.trim().toLowerCase();
    if (u.isEmpty || pass.isEmpty) return null;
    final r = await _d.rawQuery(
        'SELECT st.name AS name, st.role AS role, ro.perms AS perms '
        'FROM staff st JOIN roles ro ON ro.name = st.role '
        'WHERE st.active = 1 AND LOWER(st.username) = ? AND st.pass_hash = ? LIMIT 1',
        [u, hashPass(pass)]);
    return r.isEmpty ? null : r.first;
  }

  /// True when at least one active staff member has a PIN. Then the app
  /// asks for a PIN when it starts.
  static Future<bool> pinLoginOn() async {
    final r = await _d.rawQuery(
        "SELECT COUNT(*) AS c FROM staff WHERE active = 1 AND pin != ''");
    return (r.first['c'] as int) > 0;
  }

  /// Returns the pages this PIN may open, or null when the PIN is wrong.
  static Future<Set<String>?> loginByPin(String pin) async {
    if (pin.isEmpty) return null;
    final r = await _d.rawQuery(
        'SELECT ro.perms AS perms FROM staff st JOIN roles ro ON ro.name = st.role '
        'WHERE st.active = 1 AND st.pin = ? LIMIT 1',
        [pin]);
    if (r.isEmpty) return null;
    return permSet(r.first['perms'] as String);
  }

  static Set<String> permSet(String perms) {
    if (perms.trim() == 'all') return allModules.toSet();
    return perms.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  /// If the file Documents\HotelBilling\reset_pin.txt exists, all PINs are
  /// cleared once and the file is removed. For a forgotten PIN.
  static Future<bool> resetPinsIfAsked() async {
    final f = File(p.join(Db.baseDir, 'reset_pin.txt'));
    if (!await f.exists()) return false;
    await _d.update('staff', {'pin': ''});
    await _d.update('staff', {'pass_hash': hashPass(_defaultAdminPass)},
        where: "LOWER(username) = 'admin'");
    try {
      await f.delete();
    } catch (_) {}
    return true;
  }

  // ------------------------------------------------------------ table list
  /// The tables of the hotel (id never changes, name can be edited).
  static List<TableDef> tableList() {
    final raw = Db.s('table_list');
    if (raw.isNotEmpty) {
      try {
        final l = jsonDecode(raw) as List;
        return [
          for (final e in l)
            TableDef(e['id'] as int, e['name'] as String,
                chairs: (e['chairs'] as num?)?.toInt() ?? 4,
                shape: (e['shape'] ?? 'square') as String,
                fx: (e['fx'] as num?)?.toDouble(),
                fy: (e['fy'] as num?)?.toDouble(),
                size: (e['size'] as num?)?.toDouble() ?? 1.0)
        ];
      } catch (_) {}
    }
    final n = int.tryParse(Db.s('tables')) ?? 10;
    return [for (var i = 1; i <= n; i++) TableDef(i, '$i')];
  }

  static Future<void> saveTableList(List<TableDef> l) => Db.setS(
      'table_list', jsonEncode([for (final t in l) t.toJson()]));

  // ------------------------------------------------------------ tables
  /// Saved state: Reserved or Cleaning. Anything else means free.
  static Future<Map<int, Map<String, Object?>>> tableStates() async {
    final r = await _d.query('table_state');
    return {for (final x in r) x['num'] as int: x};
  }

  static Future<void> setTableState(int num, String state, String note) async {
    if (state == 'Free') {
      await _d.delete('table_state', where: 'num = ?', whereArgs: [num]);
    } else {
      await _d.insert('table_state', {'num': num, 'state': state, 'note': note},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // ------------------------------------------------------------ kitchen
  static Future<List<KOrder>> kitchenOrders() async {
    final rows = await _d.rawQuery(
        "SELECT * FROM bills WHERE date = ? AND status != 'void' "
        "AND kstatus IN ('new','preparing','ready') ORDER BY id",
        [todayStr()]);
    final out = <KOrder>[];
    for (final b in rows) {
      final it = await _d.query('bill_items',
          where: 'bill_id = ?', whereArgs: [b['id']], orderBy: 'id');
      out.add(KOrder(
        b['id'] as int,
        b['label'] as String,
        b['order_type'] as String,
        b['kstatus'] as String,
        DateTime.parse(b['created_at'] as String),
        [
          for (final i in it)
            KItem(i['name'] as String, i['qty'] as int, (i['note'] ?? '') as String)
        ],
      ));
    }
    return out;
  }

  static Future<void> setKStatus(int billId, String st) async {
    await _d.update('bills', {'kstatus': st}, where: 'id = ?', whereArgs: [billId]);
  }

  // ------------------------------------------------------------ report helpers
  /// Sales (paid bills) by hour of one day: {hour: total}
  static Future<Map<int, double>> salesByHour(String day) async {
    final r = await _d.rawQuery(
        "SELECT created_at, total FROM bills WHERE date = ? AND status = 'paid'",
        [day]);
    final m = <int, double>{};
    for (final x in r) {
      final h = DateTime.parse(x['created_at'] as String).hour;
      m[h] = (m[h] ?? 0) + (x['total'] as num).toDouble();
    }
    return m;
  }

  /// Sales by day: list of (date, total)
  static Future<List<Map<String, Object?>>> salesByDay(String from, String to) =>
      _d.rawQuery(
          "SELECT date, SUM(total) AS t FROM bills WHERE date BETWEEN ? AND ? AND status = 'paid' GROUP BY date ORDER BY date",
          [from, to]);

  /// Sales by section (category): list of (sn, a)
  static Future<List<Map<String, Object?>>> salesBySection(
          String from, String to) =>
      _d.rawQuery(
          'SELECT bi.section_name AS sn, SUM(bi.amount) AS a FROM bill_items bi '
          "JOIN bills b ON b.id = bi.bill_id WHERE b.date BETWEEN ? AND ? AND b.status = 'paid' "
          'GROUP BY bi.section_name ORDER BY a DESC',
          [from, to]);

  /// GST table by section: taxable value (after discount) and GST.
  static Future<List<Map<String, Object?>>> gstBySection(
          String from, String to) =>
      _d.rawQuery(
          'SELECT bi.section_name AS sn, '
          'SUM(bi.amount * (1.0 - CASE WHEN b.subtotal > 0 THEN b.discount / b.subtotal ELSE 0 END)) AS taxable, '
          'SUM(bi.amount * (1.0 - CASE WHEN b.subtotal > 0 THEN b.discount / b.subtotal ELSE 0 END) * b.gst_pct / 100.0) AS gst '
          'FROM bill_items bi JOIN bills b ON b.id = bi.bill_id '
          "WHERE b.date BETWEEN ? AND ? AND b.status = 'paid' GROUP BY bi.section_name ORDER BY bi.section_name",
          [from, to]);

  static Future<int> openTables() async {
    final r = await _d.rawQuery(
        "SELECT COUNT(DISTINCT label) AS c FROM bills WHERE status = 'draft' AND label LIKE 'Table: %'");
    return r.first['c'] as int;
  }

  // ------------------------------------------------------------ backup
  static Future<List<File>> backupFiles() async {
    final dir = Directory(p.join(Db.baseDir, 'Backups'));
    if (!await dir.exists()) return [];
    final files = (await dir.list().toList())
        .whereType<File>()
        .where((f) => f.path.endsWith('.db'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// Replace the live data with a backup file, then open it again.
  static Future<void> restore(File backup) async {
    // Save today's data first, in case of a wrong click.
    final safe = File(p.join(Db.baseDir, 'Backups', 'before_restore.db'));
    await Db.db.close();
    await File(Db.dbPath).copy(safe.path);
    await backup.copy(Db.dbPath);
    for (final ext in ['-wal', '-shm']) {
      final f = File('${Db.dbPath}$ext');
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    await Db.reopen();
  }
}

class TableDef {
  final int id;
  final String name;
  final int chairs;
  final String shape; // square | round
  final double? fx; // position on the floor, 0..1 (null = automatic place)
  final double? fy;
  final double size; // 0.4 (small) .. 2.0 (big), 1 = normal
  const TableDef(this.id, this.name,
      {this.chairs = 4, this.shape = 'square', this.fx, this.fy, this.size = 1.0});
  TableDef copy(
          {String? name, int? chairs, String? shape, double? fx, double? fy, double? size}) =>
      TableDef(id, name ?? this.name,
          chairs: chairs ?? this.chairs,
          shape: shape ?? this.shape,
          fx: fx ?? this.fx,
          fy: fy ?? this.fy,
          size: size ?? this.size);
  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'chairs': chairs, 'shape': shape, 'fx': fx, 'fy': fy, 'size': size};
}
