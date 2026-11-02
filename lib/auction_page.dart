import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'config.dart';
import 'core.dart';
import 'export.dart';
import 'screens.dart';
import 'shell.dart';
import 'slabs.dart';
import 'theme.dart';

typedef Rows = List<Map<String, dynamic>>;

int _i(Object? v) => (v as num?)?.toInt() ?? 0;

String teamName(Rows teams, Object? id) {
  final m = teams.where((x) => x['id'] == id).firstOrNull;
  return m == null ? '' : '${m['name']}';
}

void copy(BuildContext c, String text) {
  Clipboard.setData(ClipboardData(text: text));
  toast(c, 'Copied');
}

Future<void> addTeams(BuildContext c, String id) async {
  final names = await lines(c, 'Add teams', 'One team name per line');
  if (names == null || names.isEmpty) return;
  await run(c, () => db.from('teams').insert([for (final n in names) {'tournament_id': id, 'name': n}]));
}

Future<void> addPlayers(BuildContext c, String id) async {
  final input = await lines(c, 'Add players',
      'One per line: Name, role, base price\nExample: Rahul, bowler, 100\nRoles: batter, bowler, all, wk');
  if (input == null || input.isEmpty) return;
  await run(c, () async {
    final base = _i((await rows('auction_rules', id)).firstOrNull?['base_price'] ?? 50);
    final data = <Map<String, dynamic>>[];
    for (final line in input) {
      final p = line.split(RegExp(r'[,\t]')).map((e) => e.trim()).toList();
      data.add({
        'tournament_id': id,
        'name': p[0],
        'role': roleOf(p.length > 1 ? p[1] : ''),
        'base_price': int.tryParse(p.length > 2 ? p[2] : '') ?? base,
      });
    }
    await db.from('players').insert(data);
  });
}

/// Auction detail page: header + Teams, Players, MVP, Sponsors, Link, Configuration, About.
class AuctionScreen extends StatefulWidget {
  final Map<String, dynamic> t;
  const AuctionScreen(this.t, {super.key});
  @override
  State<AuctionScreen> createState() => _AuctionScreenState();
}

class _AuctionScreenState extends State<AuctionScreen> {
  late Future<Map<String, dynamic>> data = _load();
  bool get owner => widget.t['owner_id'] == db.auth.currentUser?.id;
  String get id => widget.t['id'] as String;

  @override
  void initState() {
    super.initState();
    if (!owner) db.rpc('add_view', params: {'p_tournament': id}).then((_) {}, onError: (_) {});
  }

  void reload() => setState(() => data = _load());

