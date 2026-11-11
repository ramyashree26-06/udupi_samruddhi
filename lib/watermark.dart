import 'package:flutter/material.dart';

import 'db.dart';

/// Bump `tick.value++` after the watermark strength changes.
class Branding {
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
}

/// Puts the hotel logo faintly behind every screen, like a watermark.
class Watermark extends StatelessWidget {
  final Widget child;
  const Watermark({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Branding.tick,
      builder: (context, _, __) {
        var op = Db.d('logo_opacity');
        if (op <= 0) op = 0.10;
        if (op > 0.5) op = 0.5;
        // When the keyboard opens the screen gets shorter. Keep the logo where
        // it was by giving it the full height back (the keyboard height).
        final v = View.of(context);
        final kb = v.viewInsets.bottom / v.devicePixelRatio;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: -kb,
              child: IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final side =
                        (c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight) * 0.7;
                    return Center(
                      child: Opacity(
                        opacity: op,
                        child: Image.asset(
                          'assets/logo_icon.png',
                          width: side,
                          height: side,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
