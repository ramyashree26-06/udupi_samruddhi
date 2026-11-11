import 'package:flutter/foundation.dart';
import 'util.dart';

class Section {
  final int id;
  final String name;
  Section(this.id, this.name);
  factory Section.fromMap(Map<String, Object?> m) =>
      Section(m['id'] as int, m['name'] as String);
}

class Dish {
  final int id;
  final int sectionId;
  final String sectionName;
  final String group;
  final String name;
  final double price;
  final bool closedToday;
  final String photo; // own picture (file path), '' = built-in picture
  Dish({
    required this.id,
    required this.sectionId,
    required this.sectionName,
    required this.group,
    required this.name,
    required this.price,
    required this.closedToday,
    this.photo = '',
  });
  factory Dish.fromMap(Map<String, Object?> m, String today) => Dish(
        id: m['id'] as int,
        sectionId: m['section_id'] as int,
        sectionName: (m['section_name'] ?? '') as String,
        group: (m['grp'] ?? '') as String,
        name: m['name'] as String,
        price: (m['price'] as num).toDouble(),
        closedToday: m['closed_date'] == today,
        photo: (m['photo'] ?? '') as String,
      );
}

class CartLine {
  final Dish dish;
  int qty;
  String note;
  CartLine(this.dish, this.qty, {this.note = ''});
  double get amount => dish.price * qty;
}

/// The order being made right now. One order, many sections.
class Cart extends ChangeNotifier {
  final Map<int, CartLine> _m = {};
  double discount = 0; // extra discount in Rs.
  String orderType = 'Dine In'; // Dine In | Parcel
  String label = ''; // table or token number text
  int? draftId; // set when a saved draft is opened
  int? customerId;
  String customerName = '';

  List<CartLine> get list => _m.values.toList();
  bool get isEmpty => _m.isEmpty;
  int get count => _m.values.fold<int>(0, (a, l) => a + l.qty);
  double get subtotal =>
      r2(_m.values.fold<double>(0.0, (a, l) => a + l.amount));
  int qtyOf(int dishId) => _m[dishId]?.qty ?? 0;

  void add(Dish d, {int qty = 1, String note = ''}) {
    final l = _m[d.id];
    if (l == null) {
      _m[d.id] = CartLine(d, qty, note: note);
    } else {
      l.qty += qty;
    }
    notifyListeners();
  }

  void dec(int id) {
    final l = _m[id];
    if (l == null) return;
    l.qty--;
    if (l.qty <= 0) _m.remove(id);
    notifyListeners();
  }

  void remove(int id) {
    _m.remove(id);
    notifyListeners();
  }

  void setNote(int id, String note) {
    final l = _m[id];
    if (l == null) return;
    l.note = note;
    notifyListeners();
  }

  void setDiscount(double v) {
    discount = v < 0 ? 0 : v;
    notifyListeners();
  }

  void setOrderType(String t) {
    orderType = t;
    notifyListeners();
  }

  void setLabel(String t) {
    label = t;
    // no notify: the text box already shows it
  }

  void clear() {
    _m.clear();
    discount = 0;
    draftId = null;
    customerId = null;
    customerName = '';
    label = '';
    notifyListeners();
  }
}

final Cart cart = Cart();

class BillItem {
  final String name;
  final int qty;
  final double price;
  final double amount;
  final String note;
  BillItem(this.name, this.qty, this.price, this.amount, [this.note = '']);
}

class BillData {
  final int id;
  final int billNo;
  final DateTime createdAt;
  final String label;
  final String orderType;
  final String payMode;
  final String status;
  final double subtotal;
  final double discount;
  final double gstPct;
  final double gstAmt;
  final double total;
  final List<BillItem> items;
  BillData({
    required this.id,
    required this.billNo,
    required this.createdAt,
    required this.label,
    required this.orderType,
    required this.payMode,
    required this.status,
    required this.subtotal,
    required this.discount,
    required this.gstPct,
    required this.gstAmt,
    required this.total,
    required this.items,
  });
  String get billNoText => 'B-${billNo.toString().padLeft(4, '0')}';
  /// Text shown under the bill number, like "Dine In - Table: 4".
  String get headline {
    if (label.isEmpty) return orderType;
    return '$orderType - $label';
  }
}

/// A row in the Bills list.
class BillRow {
  final int id;
  final int billNo;
  final String status;
  final DateTime createdAt;
  final String label;
  final String orderType;
  final String payMode;
  final double total;
  final String kstatus; // '', new, preparing, ready, done
  BillRow(this.id, this.billNo, this.status, this.createdAt, this.label,
      this.orderType, this.payMode, this.total, [this.kstatus = '']);

  /// Words shown in the Orders list.
  String get statusText {
    if (status == 'void') return 'Cancelled';
    if (kstatus == 'new' || kstatus == 'preparing') return 'Preparing';
    if (kstatus == 'ready') return 'Ready';
    if (status == 'draft') return 'Open';
    return 'Completed';
  }
  String get billNoText =>
      status == 'draft' ? 'Draft' : 'B-${billNo.toString().padLeft(4, '0')}';
}
