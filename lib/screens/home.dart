import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:material_ui/material_ui.dart';

import '../brand/logo.dart';
import '../brand/tokens.dart';
import '../data/timetable.dart';
import '../services/locate.dart';
import '../state/app_state.dart';
import '../widgets/transit_map.dart';
import '../widgets/ui.dart';
import 'line.dart';
import 'routes.dart';
import 'search.dart';
import 'station_panel.dart';
import 'time_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.introDone});
  final ValueNotifier<bool> introDone;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _map = MapController();
  late final _flyer = Flyer(_map, this);
  late final _draw = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));
  final _sheet = DraggableScrollableController();

  static const _overview = LatLng(19.06, 72.93);

  @override
  void initState() {
    super.initState();
    widget.introDone.addListener(_intro);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.introDone.value && _draw.value == 0 && !_draw.isAnimating) _intro();
  }

  void _intro() {
    if (!widget.introDone.value) return;
    if (Motion.reduced(context)) {
      _draw.value = 1;
      return;
    }
    _draw.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _flyer.to(_overview, 10.25, duration: const Duration(milliseconds: 1800));
    });
  }

  @override
  void dispose() {
    widget.introDone.removeListener(_intro);
    _flyer.dispose();
    _draw.dispose();
    _sheet.dispose();
    super.dispose();
  }

  TransitState get _state => TransitScope.read(context);

  /// Shows [id] on the map, a little above centre so the sheet does not cover it.
  void openStation(int id, {double zoom = 14}) {
    final s = _state.timetable.stations[id];
    _state.select(id);
    final h = MediaQuery.sizeOf(context).height;
    final mpp = 156543.03 * math.cos(s.lat * math.pi / 180) / math.pow(2, zoom);
    final shift = h * .22 * mpp / 111320;
    _flyer.to(LatLng(s.lat - shift, s.lng), zoom, reduced: Motion.reduced(context));
    if (_sheet.isAttached) {
      _sheet.animateTo(.52, duration: Motion.of(context, Motion.slow), curve: Motion.out);
    }
  }

  void _closeStation() {
    _state.select(null);
    _flyer.to(_overview, 10.25, reduced: Motion.reduced(context));
    if (_sheet.isAttached) _sheet.animateTo(.36, duration: Motion.of(context, Motion.slow), curve: Motion.out);
  }

  Future<void> _search() async {
    final id = await Navigator.of(context).push<int>(fadeThrough(const SearchScreen()));
    if (id != null && mounted) openStation(id);
  }

  Future<void> _locate() async {
    final state = _state;
    await locate(state);
    if (!mounted) return;
    if (state.here != null) {
      final near = state.nearby;
      if (near.isNotEmpty) openStation(near.first.$1.id, zoom: 14.5);
    } else if (state.locationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Palette.cardHi,
          content: Text(state.locationError!, style: Txt.text(14)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = TransitScope.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return PopScope(
      canPop: state.selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeStation();
      },
      child: Scaffold(
        backgroundColor: Palette.field,
        body: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _draw,
                builder: (context, _) => TransitMap(
                  state: state,
                  controller: _map,
                  draw: Curves.easeInOutCubic.transform(_draw.value),
                  onStation: openStation,
                ),
              ),
            ),
            // Fade the map under the status bar and top controls.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: top + 140,
              child: const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xF00B0D1A), Color(0x000B0D1A)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: top + 12,
              child: ValueListenableBuilder(
                valueListenable: widget.introDone,
                builder: (context, done, child) =>
                    Reveal(play: done, delay: const Duration(milliseconds: 200), child: child!),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const TransitMark(size: 30),
                        const SizedBox(width: 10),
                        Text('Transit', style: Txt.display(21, weight: FontWeight.w800)),
                        const Spacer(),
                        ClockPill(clock: state.clock, onTap: () => showTimeSheet(context)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SearchPill(onTap: _search, stations: state.timetable.stations.length),
                  ],
                ),
              ),
            ),
            _MapButtons(sheet: _sheet, locating: state.locating, onLocate: _locate),
            _Sheet(
              controller: _sheet,
              introDone: widget.introDone,
              onStation: openStation,
              onClose: _closeStation,
              onLocate: _locate,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onTap, required this.stations});
  final VoidCallback onTap;
  final int stations;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    scale: .98,
    label: 'Search stations',
    child: Hero(
      tag: 'search',
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: Palette.card.withValues(alpha: .92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Palette.line),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10))],
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: Palette.signal, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Search $stations stations',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.text(15.5, color: Palette.muted, weight: FontWeight.w600),
                ),
              ),
              Text('VT · ADH · TNA', style: Txt.label(10, color: Palette.faint)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MapButtons extends StatelessWidget {
  const _MapButtons({required this.sheet, required this.locating, required this.onLocate});
  final DraggableScrollableController sheet;
  final bool locating;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return AnimatedBuilder(
      animation: sheet,
      builder: (context, child) {
        final size = sheet.isAttached ? sheet.size : .36;
        return Positioned(
          right: 16,
          bottom: h * size + 14,
          child: Opacity(opacity: (1 - (size - .5) * 4).clamp(0.0, 1.0), child: child),
        );
      },
      child: Pressable(
        onTap: locating ? null : onLocate,
        label: 'Find my nearest station',
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Palette.signal,
            borderRadius: BorderRadius.circular(17),
            boxShadow: [
              BoxShadow(color: Palette.signal.withValues(alpha: .35), blurRadius: 22, offset: const Offset(0, 8)),
            ],
          ),
          child: locating
              ? const Padding(
                  padding: EdgeInsets.all(15),
                  child: CircularProgressIndicator(strokeWidth: 2.6, color: Palette.signalInk),
                )
              : const Icon(Icons.near_me_rounded, color: Palette.signalInk, size: 24),
        ),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.controller,
    required this.introDone,
    required this.onStation,
    required this.onClose,
    required this.onLocate,
  });
  final DraggableScrollableController controller;
  final ValueNotifier<bool> introDone;
  final ValueChanged<int> onStation;
  final VoidCallback onClose;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    final state = TransitScope.of(context);
    return ValueListenableBuilder(
      valueListenable: introDone,
      builder: (context, done, child) => AnimatedSlide(
        offset: done ? Offset.zero : const Offset(0, 1),
        duration: Motion.of(context, const Duration(milliseconds: 900)),
        curve: Motion.out,
        child: child,
      ),
      child: DraggableScrollableSheet(
        controller: controller,
        initialChildSize: .36,
        minChildSize: .14,
        maxChildSize: .94,
        snap: true,
        snapSizes: const [.36, .52],
        builder: (context, scroll) => DecoratedBox(
          decoration: const BoxDecoration(
            color: Palette.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, -6))],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            // One list owns the sheet's scroll controller; only its content cross-fades.
            child: ListView(
              controller: scroll,
              padding: EdgeInsets.fromLTRB(18, 0, 18, MediaQuery.paddingOf(context).bottom + 28),
              children: [
                const SheetHandle(),
                AnimatedSwitcher(
                  duration: Motion.of(context, Motion.base),
                  switchInCurve: Motion.out,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      for (final p in previous) Positioned(left: 0, right: 0, top: 0, child: p),
                      ?current,
                    ],
                  ),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: state.selected == null
                      ? _Overview(key: const ValueKey('overview'), onStation: onStation, onLocate: onLocate)
                      : StationPanel(
                          key: ValueKey(state.selected),
                          station: state.selected!,
                          onClose: onClose,
                          onStation: onStation,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      width: 42,
      height: 5,
      decoration: BoxDecoration(color: Palette.line, borderRadius: BorderRadius.circular(9)),
    ),
  );
}

