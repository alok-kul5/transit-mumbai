import 'package:material_ui/material_ui.dart';

import '../brand/tokens.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// Mumbai time, with a green dot when it is real time and yellow when the
/// schedule has been moved or sped up.
class ClockPill extends StatelessWidget {
  const ClockPill({super.key, required this.clock, required this.onTap});
  final TransitClock clock;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    label: 'Time controls',
    child: EverySecond(
      clock: clock.second,
      builder: (context) {
        final live = clock.isLive;
        final now = clock.ist;
        final dot = live ? Palette.go : Palette.signal;
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          decoration: BoxDecoration(
            color: Palette.card.withValues(alpha: .92),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: live ? Palette.line : Palette.signal.withValues(alpha: .6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Pulse(color: dot),
              const SizedBox(width: 8),
              Text(_hhmm(now), style: Txt.text(14, weight: FontWeight.w800)),
              const SizedBox(width: 6),
              Text(
                live ? 'IST' : (clock.speed != 1 ? '${clock.speed.round()}×' : _weekday(now.weekday)),
                style: Txt.label(10, color: live ? Palette.muted : Palette.signal),
              ),
            ],
          ),
        );
      },
    ),
  );

  static String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String _weekday(int d) => const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][d - 1];

class _Pulse extends StatefulWidget {
  const _Pulse({required this.color});
  final Color color;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 12,
    height: 12,
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 4 + 8 * _c.value,
            height: 4 + 8 * _c.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: .5 * (1 - _c.value)),
            ),
          ),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
          ),
        ],
      ),
    ),
  );
}

Future<void> showTimeSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  backgroundColor: Palette.surface,
  barrierColor: const Color(0x99000000),
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
  builder: (_) => const _TimeSheet(),
);

class _TimeSheet extends StatefulWidget {
  const _TimeSheet();

  @override
  State<_TimeSheet> createState() => _TimeSheetState();
}

class _TimeSheetState extends State<_TimeSheet> {
  @override
  Widget build(BuildContext context) {
    final clock = TransitScope.of(context).clock;
    void act(VoidCallback f) => setState(f);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(color: Palette.line, borderRadius: BorderRadius.circular(9)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Time', style: Txt.display(26)),
            const SizedBox(height: 8),
            Text(
              'Everything in Transit runs on Mumbai time, worked out from the timetable. '
              'Jump to a rush hour or speed the schedule up to watch the trains move.',
              style: Txt.text(13.5, color: Palette.muted, height: 1.45, weight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Choice('Live', clock.isLive, () => act(clock.live)),
                _Choice('Morning rush · 9:00', false, () => act(() => clock.jumpTo(9))),
                _Choice('Evening rush · 18:30', false, () => act(() => clock.jumpTo(18, 30))),
              ],
            ),
            const SizedBox(height: 18),
            Text('SPEED', style: Txt.label(11)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in const [1.0, 10.0, 60.0])
                  _Choice(s == 1 ? 'Real time' : '${s.round()}×', clock.speed == s, () => act(() => clock.speed = s)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice(this.text, this.on, this.onTap);
  final String text;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    label: text,
    child: AnimatedContainer(
      duration: Motion.of(context, Motion.base),
      curve: Motion.out,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: BoxDecoration(color: on ? Palette.signal : Palette.card, borderRadius: BorderRadius.circular(14)),
      child: Text(
        text,
        style: Txt.text(14, weight: FontWeight.w800, color: on ? Palette.signalInk : Palette.ink),
      ),
    ),
  );
}
