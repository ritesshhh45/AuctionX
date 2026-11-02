import 'dart:async';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'core.dart';
import 'slabs.dart';
import 'theme.dart';

/// Realtime auction panel. owner=true shows controls; owner=false is the read-only live view.
class LivePanel extends StatelessWidget {
  final String tid;
  final bool owner;
  final String? captainTeam; // set for the captain panel: only this team gets a BID button
  const LivePanel({super.key, required this.tid, required this.owner, this.captainTeam});

  Future<void> _rpc(BuildContext c, String fn, [Map<String, dynamic>? extra]) =>
      run(c, () => db.rpc(fn, params: {'p_tournament': tid, ...?extra}));

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.3)),
      );

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: kSoft, borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: const TextStyle(fontSize: 12)),
      );

  List<String> _tags(Map<String, dynamic> p) => [
        '${p['role']}'.replaceAll('_', ' '),
        for (final k in ['batting_style', 'bowling_style', 'city'])
          if (p[k] != null && '${p[k]}'.isNotEmpty && '${p[k]}' != 'None') '${p[k]}',
      ];

  int _n(Object? v) => (v as num?)?.toInt() ?? 0;

  Widget _idle() => Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        width: double.infinity,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: kLine), color: kCard),
        child: Column(children: [
          const Icon(Icons.gavel, size: 40, color: kGold),
          const SizedBox(height: 10),
          const Text('Waiting for next player', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          if (owner)
            const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Tap a player below to put them on the block', style: TextStyle(fontSize: 12))),
        ]),
      );

  Widget _stage(BuildContext c, Map<String, dynamic> s, Map<String, dynamic> cur, Map<String, dynamic>? lead, bool auto) {
    final tt = Theme.of(c).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kGold, width: 1.5),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kSoft, kCard]),
      ),
      child: Column(children: [
        Row(children: [
          avatar(cur['photo_url'], r: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${cur['name']}', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final x in _tags(cur)) _chip(x)]),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        const Text('CURRENT BID', style: TextStyle(fontSize: 11, letterSpacing: 1.5)),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (w, a) =>
              ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: w)),
          child: Text('₹${s['current_bid']}',
              key: ValueKey(s['current_bid']), style: tt.displayMedium?.copyWith(color: kGold, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: lead == null ? kLine : kGold, borderRadius: BorderRadius.circular(20)),
          child: Text(lead == null ? 'No bids yet · base ₹${cur['base_price']}' : 'Leading: ${lead['name']}',
              style: TextStyle(color: lead == null ? kText : kBg, fontWeight: FontWeight.w700)),
        ),
        if (s['timer_ends_at'] != null)
          Countdown(DateTime.parse('${s['timer_ends_at']}'), onDone: owner && auto ? () => _rpc(c, 'mark_sold') : null),
      ]),
    );
  }

  Widget _teamCard(BuildContext c, Map<String, dynamic> t, int purse, int spent, int bought, bool leading, bool bidding) {
    final left = purse - spent;
    final frac = purse > 0 ? (left / purse).clamp(0.0, 1.0).toDouble() : 0.0;
    final canBid = bidding && (owner || captainTeam == t['id']);
    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), side: BorderSide(color: leading ? kGold : kLine, width: leading ? 2 : 1)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          avatar(t['logo_url'], r: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                  value: frac, minHeight: 6, borderRadius: BorderRadius.circular(3), color: kGold, backgroundColor: kLine),
              const SizedBox(height: 4),
              Text('₹$left left · $bought players', style: const TextStyle(fontSize: 12)),
            ]),
          ),
          if (canBid) ...[
            const SizedBox(width: 10),
            FilledButton(
                onPressed: leading ? null : () => _rpc(c, 'bid_next', {'p_team': t['id']}),
                child: Text(leading ? 'LEADING' : 'BID')),
          ],
        ]),
      ),
    );
  }

  Widget _playerRow(BuildContext c, Map<String, dynamic> p, bool canStart) => Card(
        child: ListTile(
          leading: avatar(p['photo_url']),
          title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(_tags(p).join(' · ')),
          trailing: canStart ? const Icon(Icons.gavel, color: kGold) : Text('₹${p['base_price']}'),
          onTap: canStart ? () => _rpc(c, 'start_player', {'p_player': p['id']}) : null,
        ),
      );

  Widget _soldRow(Map<String, dynamic> p, String team) => Card(
        child: ListTile(
          leading: avatar(p['photo_url']),
          title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('Sold to $team'),
          trailing: Text('₹${p['sold_price']}', style: const TextStyle(fontWeight: FontWeight.w900, color: kGold, fontSize: 16)),
        ),
      );

  Widget _body(BuildContext c, Map<String, dynamic> s, List<List<Map<String, dynamic>>> d, Map<String, dynamic>? ev, DateTime? evAt) {
    final players = d[0], teams = d[1], bids = d[3];
    final rules = d[2].firstOrNull ?? <String, dynamic>{};
    final purse = _n(rules['team_purse']);
    final auto = rules['auto_sold'] == true;
    final secs = _n(rules['timer_seconds'] ?? 30);
    final spent = <String, int>{}, count = <String, int>{};
    for (final p in players) {
      if (p['auction_status'] == 'sold' && p['sold_team_id'] != null) {
        final k = '${p['sold_team_id']}';
        spent[k] = (spent[k] ?? 0) + _n(p['sold_price']);
        count[k] = (count[k] ?? 0) + 1;
      }
    }
    final cur = players.where((p) => p['id'] == s['current_player_id']).firstOrNull;
    final lead = teams.where((t) => t['id'] == s['leading_team_id']).firstOrNull;
    final bidding = s['status'] == 'bidding' && cur != null;
    String tn(Object? id) {
      final m = teams.where((t) => t['id'] == id).firstOrNull;
      return m == null ? '?' : '${m['name']}';
    }

    final sold = players.where((p) => p['auction_status'] == 'sold').toList()
      ..sort((a, b) => '${b['sold_at'] ?? ''}'.compareTo('${a['sold_at'] ?? ''}'));
    final evPlayer = ev == null ? null : players.where((p) => p['id'] == ev['player']).firstOrNull;
    final left = evAt == null ? Duration.zero : const Duration(seconds: 7) - DateTime.now().difference(evAt);
    Widget? banner;
    if (evPlayer != null && !bidding && left > Duration.zero) {
      if (evPlayer['auction_status'] == 'sold') {
        banner = SoldBanner(
            key: ValueKey('sold-${evPlayer['id']}-$evAt'),
            player: '${evPlayer['name']}',
            photo: evPlayer['photo_url'],
            team: tn(evPlayer['sold_team_id']),
            price: _n(evPlayer['sold_price']),
            left: left);
      } else if (evPlayer['auction_status'] == 'unsold') {
        banner = UnsoldBanner(
            key: ValueKey('unsold-${evPlayer['id']}-$evAt'), player: '${evPlayer['name']}', photo: evPlayer['photo_url'], left: left);
      }
    }
    final queue = players.where((p) => p['auction_status'] == 'available' && p['reg_status'] == 'approved').toList();
    final unsold = players.where((p) => p['auction_status'] == 'unsold').toList();
    final canStart = owner && !bidding;
    final since = DateTime.tryParse('${s['block_started_at']}');
    final hist = bids
        .where((b) =>
            b['player_id'] == s['current_player_id'] &&
            (since == null || (DateTime.tryParse('${b['created_at']}')?.isAfter(since) ?? true)))
        .take(6)
        .toList();

    // Captain view: only their own team, one big BID button, no organizer controls.
    if (captainTeam != null && !owner) {
      final mine = teams.where((t) => t['id'] == captainTeam).firstOrNull;
      final iLead = bidding && s['leading_team_id'] == captainTeam;
      final tiers = normalizeSlabs(slabsFromRules(rules));
      final curBid = _n(s['current_bid']);
      final nextBid = lead == null ? curBid : curBid + stepFor(tiers, curBid);
      return ListView(padding: const EdgeInsets.all(16), children: [
        if (banner != null) banner,
      if (banner != null) const SizedBox(height: 12),
        if (bidding) _stage(c, s, cur, lead, false) else _idle(),
        if (bidding)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: SizedBox(
              height: 60,
              child: FilledButton(
                onPressed: iLead ? null : () => _rpc(c, 'bid_next', {'p_team': captainTeam}),
                child: Text(iLead ? 'YOUR TEAM IS LEADING' : 'BID  ₹$nextBid',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        _title('Your team'),
        if (mine != null)
          _teamCard(c, mine, purse, spent['${mine['id']}'] ?? 0, count['${mine['id']}'] ?? 0, iLead, false),
        if (bidding && hist.isNotEmpty) ...[
          _title('Bid history'),
          for (final b in hist)
            ListTile(
              dense: true,
              leading: const Icon(Icons.history, size: 18),
              title: Text(tn(b['team_id'])),
              trailing: Text('₹${b['amount']}', style: const TextStyle(fontWeight: FontWeight.w800, color: kGold)),
            ),
        ],
        _title('Sold (${sold.length})'),
        if (sold.isEmpty) const Text('Nobody sold yet.') else for (final p in sold.take(10)) _soldRow(p, tn(p['sold_team_id'])),
        const SizedBox(height: 24),
      ]);
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (banner != null) banner,
      if (banner != null) const SizedBox(height: 12),
      if (bidding) _stage(c, s, cur, lead, auto) else _idle(),
      if (owner && bidding)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
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
        ),
      if (bidding) ...[
        _title('Bid history'),
        for (final b in hist)
          ListTile(
            dense: true,
            leading: const Icon(Icons.history, size: 18),
            title: Text(tn(b['team_id'])),
            trailing: Text('₹${b['amount']}', style: const TextStyle(fontWeight: FontWeight.w800, color: kGold)),
          ),
      ],
      _title('Teams'),
      for (final t in teams)
        _teamCard(c, t, purse, spent['${t['id']}'] ?? 0, count['${t['id']}'] ?? 0, s['leading_team_id'] == t['id'] && bidding, bidding),
      if (owner && !bidding) ...[
        _title('Controls'),
        Card(
          child: Column(children: [
            ListTile(leading: const Icon(Icons.undo), title: const Text('Undo last sale'), onTap: () => _rpc(c, 'undo_last_sale')),
            if (unsold.isNotEmpty)
              ListTile(
                  leading: const Icon(Icons.replay),
                  title: Text('Re-auction all unsold (${unsold.length})'),
                  onTap: () => _rpc(c, 'reauction_unsold')),
            SwitchListTile(
              title: Text('Auto-sold after ${secs}s with no new bid'),
              subtitle: const Text('Works while your console screen is open'),
              value: auto,
              onChanged: (v) => _rpc(c, 'set_auto_sold', {'p_value': v}),
            ),
          ]),
        ),
      ],
      _title('Next up (${queue.length})'),
      if (queue.isEmpty) const Text('No players waiting.') else for (final p in queue) _playerRow(c, p, canStart),
      if (unsold.isNotEmpty) ...[
        _title('Unsold (${unsold.length})'),
        for (final p in unsold) _playerRow(c, p, canStart),
      ],
      _title('Sold (${sold.length})'),
      if (sold.isEmpty) const Text('Nobody sold yet.') else for (final p in sold.take(15)) _soldRow(p, tn(p['sold_team_id'])),
      const SizedBox(height: 24),
    ]);
  }

  Stream<_Tick> _ticks() async* {
    Map<String, dynamic>? prev, ev;
    DateTime? evAt;
    await for (final rows in db.from('auction_state').stream(primaryKey: ['tournament_id']).eq('tournament_id', tid)) {
      final s = rows.firstOrNull;
      if (s == null) continue;
      if (prev != null && prev['status'] == 'bidding' && s['status'] != 'bidding') {
        ev = {'player': prev['current_player_id']};
        evAt = DateTime.now();
      }
      if (s['status'] == 'bidding') {
        ev = null;
        evAt = null;
      }
      prev = s;
      yield _Tick(s, ev, evAt);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<_Tick>(
        stream: _ticks(),
        builder: (c, snap) {
          final tk = snap.data;
          if (tk == null) return const Center(child: CircularProgressIndicator());
          final s = tk.s;
          return FutureBuilder<List<List<Map<String, dynamic>>>>(
            key: ValueKey(s['status'] == 'bidding' ? '${s['current_player_id']}' : 'idle-${s['version']}'),
            future: Future.wait([rows('players', tid), rows('teams', tid), rows('auction_rules', tid), recentBids(tid)]),
            builder: (c, d) => d.hasData ? _body(c, s, d.data!, tk.ev, tk.at) : const Center(child: CircularProgressIndicator()),
          );
        },
      );
}

class _Tick {
  final Map<String, dynamic> s;
  final Map<String, dynamic>? ev;
  final DateTime? at;
  _Tick(this.s, this.ev, this.at);
}

/// Celebration card shown for a few seconds after a player is sold: hammer swing + SOLD stamp.
class SoldBanner extends StatefulWidget {
  final String player, team;
  final Object? photo;
  final int price;
  final Duration left;
  const SoldBanner({super.key, required this.player, required this.photo, required this.team, required this.price, required this.left});
  @override
  State<SoldBanner> createState() => _SoldBannerState();
}

class _SoldBannerState extends State<SoldBanner> {
  bool show = true;
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer(widget.left, () {
      if (mounted) setState(() => show = false);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    if (!show) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.elasticOut,
      builder: (c, v, child) =>
          Transform.scale(scale: 0.6 + 0.4 * v, child: Opacity(opacity: v.clamp(0.0, 1.0).toDouble(), child: child)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF3D98B), kGold, Color(0xFFB8913A)]),
          boxShadow: const [BoxShadow(color: Color(0x66DDB65B), blurRadius: 24, spreadRadius: 1)],
        ),
        child: Column(children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: -0.9, end: 0.0),
            duration: const Duration(milliseconds: 900),
            curve: Curves.bounceOut,
            builder: (c, a, child) => Transform.rotate(angle: a, child: child),
            child: const Icon(Icons.gavel, size: 46, color: kBg),
          ),
          avatar(widget.photo, r: 36),
          const SizedBox(height: 6),
          const Text('SOLD!', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: kBg, letterSpacing: 2)),
          Text(widget.player, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kBg)),
          const SizedBox(height: 4),
          Text('to ${widget.team} for ₹${widget.price}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kBg)),
        ]),
      ),
    );
  }
}

