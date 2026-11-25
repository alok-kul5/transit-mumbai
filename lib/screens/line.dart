import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../brand/tokens.dart';
import '../data/timetable.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';
import 'time_sheet.dart';
import 'train_sheet.dart';

const _rowH = 58.0;
const _trackA = 62.0; // trains running along the branch
const _trackB = 92.0; // trains running back
const _labelX = 122.0;

/// "Where's my train": a line drawn as a diagram, with every train on it
/// gliding between stations in time with the schedule.
class LineScreen extends StatefulWidget {
  const LineScreen({super.key, required this.line, this.branch = 0, this.follow});
  final int line;
  final int branch;

  /// A train to keep in view and mark.
  final int? follow;

  @override
  State<LineScreen> createState() => _LineScreenState();
}

class _LineScreenState extends State<LineScreen> with SingleTickerProviderStateMixin {
  late int _branch = widget.branch;
  final _scroll = ScrollController();
  late final _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  bool _scrolled = false;

  @override
  void dispose() {
    _scroll.dispose();
    _enter.dispose();
    super.dispose();
  }

  void _scrollToFollowed(TransitState state) {
    if (_scrolled || widget.follow == null) return;
    _scrolled = true;
    final t = state.timetable.trains[widget.follow!];
    final p = state.timetable.positionOf(t, state.clock.now, branch: _branch);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final idx = p == null
          ? state.timetable.branchIndices(t, _branch).first
          : state.timetable.branchIndices(t, _branch)[p.stop];
      final target = (idx * _rowH - 180).clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(target, duration: Motion.of(context, Motion.slow), curve: Motion.out);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = TransitScope.of(context);
    final tt = state.timetable;
    final line = tt.lines[widget.line];
    final b = line.branches[_branch];
    final c = Color(line.color);
    final top = MediaQuery.paddingOf(context).top;
    _scrollToFollowed(state);
    return Scaffold(
      backgroundColor: Palette.field,
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(
            child: Hero(
              tag: 'line-${line.id}',
              flightShuttleBuilder: (_, anim, _, _, _) => LineShuttle(anim: anim, color: Color(line.color)),
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding: EdgeInsets.fromLTRB(18, top + 8, 18, 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color.lerp(Palette.field, c, .45)!, Palette.field],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Back',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back_rounded, color: Palette.ink),
                          ),
                          const Spacer(),
                          TimeReadout(clock: state.clock, onTap: () => showTimeSheet(context)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text("Where's my train", style: Txt.note(17, color: Palette.ink.withValues(alpha: .8))),
                      const SizedBox(height: 6),
                      Text(line.metro ? line.name : '${line.name} line', style: Txt.display(36)),
                      const SizedBox(height: 12),
                      if (line.branches.length > 1)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (i, br) in line.branches.indexed)
                              Pressable(
                                onTap: () => setState(() => _branch = i),
                                label: br.name,
                                child: AnimatedContainer(
                                  duration: Motion.of(context, Motion.base),
                                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: i == _branch ? c : Palette.card.withValues(alpha: .7),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    br.name,
                                    style: Txt.text(
                                      13,
                                      weight: FontWeight.w800,
                                      color: i == _branch ? Palette.signalInk : Palette.ink,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        )
                      else
                        Text(
                          b.name,
                          style: Txt.text(15, weight: FontWeight.w700, color: Palette.ink),
                        ),
                      const SizedBox(height: 14),
                      ValueListenableBuilder<int>(
                        valueListenable: state.clock.second,
                        builder: (context, _, _) {
                          final n = tt.running(state.clock.now, line: widget.line, branch: _branch).length;
                          return Row(
                            children: [
                              Text('$n', style: Txt.display(26, color: c)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  n == 1 ? 'train on this stretch now' : 'trains on this stretch now',
                                  style: Txt.text(13.5, weight: FontWeight.w700, color: Palette.muted),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: Palette.field.withValues(alpha: .6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule_rounded, size: 14, color: Palette.signal),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                line.metro
                                    ? 'Estimated from the published frequency. Not live GPS.'
                                    : 'Positions follow the timetable. Not live GPS.',
                                style: Txt.text(12, weight: FontWeight.w700, color: Palette.muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _Legend(branch: b, stations: tt.stations, color: c),
          ),
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.base),
              child: _Diagram(
                key: ValueKey(_branch),
                state: state,
                line: line,
                branch: _branch,
                follow: widget.follow,
                enter: _enter,
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 40)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.branch, required this.stations, required this.color});
  final Branch branch;
  final List<Station> stations;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final end = stations[branch.stations.last].name;
    final start = stations[branch.stations.first].name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      child: Row(
        children: [
          _Arrow(down: true, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text('to $end', style: Txt.text(12.5, weight: FontWeight.w800), maxLines: 1),
          ),
          const SizedBox(width: 16),
          _Arrow(down: false, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text('to $start', style: Txt.text(12.5, weight: FontWeight.w800), maxLines: 1),
          ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.down, required this.color});
  final bool down;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(color: color.withValues(alpha: .18), borderRadius: BorderRadius.circular(7)),
    child: Icon(down ? Icons.south_rounded : Icons.north_rounded, size: 14, color: color),
  );
}

class _Diagram extends StatelessWidget {
  const _Diagram({
    super.key,
    required this.state,
    required this.line,
    required this.branch,
    required this.follow,
    required this.enter,
  });
  final TransitState state;
  final Line line;
  final int branch;
  final int? follow;
  final Animation<double> enter;

  @override
  Widget build(BuildContext context) {
    final tt = state.timetable;
    final b = line.branches[branch];
    final height = b.stations.length * _rowH + 20;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          // Station names, staggered in.
          for (final (i, id) in b.stations.indexed)
            Positioned(
              left: _labelX,
              right: 16,
              top: 10 + i * _rowH,
              height: _rowH,
              child: Reveal(
                delay: Duration(milliseconds: 15 * i.clamp(0, 30)),
                dy: 8,
                child: _StationLabel(station: tt.stations[id], lines: tt.lines),
              ),
            ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (e) => _tap(context, e.localPosition),
              child: AnimatedBuilder(
                animation: Listenable.merge([state.clock.frame, enter]),
                builder: (context, _) => CustomPaint(
                  painter: _DiagramPainter(
                    branch: b,
                    color: Color(line.color),
                    positions: tt.running(state.clock.frame.value, line: line.index, branch: branch),
                    tt: tt,
                    follow: follow,
                    enter: Motion.out.transform(enter.value),
                    pulse: (DateTime.now().millisecondsSinceEpoch % 1400) / 1400,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _tap(BuildContext context, Offset at) {
    final tt = state.timetable;
    final positions = tt.running(state.clock.now, line: line.index, branch: branch);
    Position? best;
    var bestD = 30.0;
    for (final p in positions) {
      final o = _offsetOf(p, tt, branch);
      final d = (o - at).distance;
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    if (best == null) return;
    final t = best.train;
    final stop = math.min(best.stop + (best.atPlatform ? 0 : 1), t.stations.length - 1);
    final now = state.clock.now;
    final off = best.weekday == now.weekday ? 0 : -1440;
    final when = t.times[stop] + off;
    showTrainSheet(context, Departure(t, stop, when, when - now.minute, best.weekday));
  }
}

Offset _offsetOf(Position p, Timetable tt, int branch) {
  final idx = tt.branchIndices(p.train, branch);
  final a = idx[p.stop].toDouble();
  final bIdx = idx[math.min(p.stop + 1, idx.length - 1)].toDouble();
  final y = 10 + (a + (bIdx - a) * p.progress) * _rowH + _rowH / 2;
  return Offset(p.forward ? _trackA : _trackB, y);
}

class _StationLabel extends StatelessWidget {
  const _StationLabel({required this.station, required this.lines});
  final Station station;
  final List<Line> lines;

  @override
  Widget build(BuildContext context) {
    final interchange = station.lines.length > 1 || station.links.isNotEmpty;
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Flexible(
            child: Text(
              station.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Txt.text(interchange ? 16 : 15, weight: interchange ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
          if (interchange) ...[
            const SizedBox(width: 8),
            for (final l in station.lines.where((l) => l != station.lines.first).take(2)) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: Color(lines[l].color), shape: BoxShape.circle),
              ),
              const SizedBox(width: 3),
            ],
            if (station.links.isNotEmpty) const Icon(Icons.directions_walk_rounded, size: 13, color: Palette.faint),
          ],
        ],
      ),
    );
  }
}

class _DiagramPainter extends CustomPainter {
  _DiagramPainter({
    required this.branch,
    required this.color,
    required this.positions,
    required this.tt,
    required this.follow,
    required this.enter,
    required this.pulse,
  });
  final Branch branch;
  final Color color;
  final List<Position> positions;
  final Timetable tt;
  final int? follow;
  final double enter;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final n = branch.stations.length;
    final top = 10 + _rowH / 2;
    final bottom = 10 + (n - 1) * _rowH + _rowH / 2;
    // The tracks draw themselves down the screen on entry.
    final reach = top + (bottom - top) * enter;
    for (final x in const [_trackA, _trackB]) {
      canvas.drawLine(
        Offset(x, top),
        Offset(x, reach),
        Paint()
          ..color = color.withValues(alpha: .10)
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(x, top),
        Offset(x, reach),
        Paint()
          ..color = color.withValues(alpha: .85)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
    for (var i = 0; i < n; i++) {
      final y = 10 + i * _rowH + _rowH / 2;
      if (y > reach + 1) break;
      final s = tt.stations[branch.stations[i]];
      final interchange = s.lines.length > 1 || s.links.isNotEmpty;
      if (interchange) {
        // An interchange: a white bar across both tracks, like a printed diagram.
        final bar = RRect.fromRectAndRadius(
          Rect.fromLTRB(_trackA - 8, y - 6, _trackB + 8, y + 6),
          const Radius.circular(6),
        );
        canvas.drawRRect(bar, Paint()..color = Palette.ink);
        canvas.drawRRect(
          bar,
          Paint()
            ..color = Palette.field
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      } else {
        // An ordinary stop: a small tick on each track.
        for (final x in const [_trackA, _trackB]) {
          canvas.drawCircle(Offset(x, y), 4.2, Paint()..color = Palette.field);
          canvas.drawCircle(
            Offset(x, y),
            4.2,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
      }
      canvas.drawLine(
        Offset(_trackB + 12, y),
        Offset(_labelX - 8, y),
        Paint()
          ..color = Palette.line
          ..strokeWidth = 1.2,
      );
    }
    if (enter < .95) return;
    Position? followed;
    for (final p in positions) {
      if (p.train.id == follow) {
        followed = p;
        continue;
      }
      _train(canvas, p, false);
    }
    if (followed != null) _train(canvas, followed, true);
  }

  void _train(Canvas canvas, Position p, bool followed) {
    final o = _offsetOf(p, tt, tt.lines[p.train.line].branches.indexOf(branch));
    final fast = p.train.fast;
    final body = fast ? Palette.signal : Palette.ink;
    if (followed) {
      canvas.drawCircle(o, 18 + 10 * pulse, Paint()..color = Palette.signal.withValues(alpha: .35 * (1 - pulse)));
    }
    // Soft glow in the line colour.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 26, height: 36), const Radius.circular(13)),
      Paint()..color = color.withValues(alpha: .25),
    );
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 16, height: 26), const Radius.circular(8));
    canvas.drawRRect(r, Paint()..color = body);
    canvas.drawRRect(
      r,
      Paint()
        ..color = p.train.acOn(p.weekday) && !p.train.estimated ? Palette.ac : color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6,
    );
    // Nose: a small arrow at the front.
    final dir = p.forward ? 1.0 : -1.0;
    final nose = Path()
      ..moveTo(o.dx - 4, o.dy + dir * 4)
      ..lineTo(o.dx, o.dy + dir * 9)
      ..lineTo(o.dx + 4, o.dy + dir * 4)
      ..close();
    canvas.drawPath(nose, Paint()..color = fast ? Palette.signalInk : color);
    if (p.train.ladiesOn(p.weekday)) {
      canvas.drawCircle(o + Offset(0, -dir * 6), 3, Paint()..color = Palette.ladies);
    }
  }

  @override
  bool shouldRepaint(_DiagramPainter old) => true;
}

/// What flies between a line tile and this header: the card stretches,
/// loses its corners and floods with the line's colour.
class LineShuttle extends StatelessWidget {
  const LineShuttle({super.key, required this.anim, required this.color});
  final Animation<double> anim;
  final Color color;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: anim,
    builder: (context, _) {
      final t = Motion.out.transform(anim.value);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20 * (1 - t)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(Palette.card, Color.lerp(Palette.field, color, .45)!, t)!,
              Color.lerp(Palette.card, Palette.field, t)!,
            ],
          ),
        ),
      );
    },
  );
}
