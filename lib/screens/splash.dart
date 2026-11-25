import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../brand/logo.dart';
import '../brand/tokens.dart';

/// The load sequence, in three beats:
///   1. On local-train maroon, the network draws itself as a line diagram and
///      a train runs down each line.
///   2. The mark draws in the middle and the wordmark rises letter by letter.
///   3. The screen slides open from the centre like a local's doors, onto the
///      map, which starts its own entrance at that moment.
/// Tap to skip to the doors.
class Splash extends StatefulWidget {
  const Splash({super.key, required this.onReveal, required this.onDone});

  /// When the map underneath should start its own entrance.
  final VoidCallback onReveal;
  final VoidCallback onDone;

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 3300);
  late final _c = AnimationController(vsync: this, duration: _total);
  bool _revealed = false;

  static const _doorsAt = .70;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_revealed && _c.value >= _doorsAt) {
        _revealed = true;
        widget.onReveal();
      }
    });
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_c.isAnimating && !_c.isCompleted) {
      if (Motion.reduced(context)) _c.duration = const Duration(milliseconds: 700);
      _c.forward();
    }
  }

  void _skip() {
    if (_c.value < _doorsAt) _c.value = _doorsAt;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _iv(double a, double b, [Curve curve = Curves.linear]) =>
      curve.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _skip,
      behavior: HitTestBehavior.opaque,
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final w = box.maxWidth, h = box.maxHeight;
            final doors = _iv(_doorsAt, 1, Curves.easeInOutCubic);
            final face = _Face(
              size: Size(w, h),
              network: _iv(0, .42),
              trains: _iv(.12, .74),
              mark: _iv(.14, .40),
              word: _iv(.30, .52),
              tag: _iv(.44, .58, Motion.out),
              settle: _iv(.56, .70, Curves.easeOut),
            );
            if (doors == 0) return face;
            final dx = w / 2 * doors;
            // Two halves of the same picture, each sliding into the wall.
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: -dx,
                  top: 0,
                  width: w / 2,
                  height: h,
                  child: _Door(left: true, open: doors, full: Size(w, h), child: face),
                ),
                Positioned(
                  left: w / 2 + dx,
                  top: 0,
                  width: w / 2,
                  height: h,
                  child: _Door(left: false, open: doors, full: Size(w, h), child: face),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One door: half of the face, with a cream edge where the doors meet and the
/// shadow it throws on the platform behind.
class _Door extends StatelessWidget {
  const _Door({required this.left, required this.open, required this.full, required this.child});
  final bool left;
  final double open;
  final Size full;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ClipRect(
            child: OverflowBox(
              alignment: left ? Alignment.topLeft : Alignment.topRight,
              minWidth: full.width,
              maxWidth: full.width,
              child: child,
            ),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: left ? null : -30,
          right: left ? -30 : null,
          width: 30,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: left ? Alignment.centerLeft : Alignment.centerRight,
                  end: left ? Alignment.centerRight : Alignment.centerLeft,
                  colors: [
                    Colors.black.withValues(alpha: .5 * (1 - open)),
                    Colors.black.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: left ? null : 0,
          right: left ? 0 : null,
          width: 4,
          child: const ColoredBox(color: Palette.signal),
        ),
      ],
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({
    required this.size,
    required this.network,
    required this.trains,
    required this.mark,
    required this.word,
    required this.tag,
    required this.settle,
  });
  final Size size;
  final double network, trains, mark, word, tag, settle;

  @override
  Widget build(BuildContext context) {
    const markSize = 128.0;
    final center = Offset(size.width / 2, size.height * .40);
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _NetworkPainter(network, trains, settle))),
          if (mark > 0)
            Positioned(
              left: center.dx - markSize / 2,
              top: center.dy - markSize / 2,
              child: SizedBox.square(
                dimension: markSize,
                child: CustomPaint(painter: _MarkPainter(mark)),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: center.dy + markSize / 2 + 18,
            child: Column(
              children: [
                _Wordmark(t: word),
                const SizedBox(height: 10),
                Opacity(
                  opacity: tag,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - tag)),
                    child: Text('Mumbai locals & metro', style: Txt.note(19, color: Palette.signal)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    const word = 'Transit';
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < word.length; i++)
            Builder(
              builder: (context) {
                final a = ((t - i * .07) / .5).clamp(0.0, 1.0);
                final e = Motion.out.transform(a);
                return Opacity(
                  opacity: a,
                  child: Transform.translate(
                    offset: Offset(0, 34 * (1 - e)),
                    child: Text(
                      word[i],
                      style: Txt.display(62, weight: FontWeight.w600, color: Palette.ink),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) => TransitMarkPainter.paintMark(canvas, Offset.zero & size, t);

  @override
  bool shouldRepaint(_MarkPainter old) => old.t != t;
}

/// The network as a diagram: five lines in their own colours, drawn on with a
/// stagger, each with a cream train running down it.
class _NetworkPainter extends CustomPainter {
  _NetworkPainter(this.draw, this.run, this.settle);
  final double draw, run, settle;

  // Unit-square polylines, loosely after the real map: Western down the west
  // coast, Trans-Harbour down the east, the metro across the top and Central and
  // Harbour along the bottom, leaving the middle clear for the wordmark.
  static const _lines = <(int, List<Offset>)>[
    (0xFFFF6A3D, [Offset(.30, -.05), Offset(.30, .14), Offset(.12, .32), Offset(.12, 1.05)]),
    (0xFFC6F432, [Offset(1.05, .76), Offset(.72, .76), Offset(.52, .96), Offset(.52, 1.05)]),
    (0xFF2BD9A8, [Offset(-.05, .84), Offset(.22, .84), Offset(.34, .96), Offset(.34, 1.05)]),
    (0xFFF25CA2, [Offset(.88, -.05), Offset(.88, .30), Offset(.95, .37), Offset(.95, 1.05)]),
    (0xFF3E7BFF, [Offset(-.05, .20), Offset(.44, .20), Offset(.58, .06), Offset(1.05, .06)]),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * .5, size.height * .40),
          size.longestSide * .75,
          const [Palette.rakeHi, Palette.rake, Palette.rakeDeep],
          const [0, .45, 1],
        ),
    );
    Offset p(Offset u) => Offset(u.dx * size.width, u.dy * size.height);
    // The lines recede as the wordmark settles, so it reads.
    final fade = 1 - .5 * settle;
    for (final (i, (color, pts)) in _lines.indexed) {
      final path = Path()..moveTo(p(pts.first).dx, p(pts.first).dy);
      for (final u in pts.skip(1)) {
        path.lineTo(p(u).dx, p(u).dy);
      }
      final m = path.computeMetrics().first;
      final t = Curves.easeInOutCubic.transform(((draw - i * .09) / .6).clamp(0.0, 1.0));
      if (t <= 0) continue;
      final c = Color(color);
      final drawn = m.extractPath(0, m.length * t);
      canvas.drawPath(
        drawn,
        Paint()
          ..color = c.withValues(alpha: .16 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        drawn,
        Paint()
          ..color = c.withValues(alpha: .7 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      // Stations every so often.
      for (var d = 46.0; d < m.length * t; d += 74) {
        final at = m.getTangentForOffset(d)!.position;
        canvas.drawCircle(at, 5, Paint()..color = Palette.rakeDeep);
        canvas.drawCircle(
          at,
          5,
          Paint()
            ..color = Palette.ink.withValues(alpha: .75 * fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      // A train, leaving a short cream trail.
      final f = Curves.easeInOut.transform(((run - i * .08) / .7).clamp(0.0, 1.0));
      if (f > 0 && f < 1 && f < t) {
        final head = m.length * f;
        final trail = m.extractPath(math.max(0, head - 60), head);
        canvas.drawPath(
          trail,
          Paint()
            ..color = Palette.signal.withValues(alpha: .7 * fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
        final at = m.getTangentForOffset(head)!.position;
        canvas.drawCircle(at, 11, Paint()..color = Palette.signal.withValues(alpha: .25 * fade));
        canvas.drawCircle(at, 6, Paint()..color = Palette.signal);
      }
    }
  }

  @override
  bool shouldRepaint(_NetworkPainter old) => old.draw != draw || old.run != run || old.settle != settle;
}
