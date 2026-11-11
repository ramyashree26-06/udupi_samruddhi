import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'menu_seed.dart';
import 'db2.dart';
import 'models.dart';
import 'util.dart';

/// All data lives in one local SQLite file. No server, no internet.
class Db {
  static late Database db;
  static late String baseDir; // Documents\HotelBilling
  static late String dbPath;
  static Map<String, String> cfg = {};

  static const Map<String, String> defaults = {
    'hotel_name': 'Udupi Samruddhi',
    'address':
        '179/2, Kothnur, Deepthi Nagar, JP Nagar 9th Phase, Bengaluru 560108',
    'phone': '8660873733, 7349255700',
    'gstin': '',
    'gst_pct': '5',
    'order_mode': 'table', // table | token | none
    'kot_with_bill': '1', // 1 = print the kitchen slip together with every bill
    'split_slips': '1', // 1 = one kitchen slip per section
    'printer_mode': 'none', // none | windows | network
    'printer_name': '',
    'printer_ip': '',
    'printer_port': '9100',
    'paper_mm': '80', // 80 | 58
    'footer': 'Thank you! Visit again',
    'printer_model': '', // just a note: brand and model
    'logo_opacity': '0.10', // watermark strength
    'price_step': '5', // the +/- buttons in the Menu change price by this
    'tables': '10', // how many tables in the table list
    'auto_backup': '1', // daily backup while the app is open
    'backup_time': '23:00', // time of the daily backup (24 hour)
    'currency': 'INR (Rs)',
    // Daily report e-mail. Only SAVED for now; nothing is sent yet.
    // The mail password is NOT kept here (it would travel inside backups).
    'mail_enabled': '0',
    'mail_to': '', // admin address(es), comma separated
    'mail_from': '',
    'mail_host': '', // e.g. smtp.gmail.com
    'mail_port': '587',
    'mail_user': '',
    'mail_time': '23:30', // when the daily report should be sent
  };

  // ---------- settings ----------
  static String s(String k) => cfg[k] ?? defaults[k] ?? '';
  static double d(String k) => double.tryParse(s(k)) ?? 0;

