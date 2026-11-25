import 'package:material_ui/material_ui.dart';

import '../brand/tokens.dart';
import '../data/timetable.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';
import 'line.dart';
import 'routes.dart';

Future<void> showTrainSheet(BuildContext context, Departure d) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: const Color(0x00000000),
  barrierColor: const Color(0x99000000),
  builder: (_) => TrainSheet(departure: d),
);

/// One train's run: every stop and time, with the train's place on it now.
class TrainSheet extends StatefulWidget {
  const TrainSheet({super.key, required this.departure});
  final Departure departure;

  @override
  State<TrainSheet> createState() => _TrainSheetState();
}

class _TrainSheetState extends State<TrainSheet> {
  bool _scrolled = false;

  /// Brings the stop the train is at (or your stop, if it has not left) into view, once.
  void _scrollTo(ScrollController scroll, int row) {
    if (_scrolled) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      final target = ((row - 2) * 52.0).clamp(0.0, scroll.position.maxScrollExtent);
      scroll.animateTo(target, duration: Motion.of(context, Motion.slow), curve: Motion.out);
    });
  }

  @override
  Widget build(BuildContext context) {
    final departure = widget.departure;
    final state = TransitScope.of(context);
    final tt = state.timetable;
    final d = departure;
    final t = d.train;
    final line = tt.lineOf(t);
    final c = Color(line.color);
    final dayOffset = d.at - t.times[d.stop];
    return DraggableScrollableSheet(
      initialChildSize: .72,
      maxChildSize: .94,
      minChildSize: .4,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 42,
              height: 5,
              decoration: BoxDecoration(color: Palette.line, borderRadius: BorderRadius.circular(9)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      LineChip(line),
                      const SizedBox(width: 8),
                      if (!t.estimated) Text('Train ${t.number}', style: Txt.label(11)),
                      const Spacer(),
                      ...trainTags(d).expand((w) => [w, const SizedBox(width: 4)]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${tt.stations[t.origin].name} → ${tt.stations[t.destination].name}',
                    style: Txt.display(22, height: 1.15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.estimated
                        ? 'Every ${line.service!.headwayAt(t.start) ?? line.service!.offpeak} min. Times are estimates.'
                        : '${t.stations.length} stops · ${(t.end - t.start).round()} min end to end',
                    style: Txt.text(13.5, color: Palette.muted, weight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<Moment>(
                valueListenable: state.clock.frame,
                builder: (context, now, _) {
                  // Minutes since this run's service-day midnight.
                  final since = now.minute - dayOffset;
                  final (seg, p) = interpolate(t.times, since);
                  _scrollTo(scroll, since >= t.start ? seg : d.stop);
                  final started = since >= t.start;
                  final ended = since >= t.end;
                  return ListView.builder(
                    controller: scroll,
                    padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.paddingOf(context).bottom + 90),
                    itemCount: t.stations.length,
                    itemBuilder: (context, i) {
                      final passed = started && (i < seg || (i == seg && p > 0) || ended);
                      final here = started && !ended && i == seg && p == 0;
                      final mine = i == d.stop;
                      return _StopRow(
                        name: tt.stations[t.stations[i]].name,
                        time: clock(t.times[i]),
                        platform: t.platformAt(i),
                        color: c,
                        first: i == 0,
                        last: i == t.stations.length - 1,
                        passed: passed,
                        here: here,
                        mine: mine,
                        // The train between this stop and the next.
                        progress: started && !ended && i == seg && p > 0 ? p : null,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ).withButton(
      context,
      label: 'Watch it on the line',
      onTap: () {
        Navigator.of(context).pop();
        Navigator.of(context).push(slideUp(LineScreen(line: t.line, branch: t.branch, follow: t.id)));
      },
    );
  }
}

extension on Widget {
  Widget withButton(BuildContext context, {required String label, required VoidCallback onTap}) => Stack(
    children: [
      this,
      Positioned(
        left: 20,
        right: 20,
        bottom: MediaQuery.paddingOf(context).bottom + 18,
        child: Pressable(
          onTap: onTap,
          label: label,
          child: Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Palette.signal,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(color: Palette.signal.withValues(alpha: .3), blurRadius: 24, offset: const Offset(0, 8)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timeline_rounded, color: Palette.signalInk),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Txt.text(16, weight: FontWeight.w800, color: Palette.signalInk),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.name,
    required this.time,
    required this.platform,
    required this.color,
    required this.first,
    required this.last,
    required this.passed,
    required this.here,
    required this.mine,
    required this.progress,
  });
  final String name, time;
  final String? platform;
  final Color color;
  final bool first, last, passed, here, mine;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    const h = 52.0;
    return SizedBox(
      height: h,
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(
              time,
              style: Txt.text(14, weight: FontWeight.w800, color: passed ? Palette.faint : Palette.ink),
            ),
          ),
          SizedBox(
            width: 30,
            height: h,
            child: CustomPaint(painter: _TrackPainter(color, first, last, passed, here, progress)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: Txt.text(
                mine ? 16 : 15,
                weight: mine ? FontWeight.w800 : FontWeight.w600,
                color: passed ? Palette.faint : (mine ? Palette.signal : Palette.ink),
              ),
            ),
          ),
          if (platform != null) Text('PF $platform', style: Txt.label(10.5, color: Palette.faint)),
        ],
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.c, this.first, this.last, this.passed, this.here, this.progress);
  final Color c;
  final bool first, last, passed, here;
  final double? progress;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2, mid = size.height / 2;
    final track = Paint()
      ..color = c
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final done = Paint()
      ..color = c.withValues(alpha: .3)
      ..strokeWidth = 5;
    if (!first) canvas.drawLine(Offset(x, 0), Offset(x, mid), passed || here ? done : track);
    if (!last) canvas.drawLine(Offset(x, mid), Offset(x, size.height), passed && progress == null ? done : track);
    canvas.drawCircle(Offset(x, mid), 7, Paint()..color = passed ? c.withValues(alpha: .35) : c);
    canvas.drawCircle(Offset(x, mid), 4, Paint()..color = Palette.surface);
    final p = progress;
    if (here || p != null) {
      final y = here ? mid : mid + (size.height) * p!;
      canvas.drawCircle(Offset(x, y), 13, Paint()..color = c.withValues(alpha: .3));
      canvas.drawCircle(Offset(x, y), 8, Paint()..color = Palette.ink);
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(_TrackPainter o) => o.progress != progress || o.passed != passed || o.here != here || o.c != c;
}
