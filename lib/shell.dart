import 'package:flutter/material.dart';
import 'auction_page.dart';
import 'config.dart';
import 'core.dart';
import 'slabs.dart';
import 'screens.dart';
import 'theme.dart';

final refreshTick = ValueNotifier<int>(0);

String fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

const _select = '*, auction_rules(team_purse)';

void openAuction(BuildContext c, Map<String, dynamic> t) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => AuctionScreen(t)));

Future<void> joinAsPlayer(BuildContext c) async {
  final v = await form(c, 'Join as player', ['Auction code']);
  if (v == null || v[0].isEmpty || !c.mounted) return;
  await run(c, () async {
    final t = await db.from('tournaments').select().eq('join_code', v[0].toUpperCase()).maybeSingle();
    if (!c.mounted) return;
    if (t == null) return toast(c, 'Code not found');
    Navigator.push(c, MaterialPageRoute(builder: (_) => RegisterPlayerScreen(t)));
  });
}

void showInfo(BuildContext c, String title, String text) => showDialog(
    context: c,
    builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))]));

void joinWithCode(BuildContext c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const ViewAuctionScreen()));

class Bookmarks {
  static final ids = ValueNotifier<Set<String>>({});
  static Future<void> load() async {
    final r = await db.from('bookmarks').select('tournament_id').eq('user_id', db.auth.currentUser!.id);
    ids.value = {for (final x in r) x['tournament_id'] as String};
  }

