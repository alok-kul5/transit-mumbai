import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../brand/logo.dart';
import '../brand/tokens.dart';

/// The load sequence. The mark draws itself like a line on a map, a signal
/// runs down it, the wordmark rises letter by letter, then the end station
/// opens up into the map underneath. Tap to skip.
class Splash extends StatefulWidget {
  const Splash({super.key, required this.onReveal, required this.onDone});

  /// When the map underneath should start its own entrance.
  final VoidCallback onReveal;
  final VoidCallback onDone;

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 2900);
  late final _c = AnimationController(vsync: this, duration: _total);
  bool _revealed = false;

  static const _revealAt = .74;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_revealed && _c.value >= _revealAt) {
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
      if (Motion.reduced(context)) {
        _c.duration = const Duration(milliseconds: 600);
      }
      _c.forward();
    }
  }

  void _skip() {
    if (_c.value < _revealAt) _c.value = _revealAt;
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
    final size = MediaQuery.sizeOf(context);
    return GestureDetector(
      onTap: _skip,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final draw = _iv(.02, .34);
          final signal = _iv(.30, .52, Curves.easeInOutCubic);
          final word = _c.value;
          final tag = _iv(.50, .62, Motion.out);
          final reveal = _iv(_revealAt, 1, Curves.easeInCubic);
          const mark = 132.0;
          final center = Offset(size.width / 2, size.height * .42);
          // The hole opens from the mark's end station.
          final hole = center + const Offset(mark * .40, mark * -.10) * (1 + .5 * reveal);
          final maxR = math.sqrt(size.width * size.width + size.height * size.height);
          return ClipPath(
            clipper: _HoleClipper(hole, maxR * reveal),
            child: Container(
              color: Palette.field,
              child: Stack(
                children: [
                  // A faint grid of tracks behind everything.
                  Positioned.fill(child: CustomPaint(painter: _TracksPainter(_iv(0, .5, Motion.out)))),
                  Positioned(
                    left: center.dx - mark / 2,
                    top: center.dy - mark / 2,
                    child: Transform.scale(
                      scale: 1 + .5 * reveal,
                      child: SizedBox.square(
                        dimension: mark,
                        child: CustomPaint(painter: _SplashMarkPainter(draw, signal)),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: center.dy + mark / 2 + 26,
                    child: Opacity(
                      opacity: 1 - reveal,
                      child: Column(
                        children: [
                          _Wordmark(t: word),
                          const SizedBox(height: 14),
                          Opacity(
                            opacity: tag,
                            child: Transform.translate(
                              offset: Offset(0, 8 * (1 - tag)),
                              child: Text('MUMBAI LOCALS  ·  METRO', style: Txt.label(11.5, color: Palette.muted)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < word.length; i++)
          Builder(
            builder: (context) {
              final a = ((t - .30 - i * .028) / .16).clamp(0.0, 1.0);
              final e = Motion.out.transform(a);
              return Opacity(
                opacity: a,
                child: Transform.translate(
                  offset: Offset(0, 26 * (1 - e)),
                  child: Text(word[i], style: Txt.display(44, weight: FontWeight.w800)),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _SplashMarkPainter extends CustomPainter {
  _SplashMarkPainter(this.draw, this.signal);
  final double draw, signal;

  static const _pts = [Offset(.10, .74), Offset(.44, .74), Offset(.70, .40), Offset(.90, .40)];

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    TransitMarkPainter.paintMark(canvas, r, draw);
    if (signal <= 0 || signal >= 1) return;
    // A bright signal runs along the line, like a train on the diagram.
    final path = Path()..moveTo(_pts[0].dx * size.width, _pts[0].dy * size.height);
    for (final p in _pts.skip(1)) {
      path.lineTo(p.dx * size.width, p.dy * size.height);
    }
    final m = path.computeMetrics().first;
    final at = m.getTangentForOffset(m.length * signal)!.position;
    final trail = m.extractPath(math.max(0, m.length * signal - 34), m.length * signal);
    canvas.drawPath(
      trail,
      Paint()
        ..color = Colors.white.withValues(alpha: .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .06
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(at, size.width * .07, Paint()..color = Colors.white.withValues(alpha: .25));
    canvas.drawCircle(at, size.width * .04, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SplashMarkPainter old) => old.draw != draw || old.signal != signal;
}

/// Faint diagonal and level tracks, like a map diagram's grid.
class _TracksPainter extends CustomPainter {
  _TracksPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Palette.line.withValues(alpha: .35 * t)
      ..strokeWidth = 1;
    for (var y = -size.width; y < size.height + size.width; y += 46) {
      final dy = y + 30 * (1 - t);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy - size.width), p);
    }
  }

  @override
  bool shouldRepaint(_TracksPainter old) => old.t != t;
}

class _HoleClipper extends CustomClipper<Path> {
  _HoleClipper(this.center, this.radius);
  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_HoleClipper old) => old.radius != radius || old.center != center;
}