  Future<Map<String, dynamic>> _load() async {
    final r = await Future.wait<Object>([
      rows('players', id),
      rows('teams', id),
      rows('auction_rules', id),
      rows('sponsors', id),
      tournamentRow(id),
    ]);
    return {
      'players': r[0],
      'teams': r[1],
      'rules': (r[2] as Rows).firstOrNull ?? <String, dynamic>{},
      'sponsors': r[3],
      't': r[4],
    };
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<Map<String, dynamic>>(
        future: data,
        builder: (c, s) {
          if (s.hasError) return Scaffold(appBar: AppBar(), body: Center(child: Text('${s.error}')));
          if (!s.hasData) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
          final d = s.data!;
          final t = d['t'] as Map<String, dynamic>, rules = d['rules'] as Map<String, dynamic>;
          final players = d['players'] as Rows, teams = d['teams'] as Rows, sponsors = d['sponsors'] as Rows;
          final me = db.auth.currentUser?.id;
          final String? myTeam = teams.where((t) => t['captain_user_id'] == me).firstOrNull?['id'] as String?;
          return DefaultTabController(
            length: 7,
            child: Scaffold(
              appBar: AppBar(
                title: Text('${t['name']}', overflow: TextOverflow.ellipsis),
                actions: [
                  if (!owner && t['reg_open'] != false)
                    IconButton(
                        icon: const Icon(Icons.person_add),
                        tooltip: 'Register as player',
                        onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => RegisterPlayerScreen(t)))),
                  ValueListenableBuilder<Set<String>>(
                    valueListenable: Bookmarks.ids,
                    builder: (c, ids, _) => IconButton(
                        icon: Icon(ids.contains(id) ? Icons.bookmark : Icons.bookmark_border),
                        onPressed: () => run(c, () => Bookmarks.toggle(id))),
                  ),
                ],
              ),
              body: Column(children: [
                _Header(t: t, rules: rules, owner: owner, onChanged: reload),
                const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
                  Tab(text: 'TEAMS'),
                  Tab(text: 'PLAYERS'),
                  Tab(text: 'MVP'),
                  Tab(text: 'SPONSORS'),
                  Tab(text: 'LINK'),
                  Tab(text: 'CONFIGURATION'),
                  Tab(text: 'ABOUT'),
                ]),
                Expanded(
                  child: TabBarView(children: [
                    TeamsTab(id: id, owner: owner, teams: teams, players: players, rules: rules, onChanged: reload),
                    PlayersTab(id: id, owner: owner, players: players, teams: teams, onChanged: reload),
                    MvpTab(players: players, teams: teams),
                    SponsorsTab(id: id, owner: owner, sponsors: sponsors, onChanged: reload),
                    LinkTab(t: t, owner: owner, onChanged: reload),
                    ConfigTab(t: t, rules: rules, owner: owner, onChanged: reload),
                    AboutTab(t: t, rules: rules, teams: teams, players: players, owner: owner),
                  ]),
                ),
              ]),
              bottomNavigationBar: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton(
                    onPressed: () => Navigator.push(
                        c,
                        MaterialPageRoute(
                            builder: (_) => Scaffold(
                                appBar: AppBar(title: Text('${t['name']}')),
                                body: LivePanel(tid: id, owner: owner, captainTeam: owner ? null : myTeam)))),
                    child: const Text('VIEW AUCTION'),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

class _Header extends StatelessWidget {
  final Map<String, dynamic> t, rules;
  final bool owner;
  final VoidCallback onChanged;
  const _Header({required this.t, required this.rules, required this.owner, required this.onChanged});

  Future<void> _banner(BuildContext c) async {
    String? u;
    await run(c, () async => u = await pickAndUploadPhoto('${t['id']}'));
    if (u == null || !c.mounted) return;
    await run(c, () => db.from('tournaments').update({'banner_url': u}).eq('id', t['id']));
    onChanged();
  }

  @override
  Widget build(BuildContext c) {
    final start = t['starts_at'] == null ? null : DateTime.parse('${t['starts_at']}').toLocal();
    final banner = t['banner_url'];
    return Column(children: [
      Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          color: kSoft,
          image: banner == null ? null : DecorationImage(image: NetworkImage('$banner'), fit: BoxFit.cover),
        ),
        child: owner
            ? Align(
                alignment: Alignment.topRight,
                child: IconButton.filledTonal(
                    icon: const Icon(Icons.add_photo_alternate), tooltip: 'Set banner', onPressed: () => _banner(c)))
            : null,
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          avatar(t['logo_url'], r: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Code: ${t['join_code']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () => copy(c, '${t['join_code']}')),
              ]),
              Text([
                if (start != null) '${fmtDate(start)} · ${fmtTime(start)}',
                '${_i(rules['team_purse'])} ${unitOf(t)}/team',
                if (rules['max_squad'] != null) '${_i(rules['max_squad'])} players/team',
                '${_i(t['views'])} views',
              ].join('  ·  '), style: Theme.of(c).textTheme.bodySmall),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

class TeamsTab extends StatelessWidget {
  final String id;
  final bool owner;
  final Rows teams, players;
  final Map<String, dynamic> rules;
  final VoidCallback onChanged;
  const TeamsTab(
      {super.key,
      required this.id,
      required this.owner,
      required this.teams,
      required this.players,
      required this.rules,
      required this.onChanged});

  Widget _stat(String l, Object v, {Color? color}) => Column(children: [
        Text(l, style: const TextStyle(fontSize: 11)),
        Text('$v', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
      ]);

  Widget _card(BuildContext c, Map<String, dynamic> t, int purse, int minSquad, int reserve) {
    final sq = players.where((p) => p['sold_team_id'] == t['id'] && p['auction_status'] == 'sold').toList();
    final spent = sq.fold<int>(0, (s, p) => s + _i(p['sold_price']));
    final need = minSquad > sq.length ? minSquad - sq.length : 0;
    final maxBid = (purse - spent - (need > 0 ? need - 1 : 0) * reserve).clamp(0, purse);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: owner
            ? () async {
                await teamActions(c, t);
                onChanged();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            avatar(t['logo_url'], r: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _stat('Players', sq.length),
                  _stat('Need', need),
                  _stat('Used', spent),
                  _stat('Max bid', maxBid, color: kGold),
                ]),
              ]),
            ),
            const SizedBox(width: 12),
            Column(children: [
              Text('${purse - spent}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: kGold)),
              const Text('left', style: TextStyle(fontSize: 11)),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final purse = _i(rules['team_purse']);
    final minSquad = _i(rules['min_squad'] ?? 11), reserve = _i(rules['reserve_per_slot'] ?? 50);
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (owner)
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Add teams (one or many)'),
          onTap: () async {
            await addTeams(c, id);
            onChanged();
          },
        ),
      if (teams.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No teams yet'))),
      for (final t in teams) _card(c, t, purse, minSquad, reserve),
    ]);
  }
}

class PlayersTab extends StatefulWidget {
  final String id;
  final bool owner;
  final Rows players, teams;
  final VoidCallback onChanged;
  const PlayersTab(
      {super.key, required this.id, required this.owner, required this.players, required this.teams, required this.onChanged});
  @override
  State<PlayersTab> createState() => _PlayersTabState();
}

class _PlayersTabState extends State<PlayersTab> {
  String q = '', f = 'all';

  bool _match(Map<String, dynamic> p) {
    if (q.isNotEmpty && !'${p['name']}'.toLowerCase().contains(q.toLowerCase())) return false;
    switch (f) {
      case 'all':
        return true;
      case 'pending':
        return p['reg_status'] == 'pending';
      default:
        return p['reg_status'] == 'approved' && p['auction_status'] == f;
    }
  }

  Widget _row(BuildContext c, Map<String, dynamic> p) {
    final sold = p['auction_status'] == 'sold';
    final status = p['reg_status'] == 'approved' ? '${p['auction_status']}' : '${p['reg_status']}';
    return ListTile(
      leading: GestureDetector(
          onTap: widget.owner
              ? () async {
                  await setPlayerPhoto(c, p);
                  widget.onChanged();
                }
              : null,
          child: avatar(p['photo_url'])),
      title: Text('${p['name']}'),
      subtitle: Text(sold
          ? '${p['role']} · sold to ${teamName(widget.teams, p['sold_team_id'])}'
          : '${p['role']} · base ₹${p['base_price']}'),
      trailing: sold
          ? Text('₹${p['sold_price']}', style: const TextStyle(fontWeight: FontWeight.w800, color: kGold))
          : Text(status),
      onTap: widget.owner
          ? () async {
              await playerActions(c, p);
              widget.onChanged();
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext c) {
    final list = widget.players.where(_match).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          onChanged: (v) => setState(() => q = v),
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search), hintText: 'Search player', border: OutlineInputBorder()),
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final x in const ['all', 'available', 'sold', 'unsold', 'pending'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(x), selected: f == x, onSelected: (_) => setState(() => f = x)),
            ),
        ]),
      ),
      Expanded(
        child: ListView(children: [
          if (widget.owner)
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add players (one or many)'),
              onTap: () async {
                await addPlayers(c, widget.id);
                widget.onChanged();
              },
            ),
          for (final p in list) _row(c, p),
        ]),
      ),
    ]);
  }
}

