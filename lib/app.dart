import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'brand/tokens.dart';
import 'screens/home.dart';
import 'screens/splash.dart';
import 'state/app_state.dart';

class TransitApp extends StatefulWidget {
  const TransitApp({super.key, required this.state, this.showSplash = true});
  final TransitState state;
  final bool showSplash;

  @override
  State<TransitApp> createState() => _TransitAppState();
}

class _TransitAppState extends State<TransitApp> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late bool _splash = widget.showSplash;
  final _introDone = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    // One clock for the whole app: countdowns and moving trains read it.
    _ticker = createTicker(widget.state.clock.tick)..start();
    if (!_splash) _introDone.value = true;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _introDone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TransitScope(
      state: widget.state,
      child: MaterialApp(
        title: 'Transit',
        debugShowCheckedModeBanner: false,
        scrollBehavior: const _DragEverywhere(),
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Palette.field,
          colorScheme: const ColorScheme.dark(
            primary: Palette.signal,
            onPrimary: Palette.signalInk,
            surface: Palette.surface,
            onSurface: Palette.ink,
          ),
          splashFactory: NoSplash.splashFactory,
          highlightColor: const Color(0x00000000),
          textSelectionTheme: const TextSelectionThemeData(
            cursorColor: Palette.signal,
            selectionColor: Color(0x55FFD60A),
            selectionHandleColor: Palette.signal,
          ),
        ),
        home: Stack(
          children: [
            HomeScreen(introDone: _introDone),
            if (_splash) Splash(onReveal: () => _introDone.value = true, onDone: () => setState(() => _splash = false)),
          ],
        ),
      ),
    );
  }
}

/// Lets a mouse drag lists on the web demo, like a finger.
class _DragEverywhere extends MaterialScrollBehavior {
  const _DragEverywhere();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}