/// Shown for a few seconds when a player goes unsold.
class UnsoldBanner extends StatefulWidget {
  final String player;
  final Object? photo;
  final Duration left;
  const UnsoldBanner({super.key, required this.player, required this.photo, required this.left});
  @override
  State<UnsoldBanner> createState() => _UnsoldBannerState();
}

class _UnsoldBannerState extends State<UnsoldBanner> {
  bool show = true;
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer(widget.left, () {
      if (mounted) setState(() => show = false);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    if (!show) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      builder: (c, v, child) =>
          Transform.scale(scale: 0.7 + 0.3 * v, child: Opacity(opacity: v.clamp(0.0, 1.0).toDouble(), child: child)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kPurple, Color(0xFF3B2477)]),
        ),
        child: Column(children: [
          avatar(widget.photo, r: 34),
          const SizedBox(height: 6),
          const Text('UNSOLD', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: kText, letterSpacing: 2)),
          Text(widget.player, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kText)),
          const SizedBox(height: 2),
          const Text('Goes to the unsold list', style: TextStyle(fontSize: 13, color: kText)),
        ]),
      ),
    );
  }
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
      SimpleDialogOption(onPressed: () => Navigator.pop(d, 'access'), child: const Text('Captain access (code + PIN)')),
      SimpleDialogOption(onPressed: () => Navigator.pop(d, 'logo'), child: const Text('Set team logo')),
    ]),
  );
  if (a == null || !c.mounted) return;
  if (a == 'rename') return renameRow(c, 'teams', r);
  if (a == 'access') return captainAccess(c, r);
  String? url;
  await run(c, () async => url = await pickAndUploadPhoto('${r['tournament_id']}'));
  if (url == null || !c.mounted) return;
  return run(c, () => db.from('teams').update({'logo_url': url}).eq('id', r['id']));
}

