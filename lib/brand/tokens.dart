import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

/// Colour, type and motion for Transit. One place, so every screen agrees.
abstract final class Palette {
  // The old Mumbai local: a maroon rake with a cream band. Maroon is the brand
  // field (splash, icon, hero cards), cream the one accent, on a neutral
  // graphite night for the map.
  static const field = Color(0xFF0D0F12);
  static const fieldHi = Color(0xFF1A1D22);
  static const surface = Color(0xFF14171B);
  static const card = Color(0xFF1C1F24);
  static const cardHi = Color(0xFF25292F);
  static const line = Color(0xFF2C3037);
  static const ink = Color(0xFFF4EFE6);
  static const muted = Color(0xFFA9A397);
  static const faint = Color(0xFF6E6A63);
  static const signal = Color(0xFFEFD9B0); // the cream band
  static const signalInk = Color(0xFF2A0910);
  static const rake = Color(0xFF6E1C2B); // local-train maroon
  static const rakeDeep = Color(0xFF3B0D17);
  static const rakeHi = Color(0xFF8A2838);
  static const go = Color(0xFF3DF2A0);
  static const warn = Color(0xFFFF5D5D);
  static const ladies = Color(0xFFFF8FCB);
  static const ac = Color(0xFF7CD8FF);
}

/// Fraunces for headlines and the big figures, Schibsted Grotesk for
/// interface text, and italic Fraunces for the quiet lines in between.
abstract final class Txt {
  /// Off in tests, where nothing may touch the network.
  static bool useGoogleFonts = true;

  static TextStyle display(
    double size, {
    Color color = Palette.ink,
    double height = 1.0,
    FontWeight weight = FontWeight.w600,
    double? spacing,
  }) {
    final base = TextStyle(
      fontSize: size,
      height: height,
      letterSpacing: spacing ?? -0.025 * size,
      color: color,
      fontWeight: weight,
      fontFeatures: const [FontFeature.liningFigures(), FontFeature.tabularFigures()],
    );
    return useGoogleFonts ? GoogleFonts.fraunces(textStyle: base) : base;
  }

  static TextStyle text(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = Palette.ink,
    double height = 1.3,
    double spacing = 0,
    bool tabular = false,
  }) {
    final base = TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
      color: color,
      // Tabular figures only where numbers line up in columns: in running text
      // they widen full stops and commas too.
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );
    return useGoogleFonts ? GoogleFonts.schibstedGrotesk(textStyle: base) : base;
  }

  /// Secondary lines (notes, section heads): italic serif, never small grey caps.
  static TextStyle note(double size, {Color color = Palette.muted, double height = 1.3}) {
    final base = TextStyle(fontSize: size, height: height, color: color, fontStyle: FontStyle.italic);
    return useGoogleFonts ? GoogleFonts.fraunces(textStyle: base) : base;
  }

  static TextStyle label(double size, {Color color = Palette.muted}) =>
      text(size, weight: FontWeight.w700, color: color, spacing: 1.1);
}

/// Motion tokens. Things leave fast and land softly, like a train braking into
/// a platform. Reduced motion collapses durations to near zero.
abstract final class Motion {
  static const quick = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 560);
  static const hero = Duration(milliseconds: 680);
  static const fly = Duration(milliseconds: 1100);

  static const out = Cubic(0.16, 1, 0.3, 1); // expo-ish out
  static const inOut = Cubic(0.65, 0, 0.35, 1);
  static const spring = Cubic(0.34, 1.4, 0.64, 1); // slight overshoot

  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration d) => reduced(context) ? const Duration(milliseconds: 1) : d;
}

Color hex(String s) => Color(int.parse('FF${s.replaceFirst('#', '')}', radix: 16));
