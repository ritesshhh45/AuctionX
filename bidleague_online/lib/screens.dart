import 'dart:async';
import 'package:flutter/material.dart';
import 'core.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final e = TextEditingController(), p = TextEditingController();
  @override
  Widget build(BuildContext c) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(children: [
                Image.asset('assets/logo.png', height: 96),
                const SizedBox(height: 8),
                const Text(kAppName, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const Text('Organizer plan: ₹$kPrice per tournament'),
                const SizedBox(height: 16),
                TextField(controller: e, decoration: const InputDecoration(labelText: 'Email')),
                TextField(controller: p, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: () => run(c, () => db.auth.signInWithPassword(email: e.text.trim(), password: p.text)),
                    child: const Text('Login')),
                TextButton(
                    onPressed: () => run(c, () async {
                          await db.auth.signUp(email: e.text.trim(), password: p.text);
                        }),
                    child: const Text('Create account')),
              ]),
            ),
          ),
        ),
      );
}

class TournamentsScreen extends StatefulWidget {
  const TournamentsScreen({super.key});
  @override
  State<TournamentsScreen> createState() => _TournamentsState();
}

class _TournamentsState extends State<TournamentsScreen> {
  late Future<List<Map<String, dynamic>>> f = _load();
  Future<List<Map<String, dynamic>>> _load() => db
      .from('tournaments')
      .select()
      .eq('owner_id', db.auth.currentUser!.id)
      .order('created_at', ascending: false);

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
          title: Row(children: [
            Image.asset('assets/logo.png', height: 32),
            const SizedBox(width: 8),
            const Text(kAppName),
          ]),
          actions: [
            IconButton(
              icon: const Icon(Icons.login),
              tooltip: 'Join with code',
              onPressed: () async {
                final v = await form(c, 'Join auction', ['Auction code']);
                if (v == null || v[0].isEmpty || !c.mounted) return;
                await run(c, () async {
                  final t = await db.from('tournaments').select().eq('join_code', v[0].toUpperCase()).maybeSingle();
                  if (!c.mounted) return;
                  if (t == null) return toast(c, 'Code not found');
                  Navigator.push(
                      c,
                      MaterialPageRoute(
                          builder: (_) => Scaffold(
                              appBar: AppBar(title: Text('${t['name']}')),
                              body: LivePanel(tid: t['id'], owner: false))));
                });
              },
            ),
            IconButton(
                icon: const Icon(Icons.sports_cricket),
                tooltip: 'Captain panel',
                onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const CaptainScreen()))),
            IconButton(icon: const Icon(Icons.logout), onPressed: () => db.auth.signOut()),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('New auction'),
          onPressed: () async {
            final v = await form(c, 'New auction', ['Auction name', 'Team purse (e.g. 10000)']);
            if (v == null || v[0].isEmpty) return;
            await run(c, () => db.rpc('create_tournament', params: {'p_name': v[0], 'p_purse': int.tryParse(v[1]) ?? 10000}));
            if (mounted) setState(() => f = _load());
          },
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: f,
          builder: (c, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            if (s.data!.isEmpty) return const Center(child: Text('No auctions yet. Tap New auction.'));
            return ListView(children: [
              for (final t in s.data!)
                ListTile(
                  leading: const Icon(Icons.sports_cricket),
                  title: Text('${t['name']}'),
                  subtitle: Text('Code: ${t['join_code']}'),
                  onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => TournamentScreen(t))),
                ),
            ]);
          },
        ),
      );
}

Future<String?> pickRole(BuildContext c) => showDialog<String>(
      context: c,
      builder: (d) => SimpleDialog(title: const Text('Role'), children: [
        for (final r in const ['batter', 'bowler', 'all_rounder', 'wicket_keeper'])
          SimpleDialogOption(onPressed: () => Navigator.pop(d, r), child: Text(r.replaceAll('_', ' '))),
      ]),
    );

class TournamentScreen extends StatelessWidget {
  final Map<String, dynamic> t;
  const TournamentScreen(this.t, {super.key});
  @override
  Widget build(BuildContext context) {
    final id = t['id'] as String;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${t['name']} · ${t['join_code']}'),
          bottom: const TabBar(tabs: [Tab(text: 'Teams'), Tab(text: 'Players'), Tab(text: 'Live')]),
        ),
        body: TabBarView(children: [
          TableTab(
            table: 'teams',
            tid: id,
            addLabel: 'Add team',
            title: (r) => '${r['name']}',
            onRow: teamActions,
            add: (c) async {
              final v = await form(c, 'New team', ['Team name']);
              if (v == null || v[0].isEmpty) return;
              await run(c, () => db.from('teams').insert({'tournament_id': id, 'name': v[0]}));
            },
          ),
          TableTab(
            table: 'players',
            tid: id,
            addLabel: 'Add player',
            title: (r) =>
                '${r['name']} · ${r['role']} · base ₹${r['base_price']}${r['auction_status'] == 'sold' ? ' · SOLD ₹${r['sold_price']}' : ''}',
            onRow: (c, r) => renameRow(c, 'players', r),
            add: (c) async {
              final v = await form(c, 'New player', ['Name', 'Base price']);
              if (v == null || v[0].isEmpty || !c.mounted) return;
              final role = await pickRole(c);
              if (role == null || !c.mounted) return;
              await run(c, () => db.from('players').insert({
                    'tournament_id': id,
                    'name': v[0],
                    'role': role,
                    'base_price': int.tryParse(v[1]) ?? 50,
                  }));
            },
          ),
          LivePanel(tid: id, owner: true),
        ]),
      ),
    );
  }
}