  static Future<void> toggle(String id) async {
    if (db.auth.currentUser == null) throw 'Login to bookmark auctions';
    final uid = db.auth.currentUser!.id;
    if (ids.value.contains(id)) {
      await db.from('bookmarks').delete().eq('user_id', uid).eq('tournament_id', id);
      ids.value = {...ids.value}..remove(id);
    } else {
      await db.from('bookmarks').insert({'user_id': uid, 'tournament_id': id});
      ids.value = {...ids.value, id};
    }
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int i = 0;
  @override
  void initState() {
    super.initState();
    Bookmarks.load().catchError((_) {});
  }

  Widget _drawer(BuildContext c) {
    Widget item(IconData ic, String label, VoidCallback f) => ListTile(
        leading: Icon(ic, color: kGold),
        title: Text(label),
        onTap: () {
          Navigator.pop(c);
          f();
        });
    return Drawer(
      backgroundColor: kCard,
      child: SafeArea(
        child: ListView(children: [
          ListTile(leading: avatar(null), title: Text(db.auth.currentUser?.email ?? ''), subtitle: const Text('Organizer')),
          const Divider(),
          item(Icons.add_circle_outline, 'Create Auction', () async {
            await Navigator.push(c, MaterialPageRoute(builder: (_) => const CreateAuctionScreen()));
            refreshTick.value++;
          }),
          item(Icons.gavel, 'My Auction', () => setState(() => i = 1)),
          item(Icons.bookmark_border, 'My Bookmark', () => setState(() => i = 2)),
          item(Icons.workspace_premium, 'Pricing', () => showInfo(c, 'Pricing', 'Organizer plan: ₹$kPrice per tournament.')),
          item(Icons.person_search, 'Auctioneers', () => setState(() => i = 3)),
          item(Icons.person_add_alt, 'Join as player', () => joinAsPlayer(c)),
          item(Icons.sports_cricket, 'Join as captain', () => Navigator.push(c, MaterialPageRoute(builder: (_) => const CaptainScreen()))),
          item(Icons.search, 'View Auction', () => joinWithCode(c)),
          item(Icons.info_outline, 'About Us',
              () => showInfo(c, 'About Us', '$kAppName runs cricket player auctions: teams, live bidding, live screen and exports.')),
          item(Icons.ondemand_video, 'Tutorial Videos', () => showInfo(c, 'Tutorial Videos', 'Coming soon.')),
          item(Icons.policy_outlined, 'Policies',
              () => showInfo(c, 'Policies', 'Replace this text with your Privacy Policy, Terms and Refund Policy before publishing.')),
          item(Icons.support_agent, 'Support', () => showInfo(c, 'Support', 'Write to $kSupportEmail')),
          item(Icons.delete_outline, 'Delete Account', () => _deleteAccount(c)),
          item(Icons.logout, 'Logout', () => db.auth.signOut()),
        ]),
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext c) async {
    final ok = await showDialog<bool>(
        context: c,
        builder: (d) => AlertDialog(
              title: const Text('Delete account?'),
              content: const Text('This permanently deletes your account and every auction you created. It cannot be undone.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
              ],
            ));
    if (ok != true || !c.mounted) return;
    await run(c, () async {
      await db.rpc('delete_my_account');
      await db.auth.signOut();
    });
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        endDrawer: _drawer(c),
        appBar: AppBar(
          title: Row(children: [
            Image.asset('assets/logo.png', height: 34),
            const SizedBox(width: 8),
            const Text(kAppName, style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ),
        body: ValueListenableBuilder<int>(
          valueListenable: refreshTick,
          builder: (c, t, _) => IndexedStack(index: i, children: [
            HomeTab(key: ValueKey('home$t')),
            MyAuctionsTab(key: ValueKey('my$t')),
            const BookmarksTab(),
            const Center(child: Text('Auctioneer directory: coming soon')),
            const ProfileTab(),
          ]),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (v) => setState(() => i = v),
          backgroundColor: kCard,
          indicatorColor: kSoft,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.gavel), label: 'My Auction'),
            NavigationDestination(icon: Icon(Icons.bookmark_border), selectedIcon: Icon(Icons.bookmark), label: 'Bookmarks'),
            NavigationDestination(icon: Icon(Icons.person_search), label: 'Auctioneer'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      );
}

class AuctionList extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function() load;
  final String empty;
  final Widget? header;
  final String cacheKey;
  const AuctionList({super.key, required this.load, required this.empty, required this.cacheKey, this.header});
  @override
  State<AuctionList> createState() => _AuctionListState();
}

class _AuctionListState extends State<AuctionList> {
  late Future<List<Map<String, dynamic>>> f = cached(widget.cacheKey, widget.load);
  Future<void> _refresh() async {
    setState(() => f = cached(widget.cacheKey, widget.load));
    await f;
  }

  @override
  Widget build(BuildContext c) => RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: f,
          builder: (c, s) {
            final items = s.data ?? const <Map<String, dynamic>>[];
            return ListView(padding: const EdgeInsets.all(16), children: [
              if (widget.header != null) widget.header!,
              if (s.connectionState != ConnectionState.done)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else if (items.isEmpty)
                Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(widget.empty)))
              else
                for (final t in items) AuctionCard(t),
            ]);
          },
        ),
      );
}

class AuctionCard extends StatelessWidget {
  final Map<String, dynamic> t;
  const AuctionCard(this.t, {super.key});
  @override
  Widget build(BuildContext c) {
    final start = t['starts_at'] == null ? null : DateTime.parse('${t['starts_at']}').toLocal();
    final r = t['auction_rules'];
    final pts = (r is List ? r.firstOrNull : r)?['team_purse'];
    final info = [
      if (start != null) '${fmtDate(start)} · ${fmtTime(start)}',
      if (pts != null) '$pts ${unitOf(t)}/team',
      'Code ${t['join_code']}',
    ].join('  ·  ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openAuction(c, t),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: kSoft, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.gavel, color: kGold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t['name']}', style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(info, style: Theme.of(c).textTheme.bodySmall),
              ]),
            ),
            ValueListenableBuilder<Set<String>>(
              valueListenable: Bookmarks.ids,
              builder: (c, ids, _) => IconButton(
                icon: Icon(ids.contains(t['id']) ? Icons.bookmark : Icons.bookmark_border, color: kGold),
                onPressed: () => run(c, () => Bookmarks.toggle(t['id'])),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  Widget _tile(IconData icon, String title, String sub, VoidCallback onTap) => Expanded(
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: kSoft, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: kGold),
                ),
                const SizedBox(height: 10),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext c) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final email = db.auth.currentUser?.email ?? '';
    final name = email.contains('@') ? email.split('@').first : 'there';
    return AuctionList(
      empty: 'No upcoming auctions yet. Create one, or open an auction with its code.',
      cacheKey: 'upcoming',
      load: () => db
          .from('tournaments')
          .select(_select)
          .or('visibility.is.null,visibility.eq.public,owner_id.eq.${db.auth.currentUser?.id}')
          .gte('starts_at', start.toUtc().toIso8601String())
          .order('starts_at')
          .limit(20),
      header: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.asset('assets/banner.jpg', fit: BoxFit.cover)),
          const SizedBox(height: 16),
          Text('Hi, $name', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          const SizedBox(height: 2),
          const Text('What would you like to do?', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          Row(children: [
            _tile(Icons.add_circle_outline, 'Create auction', 'Set up teams and players', () async {
              await Navigator.push(c, MaterialPageRoute(builder: (_) => const CreateAuctionScreen()));
              refreshTick.value++;
            }),
            const SizedBox(width: 12),
            _tile(Icons.search, 'View auction', 'Open live with a code', () => joinWithCode(c)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _tile(Icons.sports_cricket, 'Join as captain', 'Code + team PIN',
                () => Navigator.push(c, MaterialPageRoute(builder: (_) => const CaptainScreen()))),
            const SizedBox(width: 12),
            _tile(Icons.person_add_alt, 'Join as player', 'Register with a code', () => joinAsPlayer(c)),
          ]),
          const SizedBox(height: 22),
          const Text('Upcoming auctions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
      ),
    );
  }
}

class MyAuctionsTab extends StatelessWidget {
  const MyAuctionsTab({super.key});
  @override
  Widget build(BuildContext c) => AuctionList(
        empty: 'You have not created any auctions yet.',
        cacheKey: 'my',
        load: () => db
            .from('tournaments')
            .select(_select)
            .eq('owner_id', db.auth.currentUser!.id)
            .order('created_at', ascending: false),
      );
}

class BookmarksTab extends StatelessWidget {
  const BookmarksTab({super.key});
  @override
  Widget build(BuildContext c) => ValueListenableBuilder<Set<String>>(
        valueListenable: Bookmarks.ids,
        builder: (c, ids, _) => ids.isEmpty
            ? const Center(child: Text('No bookmarked auctions yet.'))
            : AuctionList(
                key: ValueKey(ids.length),
                empty: 'No bookmarked auctions yet.',
                cacheKey: 'bookmarks',
                load: () => db.from('tournaments').select(_select).inFilter('id', ids.toList()),
              ),
      );
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});
  @override
  Widget build(BuildContext c) => ListView(padding: const EdgeInsets.all(16), children: [
        Card(
            child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(db.auth.currentUser?.email ?? ''),
                subtitle: const Text('Signed in'))),
        const Card(
            child: ListTile(
                leading: Icon(Icons.workspace_premium, color: kGold),
                title: Text('Organizer plan'),
                subtitle: Text('₹$kPrice per tournament'))),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            icon: const Icon(Icons.logout), label: const Text('Logout'), onPressed: () => db.auth.signOut()),
      ]);
}