/// Organizer: shows the captain code + this team's PIN, with copy / share / reset.
Future<void> captainAccess(BuildContext c, Map<String, dynamic> team) async {
  String code = '', pin = '', auction = '';
  await run(c, () async {
    final t = await db.from('tournaments').select('name').eq('id', team['tournament_id']).single();
    final cs = await db.from('tournament_secrets').select('captain_code').eq('tournament_id', team['tournament_id']).maybeSingle();
    final ps = await db.from('team_secrets').select('pin').eq('team_id', team['id']).maybeSingle();
    auction = '${t['name']}';
    code = '${cs?['captain_code'] ?? ''}';
    pin = '${ps?['pin'] ?? ''}';
  });
  if (code.isEmpty || !c.mounted) return;
  final taken = team['captain_user_id'] != null;
  final text = 'Join "$auction" as captain of ${team['name']} on AuctionX.\nCaptain code: $code\nTeam PIN: $pin\nOpen the app, then Join as captain.';
  await showDialog(
    context: c,
    builder: (d) => AlertDialog(
      title: Text('${team['name']}: captain access'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Captain code: $code', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 6),
        Text('Team PIN: $pin', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 12),
        Text(taken ? 'A captain has joined this team.' : 'No captain has joined yet.'),
        const SizedBox(height: 8),
        const Text('Share the code and this PIN only with the captain of this team.', style: TextStyle(fontSize: 12)),
      ]),
      actions: [
        TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(d);
            },
            child: const Text('Copy')),
        TextButton(onPressed: () => Share.share(text), child: const Text('Share')),
        TextButton(
            onPressed: () async {
              Navigator.pop(d);
              await run(c, () => db.rpc('reset_team_access', params: {'p_team': team['id']}));
              if (c.mounted) toast(c, 'Captain removed. A new PIN is ready.');
            },
            child: const Text('Reset')),
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close')),
      ],
    ),
  );
}

