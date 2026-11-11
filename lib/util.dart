import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

final DateFormat _dayFmt = DateFormat('yyyy-MM-dd');
final DateFormat _dtFmt = DateFormat('dd-MM-yyyy hh:mm a');
final DateFormat _dFmt = DateFormat('dd-MM-yyyy');
final DateFormat _tFmt = DateFormat('hh:mm a');

String dayStr(DateTime d) => _dayFmt.format(d);
String todayStr() => dayStr(DateTime.now());
String fmtDateTime(DateTime d) => _dtFmt.format(d);
String fmtTime(DateTime d) => _tFmt.format(d);
String fmtDay(String yyyyMMdd) => _dFmt.format(DateTime.parse(yyyyMMdd));

double r2(double v) => (v * 100).roundToDouble() / 100;
String money(double v) => v.toStringAsFixed(2);
String money0(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
String pctText(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// A small picture for each kind of dish (until real photos are added).
String emojiFor(String group, String section) {
  switch (group) {
    case 'Tiffin & Breakfast':
      return '🥣';
    case 'Dosa & South Rotis':
      return '🥞';
    case 'Meals':
    case 'Meals & Combos':
      return '🍛';
    case 'Indian Breads':
      return '🫓';
    case 'Gravy & Curries':
      return '🍲';
    case 'Rice & Biryani':
    case 'Fried Rice':
      return '🍚';
    case 'Starters':
      return '🥦';
    case 'Noodles':
      return '🍜';
    case 'Soups':
      return '🥣';
    case 'Chats':
      return '🥙';
    case 'Sandwiches & Snacks':
      return '🥪';
    case 'Fresh Juices & Soda':
      return '🍹';
    case 'Tea, Coffee & Milk':
      return '☕';
    case 'Milkshakes':
      return '🥤';
    case 'Ice Cream':
      return '🍨';
    case 'Desserts':
      return '🍮';
  }
  switch (section) {
    case 'South Meals':
      return '🥞';
    case 'North Meals':
      return '🍛';
    case 'Chinese':
      return '🍜';
    case 'Chats':
      return '🥙';
    case 'Juices':
      return '🍹';
  }
  return '🍽️';
}

// ---------- platform helpers (Windows desktop and Android) ----------
/// True on a phone or small tablet (screen narrower than 1000).
bool isNarrow(BuildContext c) => MediaQuery.of(c).size.width < 1000;

bool get isAndroid => Platform.isAndroid;
bool get isWindows => Platform.isWindows;

/// Opens a folder in Windows Explorer. Returns false on Android
/// (there files live inside the app; use [shareFile] to send them out).
Future<bool> openFolder(String path) async {
  if (!Platform.isWindows) return false;
  try {
    await Process.run('explorer', [path]);
  } catch (_) {}
  return true;
}

/// Android: opens the share sheet so a file can be sent to WhatsApp,
/// Google Drive, e-mail, or saved to the phone.
Future<void> shareFile(String path) async {
  await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
}
