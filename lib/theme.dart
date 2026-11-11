import 'package:flutter/material.dart';

const Color kOrange = Color(0xFFF26A12);
const Color kInk = Color(0xFF14161F);
const Color kMuted = Color(0xFF7B7F8C);
const Color kBg = Colors.white;
const Color kSoft = Color(0xFFF7F7F8);
const Color kLine = Color(0xFFE7E8EC);
const Color kGreen = Color(0xFF17A34A);
const Color kRed = Color(0xFFE5383B);
const Color kBrown = Color(0xFF5A2D12);
// Phone look (cream page, warm borders)
const Color kCream = Color(0xFFFFF8F1);
const Color kWarmLine = Color(0xFFF0DFCF);
const Color kTan = Color(0xFFE9CDB0);

/// [phone] = the warmer, rounder look used on phones and small tablets.
ThemeData buildTheme({bool phone = false}) {
  final r = phone ? 14.0 : 8.0;
  final line = phone ? kTan : kLine;
  final scheme = ColorScheme.fromSeed(
    seedColor: kOrange,
    primary: kOrange,
    brightness: Brightness.light,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: phone ? kCream : Colors.white,
    fontFamily: phone ? null : 'Segoe UI',
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(phone ? 20 : 12)),
    ),
    dividerColor: kLine,
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kLine),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: const BorderSide(color: kOrange, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
      ),
    ),
  );
}