/// Captain: enter the captain code, pick your team, enter its PIN. Then you only see and bid for that team.
class CaptainScreen extends StatefulWidget {
  const CaptainScreen({super.key});
  @override
  State<CaptainScreen> createState() => _CaptainState();
}

class _CaptainState extends State<CaptainScreen> {
  final code = TextEditingController();
  List<Map<String, dynamic>> found = [];
  late Future<List<Map<String, dynamic>>> mine = _mine();

  Future<List<Map<String, dynamic>>> _mine() =>
      db.from('teams').select('id,name,tournament_id,tournaments(name)').eq('captain_user_id', db.auth.currentUser!.id);

  void _open(Map<String, dynamic> t) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => Scaffold(
              appBar: AppBar(title: Text('${t['name']}')),
              body: LivePanel(tid: '${t['tournament_id']}', owner: false, captainTeam: '${t['id']}'))));

  Future<void> _find() async {
    final v = code.text.trim();
    if (v.isEmpty) {
      toast(context, 'Enter the captain code');
      return;
    }
    await run(context, () async {
      final r = await db.rpc('captain_teams', params: {'p_code': v});
      final list = [for (final x in (r as List)) Map<String, dynamic>.from(x as Map)];
      if (!mounted) return;
      setState(() => found = list);
      if (list.isEmpty) toast(context, 'Wrong captain code');
    });
  }

  Future<void> _claim(Map<String, dynamic> t) async {
    final v = await form(context, 'PIN for ${t['team_name']}', ['4 digit team PIN']);
    if (v == null || !mounted) return;
    await run(context, () async {
      await db.rpc('claim_team', params: {'p_code': code.text.trim(), 'p_team': t['team_id'], 'p_pin': v[0]});
      if (!mounted) return;
      toast(context, 'You are now captain of ${t['team_name']}');
      setState(() {
        found = [];
        code.clear();
        mine = _mine();
      });
    });
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Captain')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Join as captain', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                const Text('Enter the captain code from your organizer, then pick your team and enter its PIN.',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: code,
                      textCapitalization: TextCapitalization.characters,
                      onSubmitted: (_) => _find(),
                      decoration: InputDecoration(
                          labelText: 'Captain code',
                          filled: true,
                          fillColor: kCard,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: _find, child: const Text('Find teams')),
                ]),
              ]),
            ),
          ),
          if (found.isNotEmpty) ...[
            const Padding(
                padding: EdgeInsets.only(top: 16, bottom: 8),
                child: Text('Choose your team', style: TextStyle(fontWeight: FontWeight.w800))),
            for (final t in found)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.shield, color: kGold),
                  title: Text('${t['team_name']}'),
                  subtitle: Text('${t['tournament_name']}'),
                  trailing: t['claimed'] == true ? const Text('Taken') : const Icon(Icons.chevron_right),
                  onTap: t['claimed'] == true ? null : () => _claim(t),
                ),
              ),
          ],
          const Padding(
              padding: EdgeInsets.only(top: 20, bottom: 8),
              child: Text('My teams', style: TextStyle(fontWeight: FontWeight.w800))),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: mine,
            builder: (c, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              if (s.data!.isEmpty) return const Text('You are not a captain of any team yet.');
              return Column(children: [
                for (final t in s.data!)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.sports_cricket, color: kGold),
                      title: Text('${t['name']}'),
                      subtitle: Text('${t['tournaments']?['name'] ?? ''}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(t),
                    ),
                  ),
              ]);
            },
          ),
        ]),
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

