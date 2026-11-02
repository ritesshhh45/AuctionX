import 'dart:typed_data';
import 'package:excel/excel.dart' show Excel, IntCellValue, TextCellValue;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'core.dart';

String _sheet(Object? n, int i) {
  final s = '$n'.replaceAll(RegExp(r'[\\/*?:\[\]]'), '_');
  return '${i + 1}-${s.length > 26 ? s.substring(0, 26) : s}';
}

String _role(Object? r) => '$r'.replaceAll('_', ' ');

/// kind: 'xlsx' or 'pdf'. One sheet/section per team plus a summary and the unsold list.
Future<void> exportAuction(BuildContext c, Map<String, dynamic> t, String kind) => run(c, () async {
      final id = t['id'] as String;
      final players = await rows('players', id), teams = await rows('teams', id);
      final purse = ((await rows('auction_rules', id)).firstOrNull?['team_purse'] ?? 0) as int;
      List<Map<String, dynamic>> squad(Map<String, dynamic> tm) =>
          players.where((p) => p['sold_team_id'] == tm['id']).toList();
      int spent(Map<String, dynamic> tm) => squad(tm).fold(0, (s, p) => s + (p['sold_price'] as int));
      final unsold = players.where((p) => p['auction_status'] == 'unsold').toList();
      final raw = '${t['name']}'.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
      final file = raw.isEmpty ? 'auction' : raw;

      if (kind == 'xlsx') {
        final ex = Excel.createExcel();
        final sum = ex['Summary'];
        sum.appendRow([TextCellValue('Team'), TextCellValue('Players'), TextCellValue('Spent'), TextCellValue('Balance')]);
        for (var i = 0; i < teams.length; i++) {
          final tm = teams[i], sq = squad(tm);
          sum.appendRow([
            TextCellValue('${tm['name']}'),
            IntCellValue(sq.length),
            IntCellValue(spent(tm)),
            IntCellValue(purse - spent(tm)),
          ]);
          final sh = ex[_sheet(tm['name'], i)];
          sh.appendRow([TextCellValue('#'), TextCellValue('Player'), TextCellValue('Role'), TextCellValue('Price')]);
          for (var n = 0; n < sq.length; n++) {
            sh.appendRow([
              IntCellValue(n + 1),
              TextCellValue('${sq[n]['name']}'),
              TextCellValue(_role(sq[n]['role'])),
              IntCellValue(sq[n]['sold_price'] as int),
            ]);
          }
        }
        if (unsold.isNotEmpty) {
          final sh = ex['Unsold'];
          sh.appendRow([TextCellValue('Player'), TextCellValue('Role'), TextCellValue('Base price')]);
          for (final p in unsold) {
            sh.appendRow([TextCellValue('${p['name']}'), TextCellValue(_role(p['role'])), IntCellValue(p['base_price'] as int)]);
          }
        }
        ex.delete('Sheet1');
        final bytes = ex.encode();
        if (bytes == null) throw 'Could not build the Excel file';
        await FileSaver.instance.saveFile(
            name: file, bytes: Uint8List.fromList(bytes), ext: 'xlsx', mimeType: MimeType.microsoftExcel);
      } else {
        final doc = pw.Document();
        doc.addPage(pw.MultiPage(build: (_) => [
              pw.Header(level: 0, child: pw.Text('${t['name']}', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold))),
              for (final tm in teams) ...[
                pw.SizedBox(height: 10),
                pw.Text('${tm['name']}    Spent ${spent(tm)}    Balance ${purse - spent(tm)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.TableHelper.fromTextArray(headers: ['#', 'Player', 'Role', 'Price'], data: [
                  for (var n = 0; n < squad(tm).length; n++)
                    ['${n + 1}', '${squad(tm)[n]['name']}', _role(squad(tm)[n]['role']), '${squad(tm)[n]['sold_price']}'],
                ]),
              ],
              if (unsold.isNotEmpty) ...[
                pw.SizedBox(height: 10),
                pw.Text('Unsold', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.TableHelper.fromTextArray(headers: ['Player', 'Role', 'Base price'], data: [
                  for (final p in unsold) ['${p['name']}', _role(p['role']), '${p['base_price']}'],
                ]),
              ],
            ]));
        final bytes = await doc.save();
        await FileSaver.instance.saveFile(name: file, bytes: bytes, ext: 'pdf', mimeType: MimeType.pdf);
      }
    });
