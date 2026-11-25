import 'package:material_ui/material_ui.dart';

import '../brand/tokens.dart';
import '../data/timetable.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';
import 'home.dart';
import 'train_sheet.dart';

/// A station's departure board, inside the home sheet.
class StationPanel extends StatefulWidget {
  const StationPanel({
    super.key,
    required this.station,
    required this.scroll,
    required this.onClose,
    required this.onStation,
  });
  final int station;
  final ScrollController scroll;
  final VoidCallback onClose;
  final ValueChanged<int> onStation;

  @override
  State<StationPanel> createState() => _StationPanelState();
}

class _StationPanelState extends State<StationPanel> {
  int? _line;
  bool _fastOnly = false;

  @override
  Widget build(BuildContext context) {
    final state = TransitScope.of(context);
    final tt = state.timetable;
    final s = tt.stations[widget.station];
    final fav = state.isFavourite(s.id);
    final anyFast = tt.callsAt(s.id).any((c) => c.$1.fast);
    return ListView(
      controller: widget.scroll,
      padding: EdgeInsets.fromLTRB(18, 0, 18, MediaQuery.paddingOf(context).bottom + 28),
      children: [
        const SheetHandle(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(s.name, style: Txt.display(30, height: 1.05)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final l in s.lines) LineChip(tt.lines[l]), if (!s.metro) _Code(s.code)],
                  ),
                ],
              ),
            ),
            _RoundButton(
              icon: fav ? Icons.star_rounded : Icons.star_outline_rounded,
              color: fav ? Palette.signal : Palette.ink,
              label: fav ? 'Remove from your stations' : 'Add to your stations',
              onTap: () => state.toggleFavourite(s.id),
            ),
            const SizedBox(width: 8),
            _RoundButton(icon: Icons.close_rounded, label: 'Close', onTap: widget.onClose),
          ],
        ),
        const SizedBox(height: 18),
        EverySecond(
          clock: state.clock.second,
          builder: (context) {
            final now = state.clock.now;
            final ds = tt.departures(s.id, now, limit: 16, line: _line, where: _fastOnly ? (d) => d.train.fast : null);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (ds.isEmpty)
                  _Empty(metro: s.metro)
                else
                  _HeroDeparture(d: ds.first, onTap: () => showTrainSheet(context, ds.first)),
                const SizedBox(height: 14),
                if (s.lines.length > 1 || anyFast)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _Filter(
                          'All',
                          _line == null && !_fastOnly,
                          () => setState(() {
                            _line = null;
                            _fastOnly = false;
                          }),
                        ),
                        if (s.lines.length > 1)
                          for (final l in s.lines)
                            _Filter(
                              tt.lines[l].name,
                              _line == l,
                              () => setState(() => _line = _line == l ? null : l),
                              color: Color(tt.lines[l].color),
                            ),
                        if (anyFast) _Filter('Fast only', _fastOnly, () => setState(() => _fastOnly = !_fastOnly)),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                for (final (i, d) in ds.skip(1).indexed)
                  Reveal(
                    key: ValueKey('${d.train.id}-${d.at}'),
                    delay: Duration(milliseconds: 30 * i.clamp(0, 10)),
                    dy: 10,
                    child: _DepartureRow(d: d, onTap: () => showTrainSheet(context, d)),
                  ),
              ],
            );
          },
        ),
        if (s.links.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('CHANGE HERE', style: Txt.label(11)),
          const SizedBox(height: 8),
          for (final id in s.links)
            Pressable(
              onTap: () => widget.onStation(id),
              label: 'Walk to ${tt.stations[id].name}',
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Palette.card, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    const Icon(Icons.directions_walk_rounded, color: Palette.muted, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(tt.stations[id].name, style: Txt.text(15, weight: FontWeight.w800)),
                    ),
                    for (final l in tt.stations[id].lines) ...[
                      LineChip(tt.lines[l], small: true),
                      const SizedBox(width: 4),
                    ],
                    Text(walk(distanceKm(s, tt.stations[id])), style: Txt.text(12, color: Palette.muted)),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 22),
        const DataNote(),
      ],
    );
  }
}