  static Future<void> setS(String k, String v) async {
    cfg[k] = v;
    await db.insert('settings', {'k': k, 'v': v},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> _loadSettings() async {
    final rows = await db.query('settings');
    cfg = {for (final r in rows) r['k'] as String: r['v'] as String};
  }

  // ---------- start ----------
  static Future<void> init() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final docs = await getApplicationDocumentsDirectory();
    baseDir = p.join(docs.path, 'HotelBilling');
    await Directory(baseDir).create(recursive: true);
    dbPath = p.join(baseDir, 'billing.db');
    db = await _open();
    await _loadSettings();
  }

  static Future<Database> _open() {
    return databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: _create,
        onUpgrade: _upgrade,
        onOpen: _ensureSplit,
      ),
    );
  }

  /// Used after a backup is restored: open the (new) file again.
  static Future<void> reopen() async {
    db = await _open();
    await _loadSettings();
  }

  static Future<void> _create(Database d, int v) async {
    await d.execute(
        'CREATE TABLE sections(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, sort INTEGER NOT NULL DEFAULT 0)');
    await d.execute(
        "CREATE TABLE dishes(id INTEGER PRIMARY KEY AUTOINCREMENT, section_id INTEGER NOT NULL, name TEXT NOT NULL, price REAL NOT NULL, closed_date TEXT, grp TEXT NOT NULL DEFAULT '')");
    await d.execute(
        "CREATE TABLE bills(id INTEGER PRIMARY KEY AUTOINCREMENT, bill_no INTEGER NOT NULL, date TEXT NOT NULL, created_at TEXT NOT NULL, label TEXT NOT NULL DEFAULT '', subtotal REAL NOT NULL, gst_pct REAL NOT NULL, gst_amt REAL NOT NULL, total REAL NOT NULL, status TEXT NOT NULL DEFAULT 'paid', pay_mode TEXT NOT NULL DEFAULT 'Cash', order_type TEXT NOT NULL DEFAULT 'Dine In', discount REAL NOT NULL DEFAULT 0, kstatus TEXT NOT NULL DEFAULT '', customer_id INTEGER)");
    await d.execute(
        "CREATE TABLE bill_items(id INTEGER PRIMARY KEY AUTOINCREMENT, bill_id INTEGER NOT NULL, dish_id INTEGER, section_id INTEGER, section_name TEXT NOT NULL, name TEXT NOT NULL, qty INTEGER NOT NULL, price REAL NOT NULL, amount REAL NOT NULL, note TEXT NOT NULL DEFAULT '')");
    await d.execute('CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT NOT NULL)');
    await d.execute('CREATE INDEX idx_bills_date ON bills(date)');
    await d.execute('CREATE INDEX idx_items_bill ON bill_items(bill_id)');
    await _seedMenu(d);
    await Db2.createTables(d);
  }

  /// Extra columns / tables added later (safe to run on every start).
  static Future<void> _ensureSplit(Database d) async {
    final tabs = await d.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final tn = tabs.map((t) => t['name']).toSet();
    Future<void> addCol(String table, String col, String def) async {
      if (!tn.contains(table)) return;
      final c = await d.rawQuery('PRAGMA table_info($table)');
      if (!c.map((x) => x['name']).contains(col)) {
        await d.execute('ALTER TABLE $table ADD COLUMN $col $def');
      }
    }
    // 'Take Away' and 'Parcel' were the same: keep only Parcel
    await d.execute("UPDATE bills SET order_type = 'Parcel' WHERE order_type = 'Take Away'");
    // cash + online split on one bill
    await addCol('bills', 'pay_cash', 'REAL NOT NULL DEFAULT 0');
    await addCol('bills', 'pay_online', 'REAL NOT NULL DEFAULT 0');
    // own photo for a dish
    await addCol('dishes', 'photo', "TEXT NOT NULL DEFAULT ''");
    // outside purchases: shop name, how paid, slip photo, note, item lines
    await addCol('purchases', 'shop', "TEXT NOT NULL DEFAULT ''");
    await addCol('purchases', 'pay_mode', "TEXT NOT NULL DEFAULT 'Cash'");
    await addCol('purchases', 'slip', "TEXT NOT NULL DEFAULT ''");
    await addCol('purchases', 'note', "TEXT NOT NULL DEFAULT ''");
    // suppliers: what we take from them + address
    await addCol('suppliers', 'supplies', "TEXT NOT NULL DEFAULT ''");
    await addCol('suppliers', 'address', "TEXT NOT NULL DEFAULT ''");
    if (tn.contains('purchases') && tn.contains('suppliers')) {
      // old purchases typed with a saved supplier's name get linked to it
      await d.execute(
          "UPDATE purchases SET supplier_id = (SELECT id FROM suppliers WHERE lower(trim(name)) = lower(trim(purchases.shop)) LIMIT 1) "
          "WHERE supplier_id IS NULL AND shop != ''");
    }
    await d.execute(
        'CREATE TABLE IF NOT EXISTS purchase_items(id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_id INTEGER NOT NULL, name TEXT NOT NULL, qty REAL NOT NULL DEFAULT 0, unit TEXT NOT NULL DEFAULT \'\', amount REAL NOT NULL)');
  }

  static Future<void> _upgrade(Database d, int oldV, int newV) async {
    if (oldV < 2) {
      await d.execute("ALTER TABLE dishes ADD COLUMN grp TEXT NOT NULL DEFAULT ''");
      await d.execute("ALTER TABLE bills ADD COLUMN status TEXT NOT NULL DEFAULT 'paid'");
      await d.execute("ALTER TABLE bills ADD COLUMN pay_mode TEXT NOT NULL DEFAULT 'Cash'");
      await d.execute("ALTER TABLE bills ADD COLUMN order_type TEXT NOT NULL DEFAULT 'Dine In'");
      await d.execute('ALTER TABLE bills ADD COLUMN discount REAL NOT NULL DEFAULT 0');
      await d.execute("ALTER TABLE bill_items ADD COLUMN note TEXT NOT NULL DEFAULT ''");
      // An older test database with no bills only has the sample menu:
      // replace it with the real Udupi Samruddhi menu.
      final r = await d.rawQuery('SELECT COUNT(*) AS c FROM bills');
      if ((r.first['c'] as int) == 0) {
        await d.delete('dishes');
        await d.delete('sections');
        await _seedMenu(d);
      }
    }
    if (oldV < 3) {
      await d.execute("ALTER TABLE bills ADD COLUMN kstatus TEXT NOT NULL DEFAULT ''");
      await d.execute('ALTER TABLE bills ADD COLUMN customer_id INTEGER');
      await Db2.createTables(d);
    }
  }

  /// The real menu from the hotel's menu card (237 dishes).
  static Future<void> _seedMenu(Database d) async {
    final secId = <String, int>{};
    var sort = 0;
    for (final row in kMenuSeed) {
      final sec = row[0] as String;
      if (!secId.containsKey(sec)) {
        secId[sec] = await d.insert('sections', {'name': sec, 'sort': sort++});
      }
    }
    final batch = d.batch();
    for (final row in kMenuSeed) {
      batch.insert('dishes', {
        'section_id': secId[row[0] as String],
        'grp': row[1] as String,
        'name': row[2] as String,
        'price': (row[3] as num).toDouble(),
      });
    }
    await batch.commit(noResult: true);
  }

  // ---------- sections ----------
  static Future<List<Section>> sections() async {
    final rows = await db.query('sections', orderBy: 'sort, id');
    return rows.map(Section.fromMap).toList();
  }

  static Future<void> addSection(String name) async {
    final r = await db.rawQuery('SELECT COALESCE(MAX(sort),0)+1 AS n FROM sections');
    await db.insert('sections', {'name': name, 'sort': r.first['n'] as int});
  }

  static Future<void> renameSection(int id, String name) async {
    await db.update('sections', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteSection(int id) async {
    await db.delete('dishes', where: 'section_id = ?', whereArgs: [id]);
    await db.delete('sections', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- dishes ----------
  static Future<List<Dish>> dishes({
    int? sectionId,
    String? search,
    bool onlyOpen = false,
  }) async {
    final t = todayStr();
    final where = <String>[];
    final args = <Object?>[];
    if (sectionId != null) {
      where.add('d.section_id = ?');
      args.add(sectionId);
    }
    final hasSearch = search != null && search.isNotEmpty;
    if (hasSearch) {
      where.add('d.name LIKE ?');
      args.add('%$search%');
    }
    if (onlyOpen) {
      where.add('(d.closed_date IS NULL OR d.closed_date != ?)');
      args.add(t);
    }
    var order = 's.sort, s.id, d.id';
    if (hasSearch) {
      order = 'CASE WHEN d.name LIKE ? THEN 0 ELSE 1 END, $order';
      args.add('$search%');
    }
    final rows = await db.rawQuery(
      'SELECT d.*, s.name AS section_name FROM dishes d '
      'JOIN sections s ON s.id = d.section_id '
      '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
      'ORDER BY $order',
      args,
    );
    return rows.map((m) => Dish.fromMap(m, t)).toList();
  }

  static Future<Dish?> dishById(int id) async {
    final rows = await db.rawQuery(
      'SELECT d.*, s.name AS section_name FROM dishes d '
      'JOIN sections s ON s.id = d.section_id WHERE d.id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    return Dish.fromMap(rows.first, todayStr());
  }

  static Future<List<String>> groups(int sectionId) async {
    final rows = await db.rawQuery(
      "SELECT grp FROM dishes WHERE section_id = ? AND grp != '' "
      'GROUP BY grp ORDER BY MIN(id)',
      [sectionId],
    );
    return rows.map((r) => r['grp'] as String).toList();
  }

  static Future<void> addDish(int sectionId, String name, double price,
      {String group = '', String photo = ''}) async {
    await db.insert('dishes', {
      'section_id': sectionId,
      'name': name,
      'price': price,
      'grp': group,
      'photo': photo
    });
  }

  static Future<void> updateDish(int id,
      {required String name,
      required double price,
      required String group,
      int? sectionId,
      String? photo}) async {
    final m = <String, Object?>{'name': name, 'price': price, 'grp': group};
    if (photo != null) m['photo'] = photo;
    if (sectionId != null) m['section_id'] = sectionId;
    await db.update('dishes', m, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> setPrice(int id, double price) async {
    await db.update('dishes', {'price': price < 0 ? 0 : price},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Closed for today only: we store today's date. Tomorrow it no longer
  /// matches, so the dish opens again by itself.
  static Future<void> setClosedToday(int id, bool closed) async {
    await db.update('dishes', {'closed_date': closed ? todayStr() : null},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteDish(int id) async {
    await db.delete('dishes', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- bills ----------
  static Future<int> nextBillNo() async {
    final r = await db.rawQuery(
        "SELECT COALESCE(MAX(bill_no),0)+1 AS n FROM bills WHERE date = ? AND status != 'draft'",
        [todayStr()]);
    return r.first['n'] as int;
  }

  static Future<int> nextToken() async {
    final r = await db.rawQuery(
        "SELECT COUNT(*)+1 AS n FROM bills WHERE date = ? AND status = 'paid'",
        [todayStr()]);
    return r.first['n'] as int;
  }

  static double _gst(double sub, double discount, double pct) =>
      r2(((sub - discount) < 0 ? 0 : (sub - discount)) * pct / 100);

  static Future<int> saveBill({
    required String label,
    required String orderType,
    required String payMode,
    required double discount,
    required List<CartLine> lines,
    required double gstPct,
    int? draftId,
    int? customerId,
    double? cashAmt, // only for payMode 'Split': the cash part
  }) async {
    final now = DateTime.now();
    final date = dayStr(now);
    var sub = 0.0;
    for (final l in lines) {
      sub += l.amount;
    }
    sub = r2(sub);
    final disc = r2(discount > sub ? sub : discount);
    final gst = _gst(sub, disc, gstPct);
    final total = r2(sub - disc + gst);
    return db.transaction<int>((txn) async {
      var ks = '';
      var cid = customerId;
      if (draftId != null) {
        final o = await txn.query('bills',
            columns: ['kstatus', 'customer_id'],
            where: 'id = ?',
            whereArgs: [draftId]);
        if (o.isNotEmpty) {
          ks = (o.first['kstatus'] ?? '') as String;
          cid ??= o.first['customer_id'] as int?;
        }
        await txn.delete('bill_items', where: 'bill_id = ?', whereArgs: [draftId]);
        await txn.delete('bills', where: 'id = ?', whereArgs: [draftId]);
      }
      final r = await txn.rawQuery(
          "SELECT COALESCE(MAX(bill_no),0)+1 AS n FROM bills WHERE date = ? AND status != 'draft'",
          [date]);
      final no = r.first['n'] as int;
      final id = await txn.insert('bills', {
        'bill_no': no,
        'date': date,
        'created_at': now.toIso8601String(),
        'label': label,
        'subtotal': sub,
        'gst_pct': gstPct,
        'gst_amt': gst,
        'total': total,
        'status': 'paid',
        'pay_mode': payMode,
        'pay_cash': payMode == 'Split'
            ? r2(cashAmt ?? 0)
            : (payMode == 'Cash' ? total : 0.0),
        'pay_online': payMode == 'Split'
            ? r2(total - (cashAmt ?? 0))
            : (payMode == 'UPI' ? total : 0.0),
        'order_type': orderType,
        'discount': disc,
        'kstatus': ks,
        'customer_id': cid,
      });
      for (final l in lines) {
        await txn.insert('bill_items', {
          'bill_id': id,
          'dish_id': l.dish.id,
          'section_id': l.dish.sectionId,
          'section_name': l.dish.sectionName,
          'name': l.dish.name,
          'qty': l.qty,
          'price': l.dish.price,
          'amount': r2(l.amount),
          'note': l.note,
        });
      }
      return id;
    });
  }

  // ---------- drafts (saved orders, not yet billed) ----------
  static Future<int> saveDraft({
    required String label,
    required String orderType,
    required double discount,
    required List<CartLine> lines,
    int? draftId,
    int? customerId,
    String kstatus = '',
  }) async {
    final now = DateTime.now();
    var sub = 0.0;
    for (final l in lines) {
      sub += l.amount;
    }
    sub = r2(sub);
    return db.transaction<int>((txn) async {
      var ks = kstatus;
      var cid = customerId;
      if (draftId != null) {
        final o = await txn.query('bills',
            columns: ['kstatus', 'customer_id'],
            where: 'id = ?',
            whereArgs: [draftId]);
        if (o.isNotEmpty) {
          if (ks.isEmpty) ks = (o.first['kstatus'] ?? '') as String;
          cid ??= o.first['customer_id'] as int?;
        }
        await txn.delete('bill_items', where: 'bill_id = ?', whereArgs: [draftId]);
        await txn.delete('bills', where: 'id = ?', whereArgs: [draftId]);
      }
      final id = await txn.insert('bills', {
        'bill_no': 0,
        'date': dayStr(now),
        'created_at': now.toIso8601String(),
        'label': label,
        'subtotal': sub,
        'gst_pct': 0,
        'gst_amt': 0,
        'total': sub,
        'status': 'draft',
        'pay_mode': '',
        'order_type': orderType,
        'discount': discount,
        'kstatus': ks,
        'customer_id': cid,
      });
      for (final l in lines) {
        await txn.insert('bill_items', {
          'bill_id': id,
          'dish_id': l.dish.id,
          'section_id': l.dish.sectionId,
          'section_name': l.dish.sectionName,
          'name': l.dish.name,
          'qty': l.qty,
          'price': l.dish.price,
          'amount': r2(l.amount),
          'note': l.note,
        });
      }
      return id;
    });
  }

  /// Puts a saved draft back on the screen so billing can continue.
  static Future<void> openDraft(int id) async {
    final b = (await db.query('bills', where: 'id = ?', whereArgs: [id])).first;
    final items = await db.query('bill_items',
        where: 'bill_id = ?', whereArgs: [id], orderBy: 'id');
    cart.clear();
    cart.orderType = b['order_type'] as String;
    cart.label = b['label'] as String;
    cart.discount = (b['discount'] as num).toDouble();
    cart.draftId = id;
    cart.customerId = b['customer_id'] as int?;
    cart.customerName = await Db2.customerName(cart.customerId);
    for (final it in items) {
      Dish? dish;
      final did = it['dish_id'] as int?;
      if (did != null) dish = await dishById(did);
      dish ??= Dish(
        id: did ?? -(it['id'] as int),
        sectionId: (it['section_id'] as int?) ?? 0,
        sectionName: it['section_name'] as String,
        group: '',
        name: it['name'] as String,
        price: (it['price'] as num).toDouble(),
        closedToday: false,
      );
      cart.add(dish, qty: it['qty'] as int, note: (it['note'] ?? '') as String);
    }
  }

  static Future<void> deleteDraft(int id) async {
    await db.delete('bill_items', where: 'bill_id = ?', whereArgs: [id]);
    await db.delete('bills', where: "id = ? AND status = 'draft'", whereArgs: [id]);
  }

  static Future<List<BillRow>> drafts() => _rows("b.status = 'draft'", [],
      'b.created_at DESC');

  static Future<List<BillRow>> billsOn(String date) =>
      _rows("b.status != 'draft' AND b.date = ?", [date], 'b.id DESC');

  static Future<List<BillRow>> _rows(
      String where, List<Object?> args, String order) async {
    final rows = await db.rawQuery(
        'SELECT b.* FROM bills b WHERE $where ORDER BY $order', args);
    return rows
        .map((m) => BillRow(
              m['id'] as int,
              m['bill_no'] as int,
              m['status'] as String,
              DateTime.parse(m['created_at'] as String),
              m['label'] as String,
              m['order_type'] as String,
              m['pay_mode'] as String,
              (m['total'] as num).toDouble(),
              (m['kstatus'] ?? '') as String,
            ))
        .toList();
  }

  /// A cancelled bill stays in the list but is left out of reports.
  static Future<void> voidBill(int id) async {
    await db.update('bills', {'status': 'void'}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<BillData> getBill(int id) async {
    final b = (await db.query('bills', where: 'id = ?', whereArgs: [id])).first;
    final it = await db.query('bill_items',
        where: 'bill_id = ?', whereArgs: [id], orderBy: 'id');
    return BillData(
      id: id,
      billNo: b['bill_no'] as int,
      createdAt: DateTime.parse(b['created_at'] as String),
      label: b['label'] as String,
      orderType: b['order_type'] as String,
      payMode: (b['pay_mode'] as String) == 'Split'
          ? 'Cash Rs.${money(((b['pay_cash'] ?? 0) as num).toDouble())} + Online Rs.${money(((b['pay_online'] ?? 0) as num).toDouble())}'
          : b['pay_mode'] as String,
      status: b['status'] as String,
      subtotal: (b['subtotal'] as num).toDouble(),
      discount: (b['discount'] as num).toDouble(),
      gstPct: (b['gst_pct'] as num).toDouble(),
      gstAmt: (b['gst_amt'] as num).toDouble(),
      total: (b['total'] as num).toDouble(),
      items: it
          .map((m) => BillItem(
                m['name'] as String,
                m['qty'] as int,
                (m['price'] as num).toDouble(),
                (m['amount'] as num).toDouble(),
                (m['note'] ?? '') as String,
              ))
          .toList(),
    );
  }

  // ---------- reports ----------
  /// Rows: d (date or ''), sn (section), n (dish), q (qty), a (amount)
  static Future<List<Map<String, Object?>>> reportRows(
      String from, String to, bool dayWise) {
    return db.rawQuery(
      "SELECT ${dayWise ? 'b.date' : "''"} AS d, "
      'COALESCE(s.name, bi.section_name) AS sn, bi.name AS n, '
      'SUM(bi.qty) AS q, SUM(bi.amount) AS a '
      'FROM bill_items bi JOIN bills b ON b.id = bi.bill_id '
      'LEFT JOIN sections s ON s.id = bi.section_id '
      "WHERE b.date BETWEEN ? AND ? AND b.status = 'paid' "
      'GROUP BY ${dayWise ? 'b.date, ' : ''}bi.section_id, bi.name '
      'ORDER BY ${dayWise ? 'b.date, ' : ''}COALESCE(s.sort, 999), bi.section_name, bi.name',
      [from, to],
    );
  }

  static Future<Map<String, double>> reportTotals(String from, String to) async {
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c, COALESCE(SUM(subtotal),0) AS s, '
      'COALESCE(SUM(discount),0) AS di, '
      'COALESCE(SUM(gst_amt),0) AS g, COALESCE(SUM(total),0) AS t '
      "FROM bills WHERE date BETWEEN ? AND ? AND status = 'paid'",
      [from, to],
    );
    final m = r.first;
    return {
      'bills': (m['c'] as num).toDouble(),
      'subtotal': (m['s'] as num).toDouble(),
      'discount': (m['di'] as num).toDouble(),
      'gst': (m['g'] as num).toDouble(),
      'total': (m['t'] as num).toDouble(),
    };
  }

  /// Money received by payment type in the date range (Cash / UPI / Card).
  static Future<Map<String, double>> payTotals(String from, String to) async {
    final r = await db.rawQuery(
      'SELECT pay_mode AS m, COALESCE(SUM(total),0) AS t, '
      'COALESCE(SUM(pay_cash),0) AS c, COALESCE(SUM(pay_online),0) AS o FROM bills '
      "WHERE date BETWEEN ? AND ? AND status = 'paid' GROUP BY pay_mode",
      [from, to],
    );
    final out = <String, double>{};
    void add(String k, double v) => out[k] = (out[k] ?? 0) + v;
    for (final x in r) {
      final m = x['m'] as String;
      if (m == 'Split') {
        add('Cash', (x['c'] as num).toDouble());
        add('UPI', (x['o'] as num).toDouble());
      } else {
        add(m, (x['t'] as num).toDouble());
      }
    }
    return out;
  }

  // ---------- backup ----------
  /// Copies the database to Documents\HotelBilling\Backups once a day.
  static Future<String> backup({bool force = false}) async {
    final dir = Directory(p.join(baseDir, 'Backups'));
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, 'billing_${todayStr()}.db'));
    if (force || !await target.exists()) {
      await File(dbPath).copy(target.path);
    }
    final files = (await dir.list().toList()).whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    while (files.length > 30) {
      await files.removeAt(0).delete();
    }
    return target.path;
  }
}
