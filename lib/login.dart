import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auction_page.dart';
import 'core.dart';
import 'theme.dart';

InputDecoration fieldDec(String label, IconData icon, {Widget? suffix}) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      filled: true,
      fillColor: kCard,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final e = TextEditingController(), p = TextEditingController(), code = TextEditingController();
  bool signUp = false, busy = false, hide = true;

  String? get _redirect => kIsWeb ? Uri.base.origin : null;

  Future<void> _submit() async {
    final email = e.text.trim();
    if (email.isEmpty || p.text.length < 6) {
      toast(context, 'Enter your email and a password of at least 6 characters');
      return;
    }
    setState(() => busy = true);
    try {
      if (signUp) {
        final r = await db.auth.signUp(email: email, password: p.text);
        if (r.session == null && mounted) {
          toast(context, 'Account created. Confirm your email from the inbox, then login.');
        }
      } else {
        await db.auth.signInWithPassword(email: email, password: p.text);
      }
    } on AuthException catch (x) {
      if (mounted) toast(context, x.message);
    } catch (x) {
      if (mounted) toast(context, 'Error: $x');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _google() => run(context, () => db.auth.signInWithOAuth(OAuthProvider.google, redirectTo: _redirect));

  Future<void> _forgot() async {
    final email = e.text.trim();
    if (email.isEmpty) {
      toast(context, 'Enter your email first');
      return;
    }
    await run(context, () async {
      await db.auth.resetPasswordForEmail(email, redirectTo: _redirect);
      if (mounted) toast(context, 'Password reset link sent to $email');
    });
  }

  Future<void> _open() async {
    final v = code.text.trim();
    if (v.isEmpty) {
      toast(context, 'Enter the auction code');
      return;
    }
    await run(context, () async {
      final t = await db.from('tournaments').select().eq('join_code', v.toUpperCase()).maybeSingle();
      if (!mounted) return;
      if (t == null) return toast(context, 'Auction code not found');
      Navigator.push(context, MaterialPageRoute(builder: (_) => AuctionScreen(t)));
    });
  }

  Widget _hero() => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset('assets/banner.jpg', fit: BoxFit.cover),
      );

  Widget _feature(IconData i, String t) => Expanded(
        child: Column(children: [
          CircleAvatar(backgroundColor: kSoft, child: Icon(i, color: kGold)),
          const SizedBox(height: 6),
          Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );

  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(children: [
                  _hero(),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('Login')),
                            ButtonSegment(value: true, label: Text('Sign up')),
                          ],
                          selected: {signUp},
                          onSelectionChanged: (s) => setState(() => signUp = s.first),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                            controller: e,
                            keyboardType: TextInputType.emailAddress,
                            decoration: fieldDec('Email', Icons.mail_outline)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: p,
                          obscureText: hide,
                          onSubmitted: (_) => _submit(),
                          decoration: fieldDec('Password (min 6 characters)', Icons.lock_outline,
                              suffix: IconButton(
                                  icon: Icon(hide ? Icons.visibility_off : Icons.visibility),
                                  onPressed: () => setState(() => hide = !hide))),
                        ),
                        if (!signUp)
                          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _forgot, child: const Text('Forgot password?'))),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 48,
                          child: FilledButton(
                              onPressed: busy ? null : _submit,
                              child: busy
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                                  : Text(signUp ? 'Create account' : 'Login')),
                        ),
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Row(children: [
                              Expanded(child: Divider()),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or')),
                              Expanded(child: Divider()),
                            ])),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                              onPressed: _google,
                              icon: const Icon(Icons.g_mobiledata, size: 32),
                              label: const Text('Continue with Google')),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Player or viewer?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 4),
                        const Text('Enter the auction code to watch live or register as a player. No account needed.',
                            style: TextStyle(fontSize: 13)),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: TextField(
                                  controller: code,
                                  textCapitalization: TextCapitalization.characters,
                                  onSubmitted: (_) => _open(),
                                  decoration: fieldDec('Auction code', Icons.tag))),
                          const SizedBox(width: 12),
                          FilledButton.tonal(onPressed: _open, child: const Text('Open')),
                        ]),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    _feature(Icons.bolt, 'Live bidding'),
                    _feature(Icons.groups, 'Captain panel'),
                    _feature(Icons.cast, 'Live screen'),
                    _feature(Icons.table_view, 'Excel & PDF'),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Shown after the user opens the password-reset link from their email.
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key});
  @override
  State<NewPasswordScreen> createState() => _NewPasswordState();
}

class _NewPasswordState extends State<NewPasswordScreen> {
  final p = TextEditingController();
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Set a new password')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: p, obscureText: true, decoration: fieldDec('New password (min 6 characters)', Icons.lock_outline)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    if (p.text.length < 6) {
                      toast(c, 'Password must be at least 6 characters');
                      return;
                    }
                    await run(c, () => db.auth.updateUser(UserAttributes(password: p.text)));
                    if (c.mounted) toast(c, 'Password updated');
                  },
                  child: const Text('Save password'),
                ),
              ]),
            ),
          ),
        ),
      );
}
