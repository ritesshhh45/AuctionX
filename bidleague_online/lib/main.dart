import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core.dart';
import 'screens.dart';

const _url = String.fromEnvironment('SUPABASE_URL');
const _key = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: _url, anonKey: _key);
  runApp(const BidLeagueApp());
}

class BidLeagueApp extends StatelessWidget {
  const BidLeagueApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF0B6E4F), useMaterial3: true),
        home: StreamBuilder<AuthState>(
          stream: db.auth.onAuthStateChange,
          builder: (c, _) =>
              db.auth.currentSession == null ? const LoginScreen() : const TournamentsScreen(),
        ),
      );
}
