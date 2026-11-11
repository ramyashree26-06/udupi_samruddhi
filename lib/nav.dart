import 'dart:io';

import 'package:flutter/material.dart';

import 'db2.dart';

/// Which page is open: the position in [Db2.allModules]
/// 0 Dashboard, 1 POS, 2 Tables, 3 Orders, 4 Kitchen, 5 Menu, 6 Inventory,
/// 7 Purchases, 8 Suppliers, 9 Expenses, 10 Staff, 11 Sales,
/// 12 GST, 13 Settings, 14 Permissions, 15 Backup
final ValueNotifier<int> navIndex = ValueNotifier<int>(1);

/// Pages the signed-in person may open.
final ValueNotifier<Set<String>> allowed =
    ValueNotifier<Set<String>>(Db2.allModules.toSet());

/// Pages not shown. Inventory stays on Windows only for now. Kitchen screen is
/// hidden because the hotel has no kitchen display (the KOT prints with the bill).
final Set<String> hiddenModules =
    Platform.isAndroid ? <String>{'inventory', 'kitchen'} : <String>{'kitchen'};

/// True when the app is asking for a PIN.
final ValueNotifier<bool> locked = ValueNotifier<bool>(false);

/// True when at least one staff PIN exists (then a lock button shows).
final ValueNotifier<bool> pinOn = ValueNotifier<bool>(false);

class ModuleInfo {
  final String title;
  final String menu;
  final IconData icon;
  const ModuleInfo(this.title, this.menu, this.icon);
}

const Map<String, ModuleInfo> kModuleInfo = {
  'dashboard': ModuleInfo('Dashboard', 'Dashboard', Icons.dashboard_outlined),
  'pos': ModuleInfo('POS Billing', 'POS Billing', Icons.point_of_sale_outlined),
  'tables': ModuleInfo('Table Management', 'Tables', Icons.table_restaurant_outlined),
  'orders': ModuleInfo('Orders & Bills', 'Orders', Icons.receipt_long_outlined),
  'kitchen': ModuleInfo('Kitchen Display (KOT)', 'Kitchen (KOT)', Icons.soup_kitchen_outlined),
  'menu': ModuleInfo('Menu Management', 'Menu', Icons.restaurant_menu_outlined),
  'inventory': ModuleInfo('Inventory & Stock', 'Inventory', Icons.inventory_2_outlined),
  'purchase': ModuleInfo('Purchase Management', 'Purchases', Icons.shopping_cart_outlined),
  'suppliers': ModuleInfo('Suppliers', 'Suppliers', Icons.local_shipping_outlined),
  'expenses': ModuleInfo('Expenses', 'Expenses', Icons.payments_outlined),
  'staff': ModuleInfo('Staff & Users', 'Staff', Icons.badge_outlined),
  'sales': ModuleInfo('Sales Reports', 'Sales Reports', Icons.bar_chart_outlined),
  'gst': ModuleInfo('GST Reports', 'GST Reports', Icons.request_quote_outlined),
  'settings': ModuleInfo('Settings', 'Settings', Icons.settings_outlined),
  'permissions': ModuleInfo('User Permissions', 'Permissions', Icons.admin_panel_settings_outlined),
  'backup': ModuleInfo('Backup & Restore', 'Backup', Icons.backup_outlined),
};

String keyAt(int i) => Db2.allModules[i];
