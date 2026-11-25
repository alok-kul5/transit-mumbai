import 'package:material_ui/material_ui.dart';

import '../brand/tokens.dart';

/// Fades the new page in over a slight zoom, for the search overlay.
Route<T> fadeThrough<T>(Widget page) => PageRouteBuilder<T>(
  opaque: false,
  transitionDuration: Motion.base,
  reverseTransitionDuration: Motion.quick,
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (context, anim, _, child) {
    final t = CurvedAnimation(parent: anim, curve: Motion.out, reverseCurve: Curves.easeIn);
    return FadeTransition(
      opacity: t,
      child: ScaleTransition(scale: Tween(begin: .985, end: 1.0).animate(t), child: child),
    );
  },
);

/// Rises from the bottom like a sheet that takes the whole screen.
Route<T> slideUp<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: Motion.hero,
  reverseTransitionDuration: Motion.base,
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (context, anim, _, child) {
    final t = CurvedAnimation(parent: anim, curve: Motion.out, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: Tween(begin: .3, end: 1.0).animate(t),
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .12), end: Offset.zero).animate(t),
        child: child,
      ),
    );
  },
);
