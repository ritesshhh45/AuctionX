import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kAppName = 'BidLeague';
const kPrice = 2499; // organizer plan, per tournament

SupabaseClient get db => Supabase.instance.client;

Future<List<Map<String, dynamic>>> rows(String table, String tid) =>
    db.from(table).select().eq('tournament_id', tid);

void toast(BuildContext c, Object m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('$m')));

/// Runs a backend call and shows the server's error message if it fails.
Future<void> run(BuildContext c, Future<dynamic> Function() f) async {
  try {
    await f();
  } catch (e) {
    if (c.mounted) toast(c, e is PostgrestException ? e.message : e);
  }
}

Future<List<String>?> form(BuildContext c, String title, List<String> labels) {
  final cs = labels.map((_) => TextEditingController()).toList();
  return showDialog<List<String>>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < labels.length; i++)
          TextField(controller: cs[i], decoration: InputDecoration(labelText: labels[i])),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(d, cs.map((e) => e.text.trim()).toList()),
            child: const Text('OK')),
      ],
    ),
  );
}

Future<List<Map<String, dynamic>>> recentBids(String tid) =>
    db.from('bids').select().eq('tournament_id', tid).order('created_at', ascending: false).limit(40);