class _Overview extends StatelessWidget {
  const _Overview({super.key, required this.onStation, required this.onLocate});
  final ValueChanged<int> onStation;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    final state = TransitScope.of(context);
    final tt = state.timetable;
    var i = 0;
    Duration d() => Duration(milliseconds: 80 + 60 * i++);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Reveal(
          delay: d(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text('Next trains', style: Txt.display(27))),
              const _ScheduleBadge(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (state.here == null)
          Reveal(
            delay: d(),
            child: _LocateCard(onTap: onLocate, busy: state.locating),
          )
        else
          for (final (s, km) in state.nearby.take(2))
            Reveal(
              delay: d(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: NextTrainCard(station: s, note: walk(km), onTap: () => onStation(s.id), nearby: true),
              ),
            ),
        if (state.favourites.isNotEmpty) ...[
          const SizedBox(height: 18),
          Reveal(delay: d(), child: const _SectionLabel('Your stations')),
          const SizedBox(height: 10),
          for (final id in state.favourites)
            Reveal(
              delay: d(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: NextTrainCard(station: tt.stations[id], onTap: () => onStation(id)),
              ),
            ),
        ] else ...[
          const SizedBox(height: 12),
          Reveal(
            delay: d(),
            child: Text(
              'Star a station and its next train lives here.',
              style: Txt.text(13.5, color: Palette.faint, weight: FontWeight.w600),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Reveal(delay: d(), child: const _SectionLabel("Where's my train")),
        const SizedBox(height: 10),
        Reveal(delay: d(), child: const _LineGrid()),
        const SizedBox(height: 26),
        Reveal(delay: d(), child: const DataNote()),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: Txt.label(11.5));
}

class _ScheduleBadge extends StatelessWidget {
  const _ScheduleBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Palette.line),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.schedule_rounded, size: 13, color: Palette.muted),
        const SizedBox(width: 5),
        Text('SCHEDULE-BASED', style: Txt.label(9.5)),
      ],
    ),
  );
}