class TableTab extends StatefulWidget {
  final String table, tid, addLabel;
  final String Function(Map<String, dynamic>) title;
  final Future<void> Function(BuildContext) add;
  final Future<void> Function(BuildContext, Map<String, dynamic>)? onRow;
  const TableTab(
      {super.key,
      required this.table,
      required this.tid,
      required this.addLabel,
      required this.title,
      required this.add,
      this.onRow});
  @override
  State<TableTab> createState() => _TableTabState();
}

class _TableTabState extends State<TableTab> {
  late Future<List<Map<String, dynamic>>> f = rows(widget.table, widget.tid);
  @override
  Widget build(BuildContext c) => ListView(children: [
        ListTile(
          leading: const Icon(Icons.add),
          title: Text(widget.addLabel),
          onTap: () async {
            await widget.add(c);
            if (mounted) setState(() => f = rows(widget.table, widget.tid));
          },
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: f,
          builder: (c, s) => Column(children: [
            for (final r in s.data ?? const <Map<String, dynamic>>[]) ListTile(
              title: Text(widget.title(r)),
              trailing: widget.onRow != null ? const Icon(Icons.edit) : null,
              onTap: widget.onRow == null
                  ? null
                  : () async {
                      await widget.onRow!(c, r);
                      if (mounted) setState(() => f = rows(widget.table, widget.tid));
                    },
            ),
          ]),
        ),
      ]);
}

/// Realtime auction panel. owner=true shows controls; owner=false is the read-only live view.
class LivePanel extends StatelessWidget {
  final String tid;
  final bool owner;
  final String? captainTeam; // set for the captain panel: only this team gets a BID button
  const LivePanel({super.key, required this.tid, required this.owner, this.captainTeam});

  Future<void> _rpc(BuildContext c, String fn, [Map<String, dynamic>? extra]) =>
      run(c, () => db.rpc(fn, params: {'p_tournament': tid, ...?extra}));

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: db.from('auction_state').stream(primaryKey: ['tournament_id']).eq('tournament_id', tid),
        builder: (c, snap) {
          final s = snap.data?.firstOrNull;
          if (s == null) return const Center(child: CircularProgressIndicator());
          return FutureBuilder<List<List<Map<String, dynamic>>>>(
            key: ValueKey(s['version']),
            future: Future.wait([rows('players', tid), rows('teams', tid), rows('auction_rules', tid), recentBids(tid)]),
            builder: (c, d) {
              if (!d.hasData) return const Center(child: CircularProgressIndicator());
              final players = d.data![0], teams = d.data![1];
              final rules = d.data![2].firstOrNull ?? <String, dynamic>{};
              final purse = (rules['team_purse'] ?? 0) as int;
              final auto = rules['auto_sold'] == true;
              final secs = (rules['timer_seconds'] ?? 30) as int;
              final bids = d.data![3];
              final spent = <String, int>{};
              for (final p in players) {
                if (p['auction_status'] == 'sold') {
                  final k = p['sold_team_id'] as String;
                  spent[k] = (spent[k] ?? 0) + (p['sold_price'] as int);
                }
              }
              final cur = players.where((p) => p['id'] == s['current_player_id']).firstOrNull;
              final lead = teams.where((t) => t['id'] == s['leading_team_id']).firstOrNull;
              final bidding = s['status'] == 'bidding' && cur != null;
              final tt = Theme.of(c).textTheme;
              String tn(Object? id) {
                final m = teams.where((t) => t['id'] == id).firstOrNull;
                return m == null ? '?' : '${m['name']}';
              }
              return ListView(padding: const EdgeInsets.all(16), children: [
                if (bidding) ...[
                  Card(
                      child: ListTile(
                          title: Text('${cur['name']}', style: tt.headlineSmall),
                          subtitle: Text('${cur['role']} · base ₹${cur['base_price']}'))),
                  Center(child: Text('₹${s['current_bid']}', style: tt.displayMedium)),
                  Center(child: Text(lead == null ? 'No bids yet' : 'Leading: ${lead['name']}')),
                  if (s['timer_ends_at'] != null)
                    Countdown(DateTime.parse('${s['timer_ends_at']}'),
                        onDone: owner && auto ? () => _rpc(c, 'mark_sold') : null),
                  for (final b in bids.where((b) => b['player_id'] == s['current_player_id']).take(6))
                    ListTile(dense: true, leading: const Icon(Icons.history, size: 18), title: Text('${tn(b['team_id'])} · ₹${b['amount']}')),
                ] else
                  const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Waiting for next player'))),
                if (owner && bidding)
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: () => _rpc(c, 'mark_unsold'), child: const Text('UNSOLD'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: OutlinedButton(
                      onPressed: () async {
                        final v = await form(c, 'Set live price', ['New price']);
                        if (v == null || !c.mounted) return;
                        await _rpc(c, 'edit_live_price', {'p_amount': int.tryParse(v[0]) ?? 0});
                      },
                      child: const Text('EDIT PRICE'),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: FilledButton(onPressed: () => _rpc(c, 'mark_sold'), child: const Text('SOLD'))),
                  ]),
                const Divider(),
                for (final t in teams)
                  ListTile(
                    title: Text('${t['name']}'),
                    subtitle: Text('Purse left ₹${purse - (spent[t['id']] ?? 0)}'),
                    trailing: bidding && (owner || captainTeam == t['id'])
                        ? FilledButton(onPressed: () => _rpc(c, 'bid_next', {'p_team': t['id']}), child: const Text('BID'))
                        : null,
                  ),
                if (owner && !bidding) ...[
                  const Divider(),
                  ListTile(
                      leading: const Icon(Icons.replay),
                      title: const Text('Re-auction unsold players'),
                      onTap: () => _rpc(c, 'reauction_unsold')),
                  ListTile(
                      leading: const Icon(Icons.undo),
                      title: const Text('Undo last sale'),
                      onTap: () => _rpc(c, 'undo_last_sale')),
                  SwitchListTile(
                      title: Text('Auto-sold after ${secs}s with no new bid'),
                      subtitle: const Text('Works while your console screen is open'),
                      value: auto,
                      onChanged: (v) => _rpc(c, 'set_auto_sold', {'p_value': v})),
                  for (final p in players.where((p) => p['auction_status'] == 'available' && p['reg_status'] == 'approved'))
                    ListTile(
                      leading: const Icon(Icons.gavel),
                      title: Text('${p['name']}'),
                      subtitle: Text('${p['role']} · base ₹${p['base_price']}'),
                      onTap: () => _rpc(c, 'start_player', {'p_player': p['id']}),
                    ),
                ],
              ]);
            },
          );
        },
      );
}