class _Code extends StatelessWidget {
  const _Code(this.code);
  final String code;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      border: Border.all(color: Palette.line),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(code, style: Txt.label(11, color: Palette.muted)),
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, required this.label, this.color = Palette.ink});
  final IconData icon;
  final VoidCallback onTap;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    label: label,
    child: AnimatedContainer(
      duration: Motion.of(context, Motion.base),
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: Palette.card, borderRadius: BorderRadius.circular(14)),
      child: AnimatedSwitcher(
        duration: Motion.of(context, Motion.base),
        transitionBuilder: (c, a) => ScaleTransition(
          scale: CurvedAnimation(parent: a, curve: Motion.spring),
          child: c,
        ),
        child: Icon(icon, key: ValueKey(icon), color: color, size: 22),
      ),
    ),
  );
}

class _Filter extends StatelessWidget {
  const _Filter(this.text, this.on, this.onTap, {this.color = Palette.signal});
  final String text;
  final bool on;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Pressable(
      onTap: onTap,
      label: text,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.base),
        curve: Motion.out,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: on ? color : Palette.card, borderRadius: BorderRadius.circular(99)),
        child: Text(
          text,
          style: Txt.text(13, weight: FontWeight.w800, color: on ? Palette.signalInk : Palette.ink),
        ),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.metro});
  final bool metro;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Palette.card, borderRadius: BorderRadius.circular(24)),
    child: Text(
      metro ? 'The metro is closed for the night.' : 'No trains from here in the next four hours.',
      style: Txt.text(15, color: Palette.muted, weight: FontWeight.w700),
    ),
  );
}

/// The next train, big: a countdown, a ring that closes as it approaches, and where it goes.
class _HeroDeparture extends StatelessWidget {
  const _HeroDeparture({required this.d, required this.onTap});
  final Departure d;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = TransitScope.of(context).timetable;
    final line = tt.lineOf(d.train);
    final c = Color(line.color);
    final soon = d.minutesAway < 2;
    return Pressable(
      onTap: onTap,
      scale: .98,
      label: 'Next train to ${tt.stations[d.train.destination].name}',
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.slow),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(Palette.card, c, .28)!, Palette.card],
          ),
          border: Border.all(color: soon ? Palette.signal : c.withValues(alpha: .5), width: soon ? 1.6 : 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NEXT TRAIN', style: Txt.label(10.5, color: c)),
                  const SizedBox(height: 6),
                  Countdown(d.minutesAway, size: 46, color: soon ? Palette.signal : Palette.ink),
                  const SizedBox(height: 8),
                  Text(
                    'to ${tt.stations[d.train.destination].name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.display(17, height: 1.15),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        clock(d.at),
                        style: Txt.text(13.5, weight: FontWeight.w800, color: Palette.muted),
                      ),
                      if (d.platform != null) Tag('PF ${d.platform}', Palette.ink),
                      ...trainTags(d),
                    ],
                  ),
                ],
              ),
            ),
            ApproachRing(minutes: d.minutesAway, color: c, size: 84),
          ],
        ),
      ),
    );
  }
}

class _DepartureRow extends StatelessWidget {
  const _DepartureRow({required this.d, required this.onTap});
  final Departure d;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = TransitScope.of(context).timetable;
    final line = tt.lineOf(d.train);
    return Pressable(
      onTap: onTap,
      scale: .98,
      label: '${clock(d.at)} to ${tt.stations[d.train.destination].name}',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Palette.line)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(clock(d.at), style: Txt.text(15.5, weight: FontWeight.w800)),
            ),
            Container(
              width: 4,
              height: 34,
              decoration: BoxDecoration(color: Color(line.color), borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tt.stations[d.train.destination].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.text(15, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 5,
                    runSpacing: 3,
                    children: [
                      if (d.platform != null) Tag('PF ${d.platform}', Palette.muted),
                      ...trainTags(d, compact: true),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Countdown(d.minutesAway, size: 18, showSeconds: false, color: Palette.muted),
          ],
        ),
      ),
    );
  }
}