class _LocateCard extends StatelessWidget {
  const _LocateCard({required this.onTap, required this.busy});
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: busy ? null : onTap,
    label: 'Find my nearest station',
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE04D), Palette.signal],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: Palette.signalInk, borderRadius: BorderRadius.circular(15)),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(13),
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Palette.signal),
                  )
                : const Icon(Icons.near_me_rounded, color: Palette.signal),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nearest station', style: Txt.display(17, color: Palette.signalInk)),
                const SizedBox(height: 3),
                Text(
                  'Use your location once. It stays on your phone.',
                  style: Txt.text(13, color: Palette.signalInk.withValues(alpha: .75), weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, color: Palette.signalInk),
        ],
      ),
    ),
  );
}

/// A station and its very next train, with a live countdown.
class NextTrainCard extends StatelessWidget {
  const NextTrainCard({super.key, required this.station, required this.onTap, this.note, this.nearby = false});
  final Station station;
  final VoidCallback onTap;
  final String? note;
  final bool nearby;

  @override
  Widget build(BuildContext context) {
    final state = TransitScope.of(context);
    final tt = state.timetable;
    return Pressable(
      onTap: onTap,
      label: station.name,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Palette.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: nearby ? Palette.signal.withValues(alpha: .5) : Palette.line),
        ),
        child: EverySecond(
          clock: state.clock.second,
          builder: (context) {
            final next = tt.departures(station.id, state.clock.now, limit: 1);
            final d = next.isEmpty ? null : next.first;
            final line = d == null ? null : tt.lineOf(d.train);
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (nearby) ...[
                            const Icon(Icons.near_me_rounded, size: 14, color: Palette.signal),
                            const SizedBox(width: 5),
                          ],
                          Flexible(
                            child: Text(
                              station.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Txt.display(18, height: 1.15),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (d == null)
                        Text('No trains in the next 4 hours', style: Txt.text(13, color: Palette.muted))
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            LineChip(line!, small: true),
                            Text(
                              'to ${tt.stations[d.train.destination].name}',
                              style: Txt.text(13.5, weight: FontWeight.w700, color: Palette.ink),
                            ),
                            ...trainTags(d, compact: true),
                          ],
                        ),
                      if (note != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          note!,
                          style: Txt.text(12, color: Palette.muted, weight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
                if (d != null) ...[
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Countdown(d.minutesAway, size: 30, color: d.minutesAway < 2 ? Palette.signal : Palette.ink),
                      const SizedBox(height: 2),
                      Text(
                        clock(d.at),
                        style: Txt.text(12, color: Palette.muted, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LineGrid extends StatelessWidget {
  const _LineGrid();

  @override
  Widget build(BuildContext context) {
    final state = TransitScope.of(context);
    final tt = state.timetable;
    return EverySecond(
      clock: state.clock.second,
      builder: (context) {
        final now = state.clock.now;
        final counts = List.filled(tt.lines.length, 0);
        for (final p in tt.running(now)) {
          counts[p.train.line]++;
        }
        return LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final line in tt.lines)
                  SizedBox(
                    width: w,
                    child: LineTile(
                      line: line,
                      running: counts[line.index],
                      onTap: () => Navigator.of(context).push(slideUp(LineScreen(line: line.index))),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class LineTile extends StatelessWidget {
  const LineTile({super.key, required this.line, required this.running, required this.onTap});
  final Line line;
  final int running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Color(line.color);
    return Pressable(
      onTap: onTap,
      label: '${line.name} line, $running trains running',
      child: Hero(
        tag: 'line-${line.id}',
        flightShuttleBuilder: (_, anim, _, _, _) => LineShuttle(anim: anim, color: Color(line.color)),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            height: 86,
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: Palette.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Palette.line),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: CustomPaint(size: const Size(64, 40), painter: _MiniLinePainter(c)),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            line.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Txt.display(14.5, height: 1.1),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('$running', style: Txt.display(22, color: running > 0 ? c : Palette.faint)),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'on the move',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Txt.text(11.5, color: Palette.muted, weight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniLinePainter extends CustomPainter {
  _MiniLinePainter(this.c);
  final Color c;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = c.withValues(alpha: .35)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(0, size.height * .8)
      ..lineTo(size.width * .45, size.height * .8)
      ..lineTo(size.width * .75, size.height * .25)
      ..lineTo(size.width, size.height * .25);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_MiniLinePainter old) => old.c != c;
}

/// Where the data comes from, said plainly.
class DataNote extends StatelessWidget {
  const DataNote({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Palette.field,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Palette.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: Palette.signal),
            const SizedBox(width: 8),
            Text('Not live GPS', style: Txt.text(14, weight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Train positions and countdowns are worked out from the timetable, offline. '
          'Mumbai has no open real-time feed, so a late train will not show as late.\n\n'
          'Suburban times: Western and Central Railway timetables, via the Rush Hour project (MIT). '
          'Metro times are estimates from published frequencies. Map data © OpenStreetMap contributors (ODbL).',
          style: Txt.text(12.5, color: Palette.muted, height: 1.5, weight: FontWeight.w600),
        ),
      ],
    ),
  );
}