Future<void> renameRow(BuildContext c, String table, Map<String, dynamic> r) async {
  final v = await form(c, 'Rename', ['New name']);
  if (v == null || v[0].isEmpty) return;
  await run(c, () => db.from(table).update({'name': v[0]}).eq('id', r['id']));
}

Future<void> teamActions(BuildContext c, Map<String, dynamic> r) async {
  final a = await showDialog<String>(
    context: c,
    builder: (d) => SimpleDialog(title: Text('${r['name']}'), children: [
      SimpleDialogOption(onPressed: () => Navigator.pop(d, 'rename'), child: const Text('Rename team')),
      SimpleDialogOption(onPressed: () => Navigator.pop(d, 'captain'), child: const Text('Set captain (by email)')),
    ]),
  );
  if (a == null || !c.mounted) return;
  if (a == 'rename') return renameRow(c, 'teams', r);
  final v = await form(c, 'Captain email (must have signed up)', ['Email']);
  if (v == null || v[0].isEmpty || !c.mounted) return;
  await run(c, () => db.rpc('set_captain', params: {'p_team': r['id'], 'p_email': v[0]}));
}

class CaptainScreen extends StatelessWidget {
  const CaptainScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Captain panel')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: db
              .from('teams')
              .select('id,name,tournament_id,tournaments(name)')
              .eq('captain_user_id', db.auth.currentUser!.id),
          builder: (c, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            if (s.data!.isEmpty) return const Center(child: Text('You are not a captain of any team yet.'));
            return ListView(children: [
              for (final t in s.data!)
                ListTile(
                  leading: const Icon(Icons.shield),
                  title: Text('${t['name']}'),
                  subtitle: Text('${t['tournaments']?['name'] ?? ''}'),
                  onTap: () => Navigator.push(
                      c,
                      MaterialPageRoute(
                          builder: (_) => Scaffold(
                              appBar: AppBar(title: Text('${t['name']}')),
                              body: LivePanel(tid: t['tournament_id'], owner: false, captainTeam: t['id'])))),
                ),
            ]);
          },
        ),
      );
}

class Countdown extends StatefulWidget {
  final DateTime end;
  final VoidCallback? onDone;
  const Countdown(this.end, {super.key, this.onDone});
  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _t;
  bool _fired = false;
  int get left => widget.end.difference(DateTime.now()).inSeconds;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (left <= 0 && !_fired) {
        _fired = true;
        widget.onDone?.call();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Center(
      child: Text(left > 0 ? '⏱ ${left}s' : 'Time up', style: Theme.of(c).textTheme.titleLarge));
}
