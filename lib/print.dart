import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'db.dart';
import 'models.dart';
import 'util.dart';

/// Marker line: the hotel logo is printed here.
const String kLogoMark = '\u0001LOGO';

/// One line on a receipt.
class RLine {
  final String text;
  final int align; // 0 left, 1 center
  final bool bold;
  final bool big; // double size
  const RLine(this.text, {this.align = 0, this.bold = false, this.big = false});
}

class Receipts {
  // characters per line: 80 mm paper = 42, 58 mm paper = 32
  static int get cols {
    if (Db.s('paper_mm') == '58') return 32;
    final m = Db.s('printer_mode');
    return (m == 'usb' || m == 'network') ? 48 : 42; // real thermal printers fit 48
  }

  /// Font size that makes `cols` characters fill the paper width exactly.
  static double _fs() {
    // DejaVu Sans Mono: each character is 0.602 of the font size wide
    final w58 = Db.s('paper_mm') == '58';
    final avail = (w58 ? 58 : 80) * PdfPageFormat.mm - 2 * 3 * PdfPageFormat.mm;
    return ((avail / (cols * 0.604)) * 10).floor() / 10;
  }
  static String divider() => '-' * cols;

  static List<String> wrap(String s, int w) {
    final out = <String>[];
    var cur = '';
    for (var word in s.split(' ')) {
      while (word.length > w) {
        if (cur.isNotEmpty) {
          out.add(cur);
          cur = '';
        }
        out.add(word.substring(0, w));
        word = word.substring(w);
      }
      if (cur.isEmpty) {
        cur = word;
      } else if (cur.length + 1 + word.length <= w) {
        cur += ' $word';
      } else {
        out.add(cur);
        cur = word;
      }
    }
    if (cur.isNotEmpty) out.add(cur);
    return out.isEmpty ? [''] : out;
  }

  static String _lr(String l, String r, [int? width]) {
    final w = width ?? cols;
    final space = w - l.length - r.length;
    if (space < 1) return '$l $r';
    return l + ' ' * space + r;
  }

  // ---------- the final bill ----------
  static List<RLine> billLines(BillData b) {
    final L = <RLine>[];
    final bigW = cols ~/ 2;
    L.add(const RLine(kLogoMark, align: 1));
    for (final t in wrap(Db.s('hotel_name'), bigW)) {
      L.add(RLine(t, align: 1, bold: true, big: true));
    }
    for (final t in wrap(Db.s('address'), cols)) {
      L.add(RLine(t, align: 1));
    }
    if (Db.s('phone').isNotEmpty) L.add(RLine('Ph: ${Db.s('phone')}', align: 1));
    if (Db.s('gstin').isNotEmpty) {
      L.add(RLine('GSTIN: ${Db.s('gstin')}', align: 1));
    }
    L.add(RLine(divider()));
    L.add(RLine(_lr('Bill No: ${b.billNoText}', b.headline), bold: true));
    L.add(RLine('Date: ${fmtDateTime(b.createdAt)}'));
    L.add(RLine(divider()));

    final nameW = cols - 18;
    L.add(RLine('Item'.padRight(nameW) +
        'Qty'.padLeft(3) +
        'Rate'.padLeft(7) +
        'Amt'.padLeft(8)));
    L.add(RLine(divider()));
    for (final it in b.items) {
      final parts = wrap(it.name, nameW);
      for (var i = 0; i < parts.length; i++) {
        if (i < parts.length - 1) {
          L.add(RLine(parts[i]));
        } else {
          L.add(RLine(parts[i].padRight(nameW) +
              '${it.qty}'.padLeft(3) +
              money0(it.price).padLeft(7) +
              money(it.amount).padLeft(8)));
        }
      }
      if (it.note.isNotEmpty) {
        for (final t in wrap('  * ${it.note}', cols)) {
          L.add(RLine(t));
        }
      }
    }
    L.add(RLine(divider()));
    final totQty = b.items.fold<int>(0, (a, i) => a + i.qty);
    L.add(RLine('No Of Item/Qty: ${b.items.length}/$totQty'));
    L.add(RLine(_lr('Subtotal', money(b.subtotal))));
    if (b.discount > 0) {
      L.add(RLine(_lr('Discount', '-${money(b.discount)}')));
    }
    if (b.gstPct > 0) {
      final cgst = r2(b.gstAmt / 2);
      final sgst = r2(b.gstAmt - cgst);
      final half = pctText(b.gstPct / 2);
      L.add(RLine(_lr('CGST $half%', money(cgst))));
      L.add(RLine(_lr('SGST $half%', money(sgst))));
    }
    L.add(RLine('=' * cols));
    L.add(RLine(_lr('TOTAL', 'Rs.${money(b.total)}', cols ~/ 2),
        bold: true, big: true));
    L.add(RLine('=' * cols));
    if (b.payMode.isNotEmpty) L.add(RLine('Paid by: ${b.payMode}', align: 1, bold: true));
    L.add(const RLine(''));
    if (Db.s('footer').isNotEmpty) {
      for (final t in wrap(Db.s('footer'), cols)) {
        L.add(RLine(t, align: 1));
      }
    }
    return L;
  }