/// MVP here = the most expensive sold players.
class MvpTab extends StatelessWidget {
  final Rows players, teams;
  const MvpTab({super.key, required this.players, required this.teams});
  @override
  Widget build(BuildContext c) {
    final top = players.where((p) => p['auction_status'] == 'sold').toList()
      ..sort((a, b) => _i(b['sold_price']).compareTo(_i(a['sold_price'])));
    if (top.isEmpty) return const Center(child: Text('No players sold yet'));
    return ListView(children: [
      for (var n = 0; n < top.length && n < 10; n++)
        ListTile(
          leading: avatar(top[n]['photo_url']),
          title: Text('${n + 1}. ${top[n]['name']}'),
          subtitle: Text(teamName(teams, top[n]['sold_team_id'])),
          trailing: Text('₹${top[n]['sold_price']}', style: const TextStyle(fontWeight: FontWeight.w800, color: kGold)),
        ),
    ]);
  }
}

class SponsorsTab extends StatelessWidget {
  final String id;
  final bool owner;
  final Rows sponsors;
  final VoidCallback onChanged;
  const SponsorsTab({super.key, required this.id, required this.owner, required this.sponsors, required this.onChanged});
  @override
  Widget build(BuildContext c) => ListView(padding: const EdgeInsets.all(12), children: [
        if (owner)
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add sponsor'),
            onTap: () async {
              final v = await form(c, 'New sponsor', ['Sponsor name', 'Type (Prize money, Kit, ...)', 'Amount']);
              if (v == null || v[0].isEmpty || !c.mounted) return;
              await run(c, () => db.from('sponsors').insert({
                    'tournament_id': id,
                    'name': v[0],
                    'kind': v[1].isEmpty ? 'Sponsor' : v[1],
                    'amount': int.tryParse(v[2]) ?? 0,
                  }));
              onChanged();
            },
          ),
        if (sponsors.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No sponsors yet'))),
        for (final s in sponsors)
          Card(
            child: ListTile(
              leading: const Icon(Icons.workspace_premium, color: kGold),
              title: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${s['kind']}  ·  ₹${s['amount']}'),
              trailing: owner
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await run(c, () => db.from('sponsors').delete().eq('id', s['id']));
                        onChanged();
                      })
                  : null,
            ),
          ),
      ]);
}

