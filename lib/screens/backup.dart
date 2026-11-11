import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../daily_report.dart';
import '../db.dart';
import '../db2.dart';
import '../dialogs.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<File> files = [];
  late bool auto = Db.s('auto_backup') == '1';
  late final timeCtrl = TextEditingController(text: Db.s('backup_time'));
  DateTime repDay = DateTime.now();
  late bool mailOn = Db.s('mail_enabled') == '1';
  final mailCtrl = {
    for (final k in ['mail_to', 'mail_from', 'mail_host', 'mail_port', 'mail_user', 'mail_time'])
      k: TextEditingController(text: Db.s(k))
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    timeCtrl.dispose();
    for (final c in mailCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final f = await Db2.backupFiles();
    if (mounted) setState(() => files = f);
  }

  Future<void> _create() async {
    final path = await Db.backup(force: true);
    await _load();
    if (!mounted) return;
    snack(context, 'Backup saved: $path');
  }

  Future<void> _pickRepDay() async {
    final d = await showDatePicker(
        context: context,
        initialDate: repDay,
        firstDate: DateTime(2020),
        lastDate: DateTime.now());
    if (d != null) setState(() => repDay = d);
  }

  /// Closing report: PDF of the day + fresh data backup.
  Future<void> _closeDay() async {
    try {
      final r = await DayReport.load(dayStr(repDay));
      final path = await r.savePdf();
      await Db.backup(force: true);
      await _load();
      if (!mounted) return;
      snack(context, isAndroid ? 'Report ready. Choose where to send it.' : 'Report saved: $path');
      if (isAndroid) await shareFile(path);
    } catch (e) {
      if (!mounted) return;
      snack(context, 'Could not make report: $e');
    }
  }

  Future<void> _saveMail() async {
    final to = mailCtrl['mail_to']!.text.trim();
    if (mailOn && to.isEmpty) {
      snack(context, 'Type the admin e-mail first');
      return;
    }
    final t = mailCtrl['mail_time']!.text.trim();
    if (!RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(t)) {
      snack(context, 'Type the time like 23:30');
      return;
    }
    for (final e in mailCtrl.entries) {
      await Db.setS(e.key, e.value.text.trim());
    }
    await Db.setS('mail_enabled', mailOn ? '1' : '0');
    if (!mounted) return;
    snack(context, 'Saved. (E-mail sending is not active yet)');
  }

  Widget _mailField(String key, String label, {double? width}) => SizedBox(
        width: width ?? 260,
        child: TextField(
          controller: mailCtrl[key],
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  Future<void> _restore(File f) async {
    final ok = await confirmBox(context, 'Restore backup',
        'Replace all current data with ${p.basename(f.path)}?\nToday\'s data is saved first as before_restore.db.');
    if (!ok) return;
    try {
      await Db2.restore(f);
      if (!mounted) return;
      snack(context, 'Restored. Please close and open the app once.');
    } catch (e) {
      if (!mounted) return;
      snack(context, 'Could not restore: $e');
    }
  }

  Future<void> _saveAuto() async {
    var t = timeCtrl.text.trim();
    final ok = RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(t);
    if (!ok) {
      snack(context, 'Type the time like 23:00');
      return;
    }
    if (t.length == 4) t = '0$t';
    await Db.setS('auto_backup', auto ? '1' : '0');
    await Db.setS('backup_time', t);
    if (!mounted) return;
    snack(context, 'Saved');
  }

  Widget _tile(IconData ic, String title, String sub, Widget action) {
    final small = isNarrow(context);
    final box = Box(
      padding: EdgeInsets.all(small ? 12 : 16),
      child: small
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(ic, size: 26, color: kOrange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(sub, style: const TextStyle(color: kMuted, fontSize: 12.5)),
                const SizedBox(height: 8),
                action,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(ic, size: 34, color: kOrange),
                const SizedBox(height: 10),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(sub, style: const TextStyle(color: kMuted)),
                const SizedBox(height: 14),
                action,
              ],
            ),
    );
    return small ? box : Expanded(child: box);
  }

  @override
  Widget build(BuildContext context) {
    final small = isNarrow(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(small ? 10 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHead('Backup & Restore'),
          Flex(
            direction: small ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: small ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
            children: [
              _tile(Icons.storage_outlined, 'Create Backup', 'Take a copy of all data now',
                  orangeButton('Create Backup', _create, icon: Icons.save_alt)),
              small ? const SizedBox(height: 8) : const SizedBox(width: 14),
              _tile(
                Icons.autorenew,
                'Auto Backup',
                'Daily backup while the app is open',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
                      const Text('Time (24 hour): '),
                      SizedBox(
                        width: 90,
                        child: TextField(controller: timeCtrl),
                      ),
                      Switch(value: auto, onChanged: (v) => setState(() => auto = v)),
                    ]),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: _saveAuto, child: const Text('Save')),
                  ],
                ),
              ),
              small ? const SizedBox(height: 8) : const SizedBox(width: 14),
              _tile(
                Icons.folder_open,
                'Backup folder',
                isAndroid
                    ? 'Last 30 days are kept inside the app. Use Share to keep a copy outside the phone.'
                    : 'Last 30 days are kept in Documents\\HotelBilling\\Backups',
                OutlinedButton(
                  onPressed: () async {
                    final opened = await openFolder(p.join(Db.baseDir, 'Backups'));
                    if (!opened && mounted) {
                      snack(context, 'Backups are inside the app. Use Share next to a backup to save a copy outside the phone.');
                    }
                  },
                  child: Text(isAndroid ? 'Where are backups?' : 'Open folder'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Box(
            padding: EdgeInsets.all(small ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Daily closing report',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text(
                    'One PDF with sales, payment modes, purchases, expenses and profit. A data backup is also saved.',
                    style: TextStyle(color: kMuted, fontSize: 12.5)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: _pickRepDay,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(fmtDay(dayStr(repDay))),
                  ),
                  orangeButton('Close day & make report', _closeDay, icon: Icons.summarize_outlined),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Box(
            padding: EdgeInsets.all(small ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(
                    child: Text('E-mail the daily report to admin',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                  Switch(value: mailOn, onChanged: (v) => setState(() => mailOn = v)),
                ]),
                const Text(
                    'NOT ACTIVE YET. These details are only saved for later; nothing is sent. The mail password is not saved here.',
                    style: TextStyle(color: kMuted, fontSize: 12.5)),
                const SizedBox(height: 8),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  _mailField('mail_to', 'Admin e-mail (to)'),
                  _mailField('mail_from', 'Sender e-mail (from)'),
                  _mailField('mail_host', 'Mail server (SMTP host)'),
                  _mailField('mail_port', 'Port', width: 100),
                  _mailField('mail_user', 'Mail user name'),
                  _mailField('mail_time', 'Send at (24 hour)', width: 130),
                ]),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _saveMail, child: const Text('Save mail details')),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('Restore from a backup',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Box(
            padding: EdgeInsets.zero,
            child: files.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No backups yet', style: TextStyle(color: kMuted)),
                  )
                : Column(
                    children: [
                      for (final f in files.take(30))
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: small ? 10 : 14, vertical: 4),
                          decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: kLine))),
                          child: Row(children: [
                            Expanded(
                                child: Text(p.basename(f.path),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: small ? 12.5 : null))),
                            Text('${(f.lengthSync() / 1024).round()} KB',
                                style: const TextStyle(color: kMuted, fontSize: 12)),
                            SizedBox(width: small ? 6 : 12),
                            if (isAndroid) ...[
                              OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      visualDensity: VisualDensity.compact),
                                  onPressed: () => shareFile(f.path),
                                  child: const Text('Share')),
                              const SizedBox(width: 6),
                            ],
                            OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    visualDensity: VisualDensity.compact),
                                onPressed: () => _restore(f), child: const Text('Restore')),
                          ]),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
