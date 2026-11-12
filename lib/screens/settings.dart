import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as pth;
import 'package:printing/printing.dart';

import '../db.dart';
import '../dialogs.dart';
import '../print.dart';
import '../theme.dart';
import '../util.dart';
import '../watermark.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final name = TextEditingController(text: Db.s('hotel_name'));
  final address = TextEditingController(text: Db.s('address'));
  final phone = TextEditingController(text: Db.s('phone'));
  final gstin = TextEditingController(text: Db.s('gstin'));
  final gstPct = TextEditingController(text: Db.s('gst_pct'));
  final tables = TextEditingController(text: Db.s('tables'));
  final priceStep = TextEditingController(text: Db.s('price_step'));
  final footer = TextEditingController(text: Db.s('footer'));
  final printerName = TextEditingController(text: Db.s('printer_name'));
  final printerIp = TextEditingController(text: Db.s('printer_ip'));
  final printerPort = TextEditingController(text: Db.s('printer_port'));
  final printerModel = TextEditingController(text: Db.s('printer_model'));
  double logoOpacity = Db.d('logo_opacity') > 0 ? Db.d('logo_opacity') : 0.10;
  String orderMode = Db.s('order_mode');
  String printerMode = Db.s('printer_mode');
  String paper = Db.s('paper_mm');
  bool split = Db.s('split_slips') == '1';
  bool kotWithBill = Db.s('kot_with_bill') != '0';
  int sec = 0;
  late final currency = TextEditingController(text: Db.s('currency'));

  @override
  void dispose() {
    for (final c in [name, address, phone, gstin, gstPct, tables, priceStep, footer, printerName, printerIp, printerPort, printerModel, currency]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    await Db.setS('hotel_name', name.text.trim());
    await Db.setS('address', address.text.trim());
    await Db.setS('phone', phone.text.trim());
    await Db.setS('gstin', gstin.text.trim());
    await Db.setS('gst_pct', (double.tryParse(gstPct.text.trim()) ?? 0).toString());
    await Db.setS('footer', footer.text.trim());
    await Db.setS('tables', (int.tryParse(tables.text.trim()) ?? 10).toString());
    await Db.setS('price_step', (double.tryParse(priceStep.text.trim()) ?? 5).toString());
    await Db.setS('order_mode', orderMode);
    await Db.setS('split_slips', split ? '1' : '0');
    await Db.setS('kot_with_bill', kotWithBill ? '1' : '0');
    await Db.setS('printer_mode', printerMode);
    await Db.setS('printer_name', printerName.text.trim());
    await Db.setS('printer_ip', printerIp.text.trim());
    await Db.setS('printer_port', printerPort.text.trim().isEmpty ? '9100' : printerPort.text.trim());
    await Db.setS('paper_mm', paper);
    await Db.setS('printer_model', printerModel.text.trim());
    await Db.setS('logo_opacity', logoOpacity.toStringAsFixed(2));
    await Db.setS('currency', currency.text.trim().isEmpty ? 'INR (Rs)' : currency.text.trim());
  }

  Future<void> _saveClicked() async {
    await _save();
    if (!mounted) return;
    snack(context, 'Settings saved');
  }

  Future<void> _choosePrinter() async {
    if (isAndroid) {
      snack(context,
          'On Android the bill opens the phone\'s print dialog. For a receipt printer, type its IP below.');
      return;
    }
    List<Printer> list;
    try {
      list = await Printing.listPrinters();
    } catch (e) {
      if (!mounted) return;
      snack(context, 'Could not read printers: $e');
      return;
    }
    if (!mounted) return;
    if (list.isEmpty) {
      snack(context, 'No printers found in Windows. Install the printer driver first.');
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose printer'),
        children: [
          for (final p in list)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p.name),
              child: Text(p.name),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => printerName.text = picked);
  }

  Future<void> _test() async {
    await _save();
    final err = await Receipts.testPrint();
    if (!mounted) return;
    snack(context, err ?? 'Test slip sent to printer');
  }

  Future<void> _backupNow() async {
    final path = await Db.backup(force: true);
    if (!mounted) return;
    snack(context, 'Backup saved: $path');
  }

  Future<void> _openDataFolder() async {
    final opened = await openFolder(Db.baseDir);
    if (!opened && mounted) snack(context, 'Data is kept inside the app: ${Db.baseDir}');
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      );

  Widget _field(TextEditingController c, String label, {int lines = 1, double? width}) {
    final f = TextField(
      controller: c,
      maxLines: lines,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12.5),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: const OutlineInputBorder(),
      ),
    );
    return width == null ? f : SizedBox(width: width, child: f);
  }

  static const _secs = <String>['General', 'Billing', 'Printer', 'Taxes & GST', 'Appearance'];
  static const _icons = <IconData>[Icons.tune, Icons.receipt_long, Icons.print, Icons.percent, Icons.palette_outlined];

  Widget _saveRow() => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Wrap(spacing: 10, runSpacing: 8, children: [
          FilledButton(onPressed: _saveClicked, child: const Text('Save settings')),
          if (sec == 2)
            OutlinedButton.icon(
                onPressed: _test,
                icon: const Icon(Icons.print),
                label: const Text('Print test slip')),
        ]),
      );

  List<Widget> _general() => [
        _title('Hotel details (printed on the bill)'),
        _field(name, 'Hotel name'),
        const SizedBox(height: 10),
        _field(address, 'Address', lines: 2),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _field(phone, 'Phone')),
          const SizedBox(width: 10),
          Expanded(child: _field(currency, 'Currency')),
        ]),
        _title('Data'),
        Wrap(spacing: 10, runSpacing: 8, children: [
          OutlinedButton(onPressed: _backupNow, child: const Text('Backup now')),
          if (!isAndroid)
            OutlinedButton(onPressed: _openDataFolder, child: const Text('Open data folder')),
        ]),
        const SizedBox(height: 6),
        const Text('Auto backup time is set in the Backup & Restore tab.',
            style: TextStyle(fontSize: 12)),
      ];

  List<Widget> _billing() => [
        _title('Table or token'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'table', label: Text('Table No.')),
            ButtonSegment(value: 'token', label: Text('Token No.')),
            ButtonSegment(value: 'none', label: Text('None')),
          ],
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5)),
          ),
          selected: {orderMode},
          onSelectionChanged: (s) => setState(() => orderMode = s.first),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _field(priceStep, 'Menu +/- price step (Rs.)')),
        ]),
        const SizedBox(height: 10),
        _field(footer, 'Bill bottom line'),
        _title('Kitchen slips'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Print a separate slip for each section', style: TextStyle(fontSize: 13)),
          subtitle: const Text('Off = one slip with all items', style: TextStyle(fontSize: 11.5)),
          value: split,
          onChanged: (v) => setState(() => split = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Print KOT slip with every bill', style: TextStyle(fontSize: 13)),
          subtitle: const Text('For hotels with no kitchen printer', style: TextStyle(fontSize: 11.5)),
          value: kotWithBill,
          onChanged: (v) => setState(() => kotWithBill = v),
        ),
      ];

  List<Widget> _printer() {
    final pm = isAndroid && printerMode == 'windows' ? 'none' : printerMode;
    final phone = isNarrow(context);
    return [
        _title('Printer'),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
                value: 'none', label: Text(isAndroid ? 'Phone dialog' : 'Not set')),
            if (!isAndroid)
              const ButtonSegment(value: 'windows', label: Text('USB / Windows printer')),
            if (isAndroid)
              const ButtonSegment(value: 'usb', label: Text('USB printer')),
            const ButtonSegment(value: 'network', label: Text('Wi-Fi / LAN')),
          ],
          selected: {pm},
          onSelectionChanged: (s) => setState(() => printerMode = s.first),
        ),
        const SizedBox(height: 12),
        if (pm == 'windows')
          Row(children: [
            Expanded(child: _field(printerName, 'Printer name (as in Windows)')),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: _choosePrinter, child: const Text('Choose')),
          ]),
        if (pm == 'usb')
          Row(children: [
            const Expanded(
                child: Text('Plug the printer in with an OTG cable, then tap Check. Allow the USB permission when Android asks.')),
            const SizedBox(width: 10),
            OutlinedButton(
                onPressed: () async {
                  final m = await Receipts.usbCheck();
                  if (mounted) snack(context, m);
                },
                child: const Text('Check')),
          ]),
        if (pm == 'network')
          Row(children: [
            Expanded(flex: 2, child: _field(printerIp, phone ? 'Printer IP' : 'Printer IP (e.g. 192.168.1.50)')),
            const SizedBox(width: 10),
            Expanded(child: _field(printerPort, 'Port')),
          ]),
        const SizedBox(height: 12),
        _field(printerModel, phone ? 'Printer brand / model (note)' : 'Printer brand and model (only a note for you)'),
        const SizedBox(height: 12),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
          const Text('Paper width:'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '80', label: Text('80 mm')),
              ButtonSegment(value: '58', label: Text('58 mm')),
            ],
            selected: {paper},
            onSelectionChanged: (s) => setState(() => paper = s.first),
          ),
        ]),
    ];
  }

  List<Widget> _tax() => [
        _title('Taxes & GST'),
        Row(children: [
          Expanded(child: _field(gstPct, isNarrow(context) ? 'GST %' : 'GST % (total, split into CGST + SGST)')),
          const SizedBox(width: 10),
          Expanded(child: _field(gstin, 'GSTIN')),
        ]),
        const SizedBox(height: 8),
        const Text('Restaurant service code (HSN/SAC) used in GST reports: 996331'),
      ];

  List<Widget> _look() => [
        _title('Logo watermark (shown faintly on every tab)'),
        Row(children: [
          const Text('Strength  '),
          Expanded(
            child: Slider(
              value: logoOpacity.clamp(0.03, 0.30).toDouble(),
              min: 0.03,
              max: 0.30,
              onChanged: (v) {
                setState(() => logoOpacity = v);
                Db.cfg['logo_opacity'] = v.toStringAsFixed(2);
                Branding.tick.value++;
              },
              onChangeEnd: (v) => Db.setS('logo_opacity', v.toStringAsFixed(2)),
            ),
          ),
        ]),
        const Text('The Udupi Samruddhi logo is shown faintly behind every tab.'),
      ];

  @override
  Widget build(BuildContext context) {
    final content = switch (sec) {
      0 => _general(),
      1 => _billing(),
      2 => _printer(),
      3 => _tax(),
      _ => _look(),
    };
    if (isNarrow(context)) {
      // Phone: sections as a row of chips on top, the form below.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              children: [
                for (var i = 0; i < _secs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: phoneChip(_secs[i], sec == i,
                        () => setState(() => sec = i),
                        icon: _icons[i]),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
              children: [
                Box(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: content,
                  ),
                ),
                _saveRow(),
              ],
            ),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 210,
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kLine),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _secs.length; i++)
                ListTile(
                  dense: true,
                  selected: sec == i,
                  selectedColor: kOrange,
                  selectedTileColor: kSoft,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: Icon(_icons[i], size: 20),
                  title: Text(_secs[i], style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => setState(() => sec = i),
                ),
            ],
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 20, 20, 20),
                children: [
                  const Text('Settings', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  ...content,
                  _saveRow(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