class LinkTab extends StatelessWidget {
  final Map<String, dynamic> t;
  final bool owner;
  final VoidCallback onChanged;
  const LinkTab({super.key, required this.t, required this.owner, required this.onChanged});

  String _base() => kWebBase.isNotEmpty ? kWebBase : (kIsWeb ? Uri.base.origin : '');

  String _link(String path) => _base().isEmpty ? 'Auction code: ${t['join_code']}' : '${_base()}/#/$path/${t['join_code']}';

  Widget _regCard(BuildContext c) {
    final url = _link('register');
    final isUrl = url.startsWith('http');
    final open = t['reg_open'] != false;
        final msg = 'Register as a player for "${t['name']}" on $kAppName:\n$url';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.how_to_reg, color: kGold),
            const SizedBox(width: 10),
            const Expanded(child: Text('Player registration link', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: open ? kGold : kLine, borderRadius: BorderRadius.circular(20)),
              child: Text(open ? 'OPEN' : 'CLOSED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: open ? kBg : kText)),
            ),
          ]),
          const SizedBox(height: 10),
          SelectableText(url, style: const TextStyle(color: kGold)),
          if (!isUrl)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Host the web build and set kWebBase in lib/config.dart to get a link you can share.', style: TextStyle(fontSize: 12)),
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
                onPressed: () => copy(c, isUrl ? url : '${t['join_code']}'),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy link')),
            FilledButton.tonalIcon(onPressed: () => Share.share(msg), icon: const Icon(Icons.share, size: 18), label: const Text('Share')),
            OutlinedButton.icon(
                onPressed: open ? () => Navigator.push(c, MaterialPageRoute(builder: (_) => RegisterPlayerScreen(t))) : null,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open')),
            if (isUrl)
              OutlinedButton.icon(
                onPressed: () => showDialog(
                  context: c,
                  builder: (d) => AlertDialog(
                    title: const Text('Scan to register'),
                    content: SizedBox(
                      width: 220,
                      height: 220,
                      child: Container(color: Colors.white, padding: const EdgeInsets.all(8), child: QrImageView(data: url)),
                    ),
                    actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
                  ),
                ),
                icon: const Icon(Icons.qr_code, size: 18),
                label: const Text('QR'),
              ),
          ]),
          if (owner)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Registration open'),
              value: open,
              onChanged: (v) async {
                await run(c, () => db.from('tournaments').update({'reg_open': v}).eq('id', t['id']));
                onChanged();
              },
            ),
        ]),
      ),
    );
  }

  Widget _row(BuildContext c, IconData icon, String title, String text, {VoidCallback? open}) => Card(
        child: ListTile(
          leading: Icon(icon, color: kGold),
          title: Text(title),
          subtitle: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.copy, size: 20), onPressed: () => copy(c, text)),
            IconButton(icon: const Icon(Icons.share, size: 20), onPressed: () => Share.share(text)),
            if (open != null) IconButton(icon: const Icon(Icons.open_in_new, size: 20), onPressed: open),
          ]),
        ),
      );

  @override
  Widget build(BuildContext c) {
    final yt = '${t['youtube_url'] ?? ''}';
    final regOpen = t['reg_open'] != false;
    return ListView(padding: const EdgeInsets.all(12), children: [
      _regCard(c),
      if (_base().isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Web links appear here after you host the web build and set kWebBase in lib/config.dart. '
              'Open buttons already work inside the app.'),
        ),
      _row(c, Icons.cast, 'Live view (projector display)', _link('view'),
          open: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ProjectorScreen(t)))),
      if (owner)
        _row(c, Icons.laptop, 'Manage from laptop', _link('manage'),
            open: () => Navigator.push(
                c,
                MaterialPageRoute(
                    builder: (_) => Scaffold(
                        appBar: AppBar(title: Text('${t['name']}')), body: LivePanel(tid: '${t['id']}', owner: true))))),
      if (owner) CaptainCodeCard(tid: '${t['id']}'),
      if (yt.isNotEmpty) _row(c, Icons.smart_display, 'YouTube live', yt),
    ]);
  }
}

