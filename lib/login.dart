import 'package:flutter/material.dart';

import 'db.dart';
import 'db2.dart';
import 'nav.dart';
import 'theme.dart';

/// Shows a PIN screen when staff PINs are set; otherwise shows [child].
class LoginGate extends StatelessWidget {
  final Widget child;
  const LoginGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: locked,
      builder: (context, isLocked, _) =>
          isLocked ? const _PinScreen() : child,
    );
  }
}

class _PinScreen extends StatefulWidget {
  const _PinScreen();
  @override
  State<_PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<_PinScreen> {
  final pin = TextEditingController();
  String error = '';

  @override
  void dispose() {
    pin.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final perms = await Db2.loginByPin(pin.text.trim());
    if (!mounted) return;
    if (perms == null) {
      setState(() => error = 'Wrong PIN. Try again.');
      pin.clear();
      return;
    }
    allowed.value = perms;
    for (var i = 0; i < Db2.allModules.length; i++) {
      if (perms.contains(Db2.allModules[i])) {
        // POS is the home page for those who may use it.
        navIndex.value = perms.contains('pos') ? 1 : i;
        break;
      }
    }
    locked.value = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/logo_full.png', height: 70),
              const SizedBox(height: 10),
              Text(Db.s('hotel_name'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 24),
              TextField(
                controller: pin,
                autofocus: true,
                obscureText: true,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: const InputDecoration(hintText: 'Enter PIN'),
                onSubmitted: (_) => _go(),
              ),
              if (error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error, style: const TextStyle(color: kRed)),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: kOrange, minimumSize: const Size(0, 46)),
                  onPressed: _go,
                  child: const Text('Open'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
