import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// The Transit mark: a fragment of a line map. A yellow line leaves a station,
/// bends at 45 degrees like every good transit diagram, and arrives at a ring.
class TransitMark extends StatelessWidget {
  const TransitMark({super.key, this.size = 48, this.draw = 1, this.tile = true});
  final double size;

  /// 0..1: how much of the mark has drawn itself.
  final double draw;
  final bool tile;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _MarkPainter(draw, tile));
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.t, this.tile);
  final double t;
  final bool tile;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    if (tile) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(size.width * .24)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Palette.fieldHi, Palette.field],
          ).createShader(r),
      );
    }
    TransitMarkPainter.paintMark(canvas, tile ? r.deflate(size.width * .14) : r, t);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.t != t || old.tile != tile;
}

abstract final class TransitMarkPainter {
  /// Points of the line in a unit square.
  static const _pts = [Offset(.10, .74), Offset(.44, .74), Offset(.70, .40), Offset(.90, .40)];

  /// Draws the mark into [r]. [t] runs the draw-on: line, then the rings.
  static void paintMark(Canvas canvas, Rect r, double t, {Color line = Palette.signal, Color ring = Palette.ink}) {
    Offset p(Offset u) => Offset(r.left + u.dx * r.width, r.top + u.dy * r.height);
    final w = r.width;
    final path = Path()..moveTo(p(_pts[0]).dx, p(_pts[0]).dy);
    for (final u in _pts.skip(1)) {
      path.lineTo(p(u).dx, p(u).dy);
    }
    final lineT = (t / .7).clamp(0.0, 1.0);
    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * Curves.easeInOutCubic.transform(lineT));
    canvas.drawPath(
      drawn,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .15
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // Start station: a solid dot. End station: a ring, which pops when the line arrives.
    final a = Curves.easeOutBack.transform((t / .25).clamp(0.0, 1.0));
    canvas.drawCircle(p(_pts.first), w * .11 * a, Paint()..color = ring);
    canvas.drawCircle(p(_pts.first), w * .045 * a, Paint()..color = line);
    final b = Curves.easeOutBack.transform(((t - .62) / .38).clamp(0.0, 1.0));
    if (b > 0) {
      canvas.drawCircle(p(_pts.last), w * .14 * b, Paint()..color = ring);
      canvas.drawCircle(p(_pts.last), w * .065 * b, Paint()..color = Palette.field);
    }
  }

  /// The mark as a picture, for icons.
  static ui.Picture picture(double size) {
    final rec = ui.PictureRecorder();
    paintMark(Canvas(rec), Offset.zero & Size.square(size), 1);
    return rec.endRecording();
  }
}