class ConfigTab extends StatefulWidget {
  final Map<String, dynamic> t;
  final bool owner;
  final VoidCallback onChanged;
  final Map<String, dynamic> rules;
  const ConfigTab({super.key, required this.t, required this.rules, required this.owner, required this.onChanged});
  @override
  State<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<ConfigTab> {
  late final yt = TextEditingController(text: '${widget.t['youtube_url'] ?? ''}');

  late List<List<int>> slabs = slabsFromRules(widget.rules);

  Future<void> _saveSlabs() async {
    await run(context, () => db.from('auction_rules').update({'increment_tiers': normalizeSlabs(slabs)}).eq('tournament_id', widget.t['id']));
    if (mounted) toast(context, 'Bid slabs saved');
    widget.onChanged();
  }

  Future<void> _save(Map<String, dynamic> v) async {
    await run(context, () => db.from('tournaments').update(v).eq('id', widget.t['id']));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext c) {
    if (!widget.owner) return const Center(child: Text('Only the organizer can change settings'));
    final cur = '${widget.t['live_theme'] ?? 'classic'}';
    return ListView(padding: const EdgeInsets.all(12), children: [
      TextField(
          controller: yt,
          decoration: const InputDecoration(
              labelText: 'YouTube live URL', prefixIcon: Icon(Icons.smart_display), border: OutlineInputBorder())),
      const SizedBox(height: 8),
      Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: () => _save({'youtube_url': yt.text.trim()}), child: const Text('Save link'))),
      SwitchListTile(
        title: const Text('Player registration open'),
        value: widget.t['reg_open'] != false,
        onChanged: (v) => _save({'reg_open': v}),
      ),
      const Divider(height: 28),
      SlabEditor(slabs: slabs, base: _i(widget.rules['min_bid'] ?? 50), onChanged: (v) => slabs = v),
      Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _saveSlabs, child: const Text('Save bid slabs'))),
      const Divider(
      ),
      const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Live screen theme', style: TextStyle(fontWeight: FontWeight.w800))),
      Wrap(spacing: 12, runSpacing: 12, children: [
        for (final e in kLiveThemes.entries)
          GestureDetector(
            onTap: () => _save({'live_theme': e.key}),
            child: Container(
              width: 150,
              height: 80,
              decoration: BoxDecoration(
                color: e.value[0],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cur == e.key ? kGold : kLine, width: cur == e.key ? 3 : 1),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(e.key.toUpperCase(), style: TextStyle(color: e.value[1], fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Container(width: 60, height: 8, decoration: BoxDecoration(color: e.value[2], borderRadius: BorderRadius.circular(4))),
              ]),
            ),
          ),
      ]),
    ]);
  }
}

