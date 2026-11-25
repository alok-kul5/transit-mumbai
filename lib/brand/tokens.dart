import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

/// Colour, type and motion for Transit. One place, so every screen agrees.
abstract final class Palette {
  // A midnight field, the colour of the city after the last local, and the
  // yellow painted along every platform edge.
  static const field = Color(0xFF0B0D1A);
  static const fieldHi = Color(0xFF161A33);
  static const surface = Color(0xFF13162B);
  static const card = Color(0xFF1B1F3A);
  static const cardHi = Color(0xFF242949);
  static const line = Color(0xFF2B3054);
  static const ink = Color(0xFFF5F2E9);
  static const muted = Color(0xFF9CA1C4);
  static const faint = Color(0xFF636A93);
  static const signal = Color(0xFFFFD60A);
  static const signalInk = Color(0xFF14110A);
  static const go = Color(0xFF3DF2A0);
  static const warn = Color(0xFFFF5D5D);
  static const ladies = Color(0xFFFF8FCB);
  static const ac = Color(0xFF7CD8FF);
}

/// Unbounded for headlines and the big numbers, Manrope for everything you read.
abstract final class Txt {
  /// Off in tests, where nothing may touch the network.
  static bool useGoogleFonts = true;

  static TextStyle display(
    double size, {
    Color color = Palette.ink,
    double height = 1.0,
    FontWeight weight = FontWeight.w700,
    double? spacing,
  }) {
    final base = TextStyle(
      fontSize: size,
      height: height,
      letterSpacing: spacing ?? -0.03 * size,
      color: color,
      fontWeight: weight,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return useGoogleFonts ? GoogleFonts.unbounded(textStyle: base) : base;
  }

  static TextStyle text(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = Palette.ink,
    double height = 1.3,
    double spacing = 0,
  }) {
    final base = TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return useGoogleFonts ? GoogleFonts.manrope(textStyle: base) : base;
  }

  static TextStyle label(double size, {Color color = Palette.muted}) =>
      text(size, weight: FontWeight.w800, color: color, spacing: 1.4);
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