Widget avatar(Object? url, {double r = 22}) => CircleAvatar(
      radius: r,
      backgroundColor: kSoft,
      backgroundImage: url == null ? null : NetworkImage('$url'),
      child: url == null ? const Icon(Icons.person, color: kGold) : null,
    );

Future<List<String>?> lines(BuildContext c, String title, String hint) {
  final ctl = TextEditingController();
  return showDialog<List<String>>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
          controller: ctl, maxLines: 8, decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(
                d, ctl.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()),
            child: const Text('Add')),
      ],
    ),
  );
}

String roleOf(String s) {
  final x = s.toLowerCase();
  if (x.startsWith('bowl')) return 'bowler';
  if (x.startsWith('all')) return 'all_rounder';
  if (x == 'wk' || x.startsWith('wicket') || x.startsWith('keep')) return 'wicket_keeper';
  return 'batter';
}

Future<void> playerActions(BuildContext c, Map<String, dynamic> r) async {
  final a = await showDialog<String>(
    context: c,
    builder: (d) => SimpleDialog(title: Text('${r['name']}'), children: [
      for (final e in const {
        'approve': 'Approve',
        'reject': 'Reject',
        'rename': 'Rename',
        'price': 'Change base price',
        'photo': 'Set photo',
        'delete': 'Delete',
      }.entries)
        SimpleDialogOption(onPressed: () => Navigator.pop(d, e.key), child: Text(e.value)),
    ]),
  );
  if (a == null || !c.mounted) return;
  final id = r['id'];
  final t = db.from('players');
  switch (a) {
    case 'approve':
      return run(c, () => t.update({'reg_status': 'approved'}).eq('id', id));
    case 'reject':
      return run(c, () => t.update({'reg_status': 'rejected'}).eq('id', id));
    case 'rename':
      return renameRow(c, 'players', r);
    case 'delete':
      return run(c, () => t.delete().eq('id', id));
    case 'price':
      final v = await form(c, 'Base price', ['Base price']);
      if (v == null || !c.mounted) return;
      return run(c, () => t.update({'base_price': int.tryParse(v[0]) ?? r['base_price']}).eq('id', id));
    case 'photo':
      String? url;
      await run(c, () async => url = await pickAndUploadPhoto('${r['tournament_id']}'));
      if (url == null || !c.mounted) return;
      return run(c, () => t.update({'photo_url': url}).eq('id', id));
  }
}

