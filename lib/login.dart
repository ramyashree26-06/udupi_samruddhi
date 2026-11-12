import 'package:flutter/material.dart';

import 'db.dart';
import 'db2.dart';
import 'nav.dart';
import 'theme.dart';

/// Shows the username + password screen until someone signs in; then [child].
class LoginGate extends StatelessWidget {
  final Widget child;
  const LoginGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: locked,
      builder: (context, isLocked, _) =>
          isLocked ? const _LoginScreen() : child,
    );
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen();
  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final user = TextEditingController();
  final pass = TextEditingController();
  final passFocus = FocusNode();
  String error = '';
  bool hide = true;
  bool busy = false;

  @override
  void dispose() {
    user.dispose();
    pass.dispose();
    passFocus.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    final r = await Db2.login(user.text, pass.text);
    if (!mounted) return;
    if (r == null) {
      setState(() {
        busy = false;
        error = 'Wrong username or password.';
      });
      pass.clear();
      return;
    }
    final perms = Db2.permSet(r['perms'] as String);
    allowed.value = perms;
    currentUser.value = r['name'] as String;
    currentRole.value = r['role'] as String;
    for (var i = 0; i < Db2.allModules.length; i++) {
      if (perms.contains(Db2.allModules[i])) {
        // First page the person may open (the Dashboard for the Admin).
        navIndex.value = i;
        break;
      }
    }
    locked.value = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/logo_full.png', height: 70),
                  const SizedBox(height: 10),
                  Text(Db.s('hotel_name'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('Sign in to continue', style: TextStyle(color: kMuted)),
                  const SizedBox(height: 22),
                  TextField(
                    controller: user,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                        labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
                    onSubmitted: (_) => passFocus.requestFocus(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pass,
                    focusNode: passFocus,
                    obscureText: hide,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => hide = !hide),
                      ),
                    ),
                    onSubmitted: (_) => _go(),
                  ),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(error, style: const TextStyle(color: kRed)),
                    ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: kOrange, minimumSize: const Size(0, 48)),
                      onPressed: busy ? null : _go,
                      child: const Text('Sign in', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Forgot your password? Ask the Admin.',
                      style: TextStyle(color: kMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
