import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/timetable.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0B0D1A),
    ),
  );
  final results = await Future.wait([
    rootBundle.loadString('assets/transit.json'),
    SharedPreferences.getInstance(),
    // Wait briefly for the faces, so the splash never flashes a fallback font.
    GoogleFonts.pendingFonts([GoogleFonts.unbounded(), GoogleFonts.manrope()])
        .timeout(const Duration(milliseconds: 1500), onTimeout: () => const [])
        .catchError((_) => const []),
  ]);
  final tt = Timetable.parse(results[0] as String);
  runApp(TransitApp(state: TransitState(tt, prefs: results[1] as SharedPreferences)));
}