  // ---------- kitchen order slips ----------
  /// One slip per section when "split" is on, otherwise a single slip.
  static List<List<RLine>> kitchenSlips(List<CartLine> lines, String label, {int? kotNo}) {
    final split = Db.s('split_slips') == '1';
    final groups = <String, List<CartLine>>{};
    if (split) {
      for (final l in lines) {
        groups.putIfAbsent(l.dish.sectionName, () => []).add(l);
      }
    } else {
      groups[''] = lines;
    }
    final slips = <List<RLine>>[];
    final bigW = cols ~/ 2;
    for (final e in groups.entries) {
      final L = <RLine>[];
      L.add(const RLine('KOT', align: 1, bold: true));
      for (final t in wrap(Db.s('hotel_name'), bigW)) {
        L.add(RLine(t, align: 1, bold: true));
      }
      if (kotNo != null) {
        L.add(RLine('KOT No: ${kotNo.toString().padLeft(4, '0')}', bold: true, big: true));
      }
      L.add(RLine('Date: ${fmtDateTime(DateTime.now())}'));
      if (label.isNotEmpty) L.add(RLine('Counter: $label'));
      if (e.key.isNotEmpty) L.add(RLine('SubGroup: ${e.key.toUpperCase()}'));
      L.add(RLine(divider()));
      final nw = cols - 6;
      L.add(RLine('Food / Item'.padRight(nw) + 'Qty'.padLeft(6)));
      L.add(RLine(divider()));
      var n = 0;
      for (final l in e.value) {
        n += l.qty;
        final parts = wrap(l.dish.name, nw);
        for (var i = 0; i < parts.length; i++) {
          L.add(RLine(
              i < parts.length - 1
                  ? parts[i]
                  : parts[i].padRight(nw) + '${l.qty}'.padLeft(6),
              bold: true));
        }
        if (l.note.isNotEmpty) {
          for (final t in wrap('   * ${l.note}', cols)) {
            L.add(RLine(t));
          }
        }
      }
      L.add(RLine(divider()));
      L.add(RLine('No Of Item/Qty: ${e.value.length}/$n'));
      slips.add(L);
    }
    return slips;
  }

  /// KOT slip made from a finished bill (for hotels with no kitchen printer).
  static List<RLine> kotFromBill(BillData b) {
    final L = <RLine>[];
    final bigW = cols ~/ 2;
    L.add(const RLine('KOT', align: 1, bold: true));
    for (final t in wrap(Db.s('hotel_name'), bigW)) {
      L.add(RLine(t, align: 1, bold: true));
    }
    L.add(RLine('KOT No: ${b.billNoText}', bold: true, big: true));
    L.add(RLine('Date: ${fmtDateTime(b.createdAt)}'));
    L.add(RLine('Counter: ${b.headline}'));
    L.add(RLine(divider()));
    final nw = cols - 6;
    L.add(RLine('Food / Item'.padRight(nw) + 'Qty'.padLeft(6)));
    L.add(RLine(divider()));
    var n = 0;
    for (final it in b.items) {
      n += it.qty;
      final parts = wrap(it.name, nw);
      for (var i = 0; i < parts.length; i++) {
        L.add(RLine(
            i < parts.length - 1 ? parts[i] : parts[i].padRight(nw) + '${it.qty}'.padLeft(6),
            bold: true));
      }
      if (it.note.isNotEmpty) {
        for (final t in wrap('   * ${it.note}', cols)) {
          L.add(RLine(t));
        }
      }
    }
    L.add(RLine(divider()));
    L.add(RLine('No Of Item/Qty: ${b.items.length}/$n'));
    return L;
  }

  /// Prints the bill and, if switched on in Settings, the KOT slip right after it.
  static Future<String?> printBillAndKot(BillData b) async {
    var err = await printLines(billLines(b));
    if (err == null && Db.s('kot_with_bill') != '0') {
      err = await printLines(kotFromBill(b));
    }
    return err;
  }