class CreateAuctionScreen extends StatefulWidget {
  const CreateAuctionScreen({super.key});
  @override
  State<CreateAuctionScreen> createState() => _CreateAuctionState();
}

class _CreateAuctionState extends State<CreateAuctionScreen> {
  final name = TextEditingController(),
      purse = TextEditingController(text: '10000'),
      minBid = TextEditingController(text: '50'),
      perTeam = TextEditingController(text: '11'),
      venue = TextEditingController();
  List<List<int>> slabs = [for (final s in kDefaultSlabs) [...s]];
  String pointSystem = 'Points', visibility = 'Public';
  bool remote = true;
  DateTime? date;
  TimeOfDay? time;
  bool busy = false;

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        suffixIcon: Icon(icon),
        filled: true,
        fillColor: kCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _box(String label, TextEditingController c, IconData icon, {bool number = false}) => TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: _dec(label, icon),
      );

  Widget _pick(String label, String? value, IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: InputDecorator(decoration: _dec(label, icon), child: Text(value ?? ' ')),
      );

  Future<void> _create() async {
    if (name.text.trim().isEmpty || date == null || time == null) {
      toast(context, 'Enter auction name, date and time');
      return;
    }
    final start = DateTime(date!.year, date!.month, date!.day, time!.hour, time!.minute);
    setState(() => busy = true);
    await run(context, () async {
      final tiers = normalizeSlabs(slabs);
      final id = await db.rpc('create_auction', params: {
        'p_name': name.text.trim(),
        'p_starts': start.toUtc().toIso8601String(),
        'p_purse': int.tryParse(purse.text) ?? 10000,
        'p_min_bid': int.tryParse(minBid.text) ?? 50,
        'p_step': tiers.first['step'],
      });
      final n = int.tryParse(perTeam.text) ?? 11;
      await db.from('auction_rules').update({'increment_tiers': tiers, 'min_squad': n, 'max_squad': n}).eq('tournament_id', id);
      await db.from('tournaments').update({
        'venue': venue.text.trim(),
        'point_system': pointSystem,
        'remote_bidding': remote,
        'visibility': visibility.toLowerCase(),
      }).eq('id', id);
      if (mounted) Navigator.pop(context);
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Create Auction')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          for (final w in [
            _box('Auction name', name, Icons.emoji_events_outlined),
            _pick('Auction date', date == null ? null : fmtDate(date!), Icons.calendar_today, () async {
              final d = await showDatePicker(
                  context: c,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 730)));
              if (d != null && mounted) setState(() => date = d);
            }),
            _pick('Auction time', time == null ? null : fmtTime(DateTime(2000, 1, 1, time!.hour, time!.minute)),
                Icons.schedule, () async {
              final t = await showTimePicker(context: c, initialTime: TimeOfDay.now());
              if (t != null && mounted) setState(() => time = t);
            }),
            _box('Points balance per team', purse, Icons.toll_outlined, number: true),
            _box('Minimum bid', minBid, Icons.gavel, number: true),
            SlabEditor(slabs: slabs, base: int.tryParse(minBid.text) ?? 50, onChanged: (v) => slabs = v),
            _box('Players per team', perTeam, Icons.groups, number: true),
            _box('Venue', venue, Icons.place_outlined),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Point system', style: TextStyle(fontWeight: FontWeight.w800)),
              Wrap(spacing: 8, children: [
                for (final x in const ['Points', 'Coins', 'Rupees', 'Credits', 'Custom'])
                  ChoiceChip(label: Text(x), selected: pointSystem == x, onSelected: (_) => setState(() => pointSystem = x)),
              ]),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable remote team bidding', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Captains bid from their own phone. Turn off if only the organizer places bids.'),
              value: remote,
              onChanged: (v) => setState(() => remote = v),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Auction visibility', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Public', label: Text('Public')),
                  ButtonSegment(value: 'Private', label: Text('Private (code only)')),
                ],
                selected: {visibility},
                onSelectionChanged: (v) => setState(() => visibility = v.first),
              ),
            ]),
          ]) ...[w, const SizedBox(height: 12)],
          FilledButton(
              onPressed: busy ? null : _create, child: Text(busy ? 'Creating...' : 'Create auction')),
        ]),
      );
}

