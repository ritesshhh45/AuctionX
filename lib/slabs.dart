import 'package:flutter/material.dart';
import 'theme.dart';

/// A slab is [fromAmount, increaseBy]. Each slab applies once the current bid reaches its "from" amount.
const kDefaultSlabs = <List<int>>[
  [0, 10],
  [100, 20],
  [200, 50],
];

List<List<int>> slabsFromRules(Map<String, dynamic> rules) {
  final t = rules['increment_tiers'];
  if (t is List && t.isNotEmpty) {
    return [for (final x in t) [(x['min'] as num).toInt(), (x['step'] as num).toInt()]];
  }
  return [for (final s in kDefaultSlabs) [...s]];
}

/// Cleans user input: drops invalid rows, sorts, forces the first slab to start at 0. Returns the JSON stored in the database.
List<Map<String, int>> normalizeSlabs(List<List<int>> slabs) {
  final ok = slabs.where((s) => s[1] > 0 && s[0] >= 0).toList()..sort((a, b) => a[0].compareTo(b[0]));
  if (ok.isEmpty) return [for (final s in kDefaultSlabs) {'min': s[0], 'step': s[1]}];
  final seen = <int>{};
  final out = <Map<String, int>>[];
  for (final s in ok) {
    if (seen.add(s[0])) out.add({'min': s[0], 'step': s[1]});
  }
  out.first['min'] = 0;
  return out;
}

int stepFor(List<Map<String, int>> tiers, int bid) {
  var st = tiers.first['step']!;
  for (final t in tiers) {
    if (t['min']! <= bid) st = t['step']!;
  }
  return st;
}

class SlabEditor extends StatefulWidget {
  final List<List<int>> slabs;
  final int base; // minimum bid, used for the preview
  final ValueChanged<List<List<int>>> onChanged;
  const SlabEditor({super.key, required this.slabs, required this.base, required this.onChanged});
  @override
  State<SlabEditor> createState() => _SlabEditorState();
}

class _SlabEditorState extends State<SlabEditor> {
  final from = <TextEditingController>[], step = <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    for (final s in widget.slabs) {
      from.add(TextEditingController(text: '${s[0]}'));
      step.add(TextEditingController(text: '${s[1]}'));
    }
  }

  List<List<int>> get _value =>
      [for (var i = 0; i < from.length; i++) [int.tryParse(from[i].text) ?? 0, int.tryParse(step[i].text) ?? 0]];

  void _notify() {
    widget.onChanged(_value);
    setState(() {});
  }

  void _add() {
    final last = from.isEmpty ? 0 : (int.tryParse(from.last.text) ?? 0);
    final lastStep = step.isEmpty ? 10 : (int.tryParse(step.last.text) ?? 10);
    from.add(TextEditingController(text: '${last + 100}'));
    step.add(TextEditingController(text: '${lastStep + 10}'));
    _notify();
  }

  void _remove(int i) {
    from.removeAt(i).dispose();
    step.removeAt(i).dispose();
    _notify();
  }

  InputDecoration _d(String l) => InputDecoration(
      labelText: l, isDense: true, filled: true, fillColor: kCard, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)));

  String _preview() {
    final tiers = normalizeSlabs(_value);
    var b = widget.base;
    final out = <int>[];
    for (var i = 0; i < 14; i++) {
      out.add(b);
      b += stepFor(tiers, b);
    }
    return '${out.join(', ')} ...';
  }

  @override
  Widget build(BuildContext c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Bid slabs', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        const Text('Each slab starts when the current bid reaches its "From" amount. Example: 0 > +10, 100 > +20, 200 > +50.',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 10),
        for (var i = 0; i < from.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      controller: from[i],
                      enabled: i != 0,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _notify(),
                      decoration: _d(i == 0 ? 'From (start)' : 'From bid'))),
              const SizedBox(width: 10),
              Expanded(
                  child: TextField(
                      controller: step[i],
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _notify(),
                      decoration: _d('Increase by'))),
              SizedBox(
                  width: 40,
                  child: i == 0
                      ? null
                      : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _remove(i))),
            ]),
          ),
        TextButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add slab')),
        Text('Bids will go: ${_preview()}', style: const TextStyle(fontSize: 12, color: kGold)),
      ]);
}
