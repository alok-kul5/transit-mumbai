// Draws the app icons from the same painter the app uses.
// Run: flutter test tool/make_icons_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:transit/brand/logo.dart';
import 'package:transit/brand/tokens.dart';

Future<List<int>> _icon(int px, {double mark = .62, bool rounded = false, bool transparent = false}) async {
  final rec = ui.PictureRecorder();
  final s = px.toDouble();
  final canvas = Canvas(rec);
  final rect = Offset.zero & Size(s, s);
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Palette.rakeHi, Palette.rakeDeep],
    ).createShader(rect);
  if (transparent) {
    // Adaptive-icon foreground: the launcher supplies the background.
  } else if (rounded) {
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(s * .23)), bg);
  } else {
    canvas.drawRect(rect, bg);
  }
  final m = s * mark;
  TransitMarkPainter.paintMark(canvas, Rect.fromCenter(center: rect.center, width: m, height: m), 1);
  final img = await rec.endRecording().toImage(px, px);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<int> _sizeOf(File f) async {
  final codec = await ui.instantiateImageCodec(await f.readAsBytes());
  return (await codec.getNextFrame()).image.width;
}

void main() {
  testWidgets('write icons', (tester) async {
    Txt.useGoogleFonts = false;
    await tester.runAsync(() async {
      Future<void> write(
        String path,
        int px, {
        double mark = .62,
        bool rounded = false,
        bool transparent = false,
      }) async {
        File(path).writeAsBytesSync(await _icon(px, mark: mark, rounded: rounded, transparent: transparent));
      }

      await write('web/favicon.png', 64, mark: .7, rounded: true);
      await write('web/icons/Icon-192.png', 192, rounded: true);
      await write('web/icons/Icon-512.png', 512, rounded: true);
      await write('web/icons/Icon-maskable-192.png', 192, mark: .5);
      await write('web/icons/Icon-maskable-512.png', 512, mark: .5);
      const android = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
      for (final e in android.entries) {
        await write('android/app/src/main/res/mipmap-${e.key}/ic_launcher.png', e.value, rounded: true);
        // 108 dp canvas, mark inside the 66 dp safe zone.
        await write(
          'android/app/src/main/res/mipmap-${e.key}/ic_launcher_foreground.png',
          e.value * 108 ~/ 48,
          mark: .42,
          transparent: true,
        );
      }
      for (final f in Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset').listSync().whereType<File>()) {
        if (!f.path.endsWith('.png')) continue;
        await write(f.path, await _sizeOf(f));
      }
      Directory('docs/brand').createSync(recursive: true);
      await write('docs/brand/icon-1024.png', 1024, rounded: true);
    });
  });
}
