import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auction_page.dart';
import 'config.dart';
import 'core.dart';
import 'login.dart';
import 'screens.dart';
import 'shell.dart';
import 'splash.dart';
import 'theme.dart';

// --dart-define still works; otherwise the values from lib/config.dart are used.
const _url = String.fromEnvironment('SUPABASE_URL', defaultValue: kSupabaseUrl);
const _key = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: kSupabaseAnonKey);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!_url.startsWith('https://') || _key.length < 20) {
    runApp(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Supabase URL / anon key not set.\n\nOpen lib/config.dart, paste both values, save, and run again.',
                        textAlign: TextAlign.center))))));
    return;
  }
  await Supabase.initialize(url: _url, anonKey: _key);
  runApp(const BidLeagueApp());
}

class BidLeagueApp extends StatelessWidget {
  const BidLeagueApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        builder: (c, child) => ValueListenableBuilder<bool>(
          valueListenable: wideMode,
          builder: (c, wide, _) => ColoredBox(
            color: kBg,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? double.infinity : 560),
                child: Column(children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: offline,
                    builder: (c, off, _) => off
                        ? const Material(
                            color: kSoft,
                            child: SizedBox(
                                width: double.infinity,
                                child: Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Text('Offline: showing saved data. Bidding needs internet.',
                                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12)))))
                        : const SizedBox.shrink(),
                  ),
                  Expanded(child: child ?? const SizedBox()),
                ]),
              ),
            ),
          ),
        ),
        home: const SplashGate(),
      );
}

/// Shows the animated intro once, on top of the app that is already loading underneath.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool showIntro = true;
  @override
  Widget build(BuildContext context) => Stack(children: [
        const DeepLinkGate(),
        if (showIntro)
          Positioned.fill(
            child: IntroSplash(onDone: () {
              if (mounted) setState(() => showIntro = false);
            }),
          ),
      ]);
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: db.auth.onAuthStateChange,
        builder: (c, snap) {
          if (snap.data?.event == AuthChangeEvent.passwordRecovery) return const NewPasswordScreen();
          return db.auth.currentSession == null ? const LoginScreen() : const HomeShell();
        },
      );
}

/// Web links: #/view/CODE (projector display), #/register/CODE (player form), #/manage/CODE (organizer, needs login).
class DeepLinkGate extends StatelessWidget {
  const DeepLinkGate({super.key});
  @override
  Widget build(BuildContext context) {
    final m = kIsWeb ? RegExp(r'^/(view|register|manage)/(\w+)$').firstMatch(Uri.base.fragment) : null;
    if (m == null) return const AuthGate();
    final kind = m[1]!, code = m[2]!;
    return FutureBuilder<Map<String, dynamic>?>(
      future: db.from('tournaments').select().eq('join_code', code.toUpperCase()).maybeSingle(),
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final t = s.data;
        if (t == null) return const AuthGate();
        switch (kind) {
          case 'view':
            return ProjectorScreen(t);
          case 'register':
            return RegisterPlayerScreen(t);
          default:
            return db.auth.currentSession == null ? const AuthGate() : AuctionScreen(t);
        }
      },
    );
  }
}
