import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kAppName = 'AuctionX';
const kPrice = 2499; // organizer plan, per tournament

SupabaseClient get db => Supabase.instance.client;

/// True while saved (cached) data is being shown because the network failed.
final offline = ValueNotifier<bool>(false);

/// Runs [load]; on success saves the result on the device, on failure returns the last saved copy.
Future<List<Map<String, dynamic>>> cached(String key, Future<List<Map<String, dynamic>>> Function() load) async {
  final prefs = await SharedPreferences.getInstance();
  final k = 'c:${db.auth.currentUser?.id}:$key';
  try {
    final r = await load();
    await prefs.setString(k, jsonEncode(r));
    if (offline.value) offline.value = false;
    return r;
  } catch (e) {
    final s = prefs.getString(k);
    if (s == null) rethrow;
    offline.value = true;
    return (jsonDecode(s) as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
  }
}

Future<List<Map<String, dynamic>>> rows(String table, String tid) =>
    cached('$table:$tid', () => db.from(table).select().eq('tournament_id', tid));

Future<Map<String, dynamic>> tournamentRow(String id) async =>
    (await cached('t:$id', () async => [await db.from('tournaments').select().eq('id', id).single()])).first;

String friendly(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) return e.message;
  final s = '$e';
  if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('ClientException') || s.contains('XMLHttpRequest')) {
    return 'No internet connection. Try again when you are online.';
  }
  return s;
}

void toast(BuildContext c, Object m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('$m')));

/// Runs a backend call and shows the server's error message if it fails.
Future<void> run(BuildContext c, Future<dynamic> Function() f) async {
  try {
    await f();
  } catch (e) {
    if (c.mounted) toast(c, friendly(e));
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

/// Lets the user pick a photo, uploads it to the public player-photos bucket, returns its URL.
Future<String?> pickAndUploadPhoto(String tid) async {
  final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, imageQuality: 70);
  if (x == null) return null;
  final bytes = await x.readAsBytes();
  final path = '$tid/${DateTime.now().millisecondsSinceEpoch}.jpg';
  await db.storage
      .from('player-photos')
      .uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
  return db.storage.from('player-photos').getPublicUrl(path);
}

/// true while a full-width screen (projector display) is open; the app is otherwise centered at phone width.
final wideMode = ValueNotifier<bool>(false);