/// "View auction": type the code in boxes, then open the auction.
class ViewAuctionScreen extends StatefulWidget {
  const ViewAuctionScreen({super.key});
  @override
  State<ViewAuctionScreen> createState() => _ViewAuctionState();
}

class _ViewAuctionState extends State<ViewAuctionScreen> {
  final code = TextEditingController();
  bool busy = false;

  Future<void> _go() async {
    final v = code.text.trim().toUpperCase();
    if (v.length < 6) {
      toast(context, 'Enter the 6 character auction code');
      return;
    }
    setState(() => busy = true);
    await run(context, () async {
      final t = await db.from('tournaments').select().eq('join_code', v).maybeSingle();
      if (!mounted) return;
      if (t == null) return toast(context, 'Auction code not found');
      openAuction(context, t);
    });
    if (mounted) setState(() => busy = false);
  }

  Widget _box(String ch, bool active) => Container(
        width: 44,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? kGold : kLine, width: active ? 2 : 1),
        ),
        child: Text(ch, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      );

  Widget _tip(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 6, right: 10), child: Icon(Icons.circle, size: 6, color: kGold)),
          Expanded(child: Text(t)),
        ]),
      );

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('View Auction')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Enter your auction code', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          Stack(alignment: Alignment.center, children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: code,
              builder: (c, v, _) {
                final t = v.text.toUpperCase();
                final kids = <Widget>[];
                for (var i = 0; i < 6; i++) {
                  if (i == 3) {
                    kids.add(const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('-', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))));
                  } else if (i > 0) {
                    kids.add(const SizedBox(width: 8));
                  }
                  kids.add(_box(i < t.length ? t[i] : '', i == t.length));
                }
                return Row(mainAxisAlignment: MainAxisAlignment.center, children: kids);
              },
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: code,
                  autofocus: true,
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _go(),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
                onPressed: busy ? null : _go,
                child: busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Get auction details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          ),
          const SizedBox(height: 24),
          _tip('Enter the auction code to view the auction details'),
          _tip('The auction code is provided by the auction organizer'),
          _tip('Captains: use Join as captain on the Home page'),
          _tip('Players: use Join as player to register'),
        ]),
      );
}