Future<void> setPlayerPhoto(BuildContext c, Map<String, dynamic> p) async {
  String? url;
  await run(c, () async => url = await pickAndUploadPhoto('${p['tournament_id']}'));
  if (url == null || !c.mounted) return;
  await run(c, () => db.from('players').update({'photo_url': url}).eq('id', p['id']));
}

/// Stand-alone player registration page (opens from the shared link, no login needed).
class RegisterPlayerScreen extends StatefulWidget {
  final Map<String, dynamic> t;
  const RegisterPlayerScreen(this.t, {super.key});
  @override
  State<RegisterPlayerScreen> createState() => _RegisterState();
}

class _RegisterState extends State<RegisterPlayerScreen> {
  final name = TextEditingController(),
      city = TextEditingController(),
      age = TextEditingController(),
      phone = TextEditingController(),
      jersey = TextEditingController();
  String role = 'batter', bat = 'Right', bowl = 'None', shirt = 'M';
  String? photo;
  bool busy = false, done = false;

  InputDecoration _d(String l, IconData i) => InputDecoration(
      labelText: l,
      prefixIcon: Icon(i),
      filled: true,
      fillColor: kCard,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)));

  Future<void> _photo() async {
    String? u;
    await run(context, () async => u = await pickAndUploadPhoto('${widget.t['id']}'));
    if (u != null && mounted) setState(() => photo = u);
  }

  Future<void> _submit() async {
    if (name.text.trim().length < 2 || phone.text.trim().length < 10) {
      toast(context, 'Enter your name and a 10 digit phone number');
      return;
    }
    setState(() => busy = true);
    var ok = false;
    await run(context, () async {
      await db.rpc('register_player', params: {
        'p_code': widget.t['join_code'],
        'p_name': name.text.trim(),
        'p_phone': phone.text.trim(),
        'p_role': role,
        'p_photo': photo,
        'p_jersey': jersey.text.trim(),
        'p_tshirt': shirt,
        'p_city': city.text.trim(),
        'p_batting': bat,
        'p_bowling': bowl,
        'p_age': int.tryParse(age.text),
      });
      ok = true;
    });
    if (!mounted) return;
    setState(() {
      busy = false;
      done = ok;
    });
  }

  void _again() => setState(() {
        done = false;
        photo = null;
        for (final c in [name, city, age, phone, jersey]) {
          c.clear();
        }
      });

  Widget _chips(String label, List<String> items, String value, ValueChanged<String> on) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 6, bottom: 4), child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final x in items)
            ChoiceChip(label: Text(x.replaceAll('_', ' ')), selected: value == x, onSelected: (_) => setState(() => on(x))),
        ]),
      ]);

  @override
  Widget build(BuildContext c) {
    final closed = widget.t['reg_open'] == false;
    final banner = widget.t['banner_url'];
    return Scaffold(
      appBar: AppBar(title: const Text('Player registration')),
      body: closed
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Registration is closed for this auction.')))
          : done
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_circle, size: 72, color: kGold),
                      const SizedBox(height: 12),
                      const Text('You are registered!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('The organizer of ${widget.t['name']} will approve your entry.', textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      OutlinedButton(onPressed: _again, child: const Text('Register another player')),
                    ]),
                  ),
                )
              : ListView(padding: const EdgeInsets.all(16), children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: banner == null
                        ? Image.asset('assets/banner.jpg', fit: BoxFit.cover)
                        : Image.network('$banner', height: 130, width: double.infinity, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 14),
                  Text('${widget.t['name']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const Text('Fill your details to join the player list', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 16),
                  Center(
                    child: GestureDetector(
                      onTap: _photo,
                      child: Stack(children: [
                        avatar(photo, r: 56),
                        const Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(radius: 16, backgroundColor: kGold, child: Icon(Icons.camera_alt, size: 18, color: kBg)),
                        ),
                      ]),
                    ),
                  ),
                  const Padding(padding: EdgeInsets.all(8), child: Center(child: Text('Add your photo', style: TextStyle(fontSize: 12)))),
                  TextField(controller: name, decoration: _d('Full name', Icons.person_outline)),
                  const SizedBox(height: 12),
                  _chips('Playing role', const ['batter', 'bowler', 'all_rounder', 'wicket_keeper'], role, (x) => role = x),
                  const SizedBox(height: 8),
                  TextField(controller: city, decoration: _d('City / village', Icons.location_on_outlined)),
                  const SizedBox(height: 12),
                  TextField(controller: age, keyboardType: TextInputType.number, decoration: _d('Age', Icons.cake_outlined)),
                  _chips('Batting style', const ['Right', 'Left'], bat, (x) => bat = x),
                  _chips('Bowling style', const ['None', 'Fast', 'Medium', 'Spin'], bowl, (x) => bowl = x),
                  const SizedBox(height: 10),
                  TextField(controller: phone, keyboardType: TextInputType.phone, decoration: _d('Phone number', Icons.phone_outlined)),
                  const SizedBox(height: 12),
                  TextField(controller: jersey, decoration: _d('Name on jersey', Icons.checkroom)),
                  _chips('T-shirt size', const ['S', 'M', 'L', 'XL', 'XXL'], shirt, (x) => shirt = x),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                        onPressed: busy ? null : _submit,
                        child: busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                            : const Text('Register', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                  ),
                  const SizedBox(height: 24),
                ]),
    );
  }
}