  /// On a big sheet (Letter / A4) the bill is placed in the middle, receipt width.
  static pw.Widget _wrap(double? width, pw.Widget child) => width == null
      ? child
      : pw.Align(
          alignment: pw.Alignment.topCenter,
          child: pw.SizedBox(width: width, child: child));

  // ---------- PDF way (Windows printer, any driver) ----------
  static PdfPageFormat _format(List<RLine> lines) {
    final w58 = Db.s('paper_mm') == '58';
    final fs = _fs();
    final width = (w58 ? 58 : 80) * PdfPageFormat.mm;
    final margin = 3 * PdfPageFormat.mm;
    var h = 0.0;
    for (final l in lines) {
      h += l.text == kLogoMark ? 50.0 : fs * (l.big ? 2 : 1) * 1.3;
    }
    h += 2 * margin + 12 * PdfPageFormat.mm;
    return PdfPageFormat(width, h, marginAll: margin);
  }

  static Future<Uint8List> _toPdf(List<RLine> lines, PdfPageFormat fmt,
      {Uint8List? logoPng, PdfPageFormat? sheet}) async {
    final k = sheet == null ? 1.0 : 1.6; // bigger on a Letter / A4 sheet
    final fs = _fs() * k;
    final normal = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSansMono.ttf'));
    final boldF = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSansMono-Bold.ttf'));
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: sheet == null ? fmt : PdfPageFormat(sheet.width, sheet.height, marginAll: 12 * PdfPageFormat.mm),
      build: (ctx) => _wrap(sheet == null ? null : fmt.availableWidth * k, pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          for (final l in lines)
            if (l.text.length > 8 && RegExp(r'^-+$').hasMatch(l.text))
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Divider(
                      height: 3, thickness: 0.7, borderStyle: pw.BorderStyle.dashed))
            else if (l.text.length > 8 && RegExp(r'^=+$').hasMatch(l.text))
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Divider(height: 3, thickness: 1.6))
            else if (l.text == kLogoMark)
              (logoPng == null
                  ? pw.SizedBox()
                  : pw.Center(child: pw.Image(pw.MemoryImage(logoPng), height: 42 * k)))
            else
              pw.Text(
              l.text.isEmpty ? ' ' : l.text,
              softWrap: false,
              textAlign: l.align == 1 ? pw.TextAlign.center : pw.TextAlign.left,
              style: pw.TextStyle(
                font: l.bold ? boldF : normal,
                fontSize: fs * (l.big ? 2 : 1),
              ),
            ),
        ],
      )),
    ));
    return doc.save();
  }

  // ---------- ESC/POS way (network printer, raw) ----------
  static List<int> _escPos(List<RLine> lines, {List<int>? logo}) {
    final b = <int>[0x1B, 0x40]; // reset printer
    for (final l in lines) {
      if (l.text == kLogoMark) {
        if (logo != null) {
          b.addAll([0x1B, 0x61, 0x01]);
          b.addAll(logo);
          b.add(0x0A);
        }
        continue;
      }
      b.addAll([0x1B, 0x61, l.align]); // align
      b.addAll([0x1B, 0x45, l.bold ? 1 : 0]); // bold
      b.addAll([0x1D, 0x21, l.big ? 0x11 : 0x00]); // double size
      b.addAll(l.text.runes.map((r) => r < 128 ? r : 0x3F));
      b.add(0x0A);
    }
    b.addAll([0x1D, 0x21, 0x00, 0x1B, 0x45, 0x00, 0x1B, 0x61, 0x00]);
    b.addAll([0x1B, 0x64, 4]); // feed 4 lines
    b.addAll([0x1D, 0x56, 0x42, 0x00]); // cut
    return b;
  }

  // ---------- logo for ESC/POS printers ----------
  static Future<List<int>?> _logoRaster(Uint8List png) async {
    try {
      final w = Db.s('paper_mm') == '58' ? 144 : 200;
      final codec = await ui.instantiateImageCodec(png, targetWidth: w);
      final fr = await codec.getNextFrame();
      final img = fr.image;
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) return null;
      final px = bd.buffer.asUint8List();
      final ww = img.width, h = img.height, wb = (ww + 7) ~/ 8;
      final out = <int>[0x1D, 0x76, 0x30, 0x00, wb & 0xFF, (wb >> 8) & 0xFF, h & 0xFF, (h >> 8) & 0xFF];
      for (var y = 0; y < h; y++) {
        for (var xb = 0; xb < wb; xb++) {
          var byte = 0;
          for (var bit = 0; bit < 8; bit++) {
            final x = xb * 8 + bit;
            if (x >= ww) continue;
            final i = (y * ww + x) * 4;
            final a = px[i + 3] / 255.0;
            final luma = (0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2]) * a + 255 * (1 - a);
            if (luma < 190) byte |= 0x80 >> bit;
          }
          out.add(byte);
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  // ---------- USB printer (Android) ----------
  static const MethodChannel _usb = MethodChannel('hotel/usb_printer');

  /// Plain text list of USB printers the phone can see.
  static Future<String> usbCheck() async {
    try {
      final r = await _usb.invokeMethod<List<dynamic>>('list');
      if (r == null || r.isEmpty) {
        return 'No USB printer found. Check the OTG cable and that the printer is ON.';
      }
      return 'USB printer found: ${r.map((e) => e['name']).join(', ')}';
    } catch (e) {
      return 'USB check problem: $e';
    }
  }

  // ---------- send to the printer ----------
  /// Returns null when OK, or a plain message when something is wrong.
  static Future<String?> printLines(List<RLine> lines) async {
    final mode = Db.s('printer_mode');
    Uint8List? logoPng;
    if (lines.any((l) => l.text == kLogoMark)) {
      try {
        logoPng = (await rootBundle.load('assets/logo_icon.png')).buffer.asUint8List();
      } catch (_) {}
    }
    try {
      if (Platform.isAndroid && mode == 'usb') {
        final logo = logoPng == null ? null : await _logoRaster(logoPng);
        await _usb.invokeMethod('print', {'bytes': Uint8List.fromList(_escPos(lines, logo: logo))});
        return null;
      }
      // Android: use the phone's own print dialog (Wi-Fi / Bluetooth / PDF),
      // unless a network (IP) printer is set. Direct printer setup comes later.
      if (Platform.isAndroid && mode != 'network') {
        final fmt = _format(lines);
        final bytes = await _toPdf(lines, fmt, logoPng: logoPng);
        final ok = await Printing.layoutPdf(
          // if the dialog picks a big sheet (Letter / A4), centre the bill on it
          onLayout: (f) async => f.width > fmt.width * 1.4
              ? await _toPdf(lines, fmt, logoPng: logoPng, sheet: f)
              : bytes,
          name: 'Hotel bill',
          format: fmt,
        );
        return ok ? null : 'Print was cancelled.';
      }
      if (mode == 'windows') {
        final name = Db.s('printer_name');
        if (name.isEmpty) return 'Printer not chosen. Open Settings and pick the printer.';
        final printers = await Printing.listPrinters();
        final match = printers.where((p) => p.name == name).toList();
        if (match.isEmpty) {
          return 'Printer "$name" not found. Check it is ON and connected.';
        }
        final fmt = _format(lines);
        final bytes = await _toPdf(lines, fmt, logoPng: logoPng);
        final ok = await Printing.directPrintPdf(
          printer: match.first,
          onLayout: (_) async => bytes,
          name: 'Hotel bill',
          format: fmt,
        );
        return ok ? null : 'The printer did not accept the print.';
      }
      if (mode == 'network') {
        final ip = Db.s('printer_ip');
        final port = int.tryParse(Db.s('printer_port')) ?? 9100;
        if (ip.isEmpty) return 'Printer IP is empty. Open Settings.';
        final sock =
            await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
        final logo = logoPng == null ? null : await _logoRaster(logoPng);
        sock.add(Uint8List.fromList(_escPos(lines, logo: logo)));
        await sock.flush();
        await sock.close();
        return null;
      }
      return 'Printer is not set up yet. Open Settings.';
    } on PlatformException catch (e) {
      return e.message ?? 'USB print problem';
    } catch (e) {
      return 'Print problem: $e';
    }
  }

  static Future<String?> testPrint() {
    final L = <RLine>[
      RLine(Db.s('hotel_name'), align: 1, bold: true, big: true),
      const RLine('TEST PRINT', align: 1, bold: true),
      RLine(divider()),
      const RLine('If you can read this, the'),
      const RLine('printer is working.'),
      RLine(divider()),
      RLine('Item'.padRight(cols - 18) +
          'Qty'.padLeft(3) +
          'Rate'.padLeft(7) +
          'Amt'.padLeft(8)),
      RLine('Masala Dosa'.padRight(cols - 18) +
          '2'.padLeft(3) +
          '70'.padLeft(7) +
          '140.00'.padLeft(8)),
      RLine(divider()),
      RLine(fmtDateTime(DateTime.now()), align: 1),
    ];
    return printLines(L);
  }
}
