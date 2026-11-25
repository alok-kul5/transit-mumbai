import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../brand/tokens.dart';
import '../data/timetable.dart';

/// Shrinks a touch while pressed, springs back on release.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = .96, this.label});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final String? label;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Motion.of(context, _down ? Motion.quick : Motion.base),
          curve: _down ? Curves.easeOut : Motion.spring,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Fades and rises into place after [delay]; lists use it for a stagger.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.delay = Duration.zero, this.dy = 18, this.play = true});
  final Widget child;
  final Duration delay;
  final double dy;
  final bool play;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.slow);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) _c.value = 1;
    _maybeStart();
  }

  @override
  void didUpdateWidget(Reveal old) {
    super.didUpdateWidget(old);
    _maybeStart();
  }

  void _maybeStart() {
    if (_started || !widget.play) return;
    _started = true;
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Motion.out.transform(_c.value);
        return Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.translate(offset: Offset(0, (1 - t) * widget.dy), child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// A line's badge: its colour and short name.
class LineChip extends StatelessWidget {
  const LineChip(this.line, {super.key, this.small = false, this.onTap, this.selected = true});
  final Line line;
  final bool small;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Color(line.color);
    final chip = AnimatedContainer(
      duration: Motion.of(context, Motion.base),
      curve: Motion.out,
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 11, vertical: small ? 3 : 6),
      decoration: BoxDecoration(
        color: selected ? c : c.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.withValues(alpha: selected ? 1 : .5)),
      ),
      child: Text(
        line.metro ? line.id : line.name,
        style: Txt.text(small ? 10.5 : 12.5, weight: FontWeight.w800, color: selected ? _inkOn(c) : c, height: 1.1),
      ),
    );
    return onTap == null ? chip : Pressable(onTap: onTap, label: '${line.name} line', child: chip);
  }
}

Color _inkOn(Color c) => c.computeLuminance() > .35 ? Palette.signalInk : Colors.white;

/// Small capsules for train facts: FAST, AC, LADIES, EST.
class Tag extends StatelessWidget {
  const Tag(this.text, this.color, {super.key, this.filled = false});
  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
    decoration: BoxDecoration(
      color: filled ? color : color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(text, style: Txt.label(9.5, color: filled ? _inkOn(color) : color).copyWith(letterSpacing: .8)),
  );
}

/// The tags a departure deserves.
List<Widget> trainTags(Departure d, {bool compact = false}) => [
  if (d.train.fast) const Tag('FAST', Palette.signal, filled: true),
  if (!d.train.estimated && !d.train.fast) const Tag('SLOW', Palette.muted),
  if (d.ac && !d.train.estimated) const Tag('AC', Palette.ac),
  if (d.ladies) const Tag('LADIES', Palette.ladies),
  if (d.train.estimated && !compact) const Tag('EST', Palette.muted),
];

/// A countdown whose digits roll as they change, like a platform indicator.
class Countdown extends StatelessWidget {
  const Countdown(this.minutes, {super.key, this.size = 44, this.color = Palette.ink, this.showSeconds = true});
  final double minutes;
  final double size;
  final Color color;
  final bool showSeconds;

  @override
  Widget build(BuildContext context) {
    if (minutes < .5) return _Now(size: size);
    final secs = (minutes * 60).floor();
    final String text;
    final String unit;
    if (secs >= 3600) {
      text = '${secs ~/ 3600}:${((secs % 3600) ~/ 60).toString().padLeft(2, '0')}';
      unit = 'h';
    } else if (showSeconds && secs < 600) {
      text = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
      unit = '';
    } else {
      text = '${(secs / 60).ceil()}';
      unit = 'min';
    }
    final style = Txt.display(size, color: color, weight: FontWeight.w700);
    return Semantics(
      label: '${(minutes).ceil()} minutes',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          for (final (i, ch) in text.split('').indexed) _RollingChar(ch, style, key: ValueKey('$i${text.length}')),
          if (unit.isNotEmpty) ...[
            SizedBox(width: size * .12),
            Text(
              unit,
              style: Txt.text(size * .34, weight: FontWeight.w700, color: color.withValues(alpha: .7)),
            ),
          ],
        ],
      ),
    );
  }
}

class _RollingChar extends StatelessWidget {
  const _RollingChar(this.ch, this.style, {super.key});
  final String ch;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (ch == ':') return Text(ch, style: style);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: Motion.of(context, Motion.base),
        switchInCurve: Motion.out,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) {
          final incoming = child.key == ValueKey(ch);
          return SlideTransition(
            position: Tween(begin: Offset(0, incoming ? .9 : -.9), end: Offset.zero).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          );
        },
        layoutBuilder: (current, previous) => Stack(alignment: Alignment.center, children: [...previous, ?current]),
        child: Text(ch, key: ValueKey(ch), style: style),
      ),
    );
  }
}

class _Now extends StatefulWidget {
  const _Now({required this.size});
  final double size;

  @override
  State<_Now> createState() => _NowState();
}

class _NowState extends State<_Now> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: .45, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: Text('Now', style: Txt.display(widget.size, color: Palette.signal)),
  );
}

/// A ring that empties as the train gets closer, for the hero countdown.
class ApproachRing extends StatelessWidget {
  const ApproachRing({super.key, required this.minutes, required this.color, this.size = 64, this.span = 10});
  final double minutes;
  final double span;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _RingPainter((1 - (minutes / span)).clamp(0.0, 1.0), color));
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = color.withValues(alpha: .16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      math.pi * 2 * t,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    // The train itself, riding the ring.
    final a = -math.pi / 2 + math.pi * 2 * t;
    canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r, 6.5, Paint()..color = Palette.ink);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t || old.color != color;
}

/// Rebuilds once a second of app time.
class EverySecond extends StatelessWidget {
  const EverySecond({super.key, required this.clock, required this.builder});
  final ValueNotifier<int> clock;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<int>(valueListenable: clock, builder: (context, _, _) => builder(context));
}

/// "4 min walk", "1.2 km".
String walk(double km) {
  if (km < 1.2) return '${(km * 1000 / 80).ceil().clamp(1, 99)} min walk';
  return '${km.toStringAsFixed(1)} km';
}