class AboutTab extends StatelessWidget {
  final Map<String, dynamic> t, rules;
  final Rows teams, players;
  final bool owner;
  const AboutTab(
      {super.key, required this.t, required this.rules, required this.teams, required this.players, required this.owner});

  Widget _info(IconData i, String l, Object v) => SizedBox(
        width: 160,
        child: ListTile(
          dense: true,
          leading: Icon(i, color: kGold),
          title: Text(l, style: const TextStyle(fontSize: 11)),
          subtitle: Text('$v', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      );

  @override
  Widget build(BuildContext c) {
    final tiers = rules['increment_tiers'];
    final step = tiers is List && tiers.isNotEmpty ? _i((tiers.first as Map)['step']) : 0;
    final code = '${t['join_code']}';
    final share = 'Join "${t['name']}" on $kAppName. Auction code: $code';
    return ListView(padding: const EdgeInsets.all(12), children: [
      Wrap(children: [
        _info(Icons.tag, 'Auction code', code),
        _info(Icons.toll_outlined, 'Points / team', _i(rules['team_purse'])),
        _info(Icons.gavel, 'Minimum bid', _i(rules['min_bid'])),
        _info(Icons.trending_up, 'Bid increase', step),
        _info(Icons.groups, 'Teams', teams.length),
        _info(Icons.sports_cricket, 'Players', players.length),
      ]),
      const SizedBox(height: 12),
      Center(child: Container(color: Colors.white, padding: const EdgeInsets.all(8), child: QrImageView(data: code, size: 170))),
      Center(child: Padding(padding: const EdgeInsets.all(8), child: Text(code, style: const TextStyle(fontWeight: FontWeight.w800)))),
      Center(
          child: OutlinedButton.icon(
              icon: const Icon(Icons.share), label: const Text('Share this auction'), onPressed: () => Share.share(share))),
      if (owner) ...[
        const Divider(height: 32),
        ListTile(
            leading: const Icon(Icons.table_view, color: kGold),
            title: const Text('Export Excel'),
            onTap: () => exportAuction(c, t, 'xlsx')),
        ListTile(
            leading: const Icon(Icons.picture_as_pdf, color: kGold),
            title: const Text('Export PDF'),
            onTap: () => exportAuction(c, t, 'pdf')),
      ],
    ]);
  }
}

/// Full-screen display for a projector / screen share / stream capture, styled by the chosen live theme.
class ProjectorScreen extends StatefulWidget {
  final Map<String, dynamic> t;
  const ProjectorScreen(this.t, {super.key});
  @override
  State<ProjectorScreen> createState() => _ProjectorState();
}

class _ProjectorState extends State<ProjectorScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => wideMode.value = true);
  }

  @override
  void dispose() {
    wideMode.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = '${widget.t['id']}';
    final th = kLiveThemes['${widget.t['live_theme']}'] ?? kLiveThemes['classic']!;
    final bg = th[0], fg = th[1], ac = th[2];
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: StreamBuilder<Rows>(
          stream: db.from('auction_state').stream(primaryKey: ['tournament_id']).eq('tournament_id', id),
          builder: (c, snap) {
            final s = snap.data?.firstOrNull;
            if (s == null) return Center(child: CircularProgressIndicator(color: ac));
            return FutureBuilder<List<Rows>>(
              key: ValueKey(s['status'] == 'bidding' ? '${s['current_player_id']}' : 'idle-${s['version']}'),
              future: Future.wait([rows('players', id), rows('teams', id), rows('auction_rules', id)]),
              builder: (c, d) {
                if (!d.hasData) return Center(child: CircularProgressIndicator(color: ac));
                final players = d.data![0], teams = d.data![1];
                final purse = _i(d.data![2].firstOrNull?['team_purse']);
                final cur = players.where((p) => p['id'] == s['current_player_id']).firstOrNull;
                final bidding = s['status'] == 'bidding' && cur != null;
                int left(Map<String, dynamic> tm) => purse -
                    players
                        .where((p) => p['sold_team_id'] == tm['id'] && p['auction_status'] == 'sold')
                        .fold<int>(0, (a, p) => a + _i(p['sold_price']));
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Row(children: [
                      IconButton(icon: Icon(Icons.arrow_back, color: fg), onPressed: () => Navigator.maybePop(c)),
                      Expanded(
                          child: Text('${widget.t['name']}',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: fg, fontSize: 24, fontWeight: FontWeight.w800))),
                      const SizedBox(width: 48),
                    ]),
                    Expanded(
                      child: Center(
                        child: bidding
                            ? FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  avatar(cur['photo_url'], r: 90),
                                  const SizedBox(height: 16),
                                  Text('${cur['name']}', style: TextStyle(color: fg, fontSize: 56, fontWeight: FontWeight.w800)),
                                  Text('${cur['role']} · base ₹${cur['base_price']}', style: TextStyle(color: fg, fontSize: 24)),
                                  const SizedBox(height: 16),
                                  Text('₹${s['current_bid']}', style: TextStyle(color: ac, fontSize: 96, fontWeight: FontWeight.w900)),
                                  Text(
                                      s['leading_team_id'] == null
                                          ? 'Waiting for bids'
                                          : 'Leading: ${teamName(teams, s['leading_team_id'])}',
                                      style: TextStyle(color: fg, fontSize: 30)),
                                ]),
                              )
                            : Text('Waiting for next player', style: TextStyle(color: fg, fontSize: 36)),
                      ),
                    ),
                    Wrap(spacing: 10, runSpacing: 8, children: [
                      for (final tm in teams)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: fg.withAlpha(30), borderRadius: BorderRadius.circular(10)),
                          child: Text('${tm['name']}  ₹${left(tm)}', style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
                        ),
                    ]),
                  ]),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Organizer only: the captain code to share with team captains.
class CaptainCodeCard extends StatelessWidget {
  final String tid;
  const CaptainCodeCard({super.key, required this.tid});
  @override
  Widget build(BuildContext c) => FutureBuilder<Map<String, dynamic>?>(
        future: db.from('tournament_secrets').select('captain_code').eq('tournament_id', tid).maybeSingle(),
        builder: (c, s) {
          final code = s.data?['captain_code'];
          if (code == null) return const SizedBox.shrink();
          final text = 'Captain code: $code (open $kAppName, then Join as captain). Each team also has its own PIN.';
          return Card(
            child: ListTile(
              leading: const Icon(Icons.sports_cricket, color: kGold),
              title: const Text('Captain code'),
              subtitle: Text('$code   ·   PIN per team: Teams tab, tap a team, Captain access'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.copy, size: 20), onPressed: () => copy(c, '$code')),
                IconButton(icon: const Icon(Icons.share, size: 20), onPressed: () => Share.share(text)),
              ]),
            ),
          );
        },
      );
}

/// Unit label chosen at creation: points, coins, rupees, credits.
String unitOf(Map<String, dynamic> t) {
  final p = '${t['point_system'] ?? 'Points'}';
  return p == 'Custom' ? 'points' : p.toLowerCase();
}
