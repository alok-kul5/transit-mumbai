import 'package:material_ui/material_ui.dart';

import '../brand/tokens.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// The time in Mumbai, set as type rather than a badge: a serif clock with an
/// italic line under it. The line turns yellow when you are looking at another
/// time or running the schedule fast. Tap for the time controls.
class TimeReadout extends StatelessWidget {
  const TimeReadout({super.key, required this.clock, required this.onTap});
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
        final hh = now.hour.toString().padLeft(2, '0');
        final mm = now.minute.toString().padLeft(2, '0');
        final note = live
            ? 'in Mumbai'
            : clock.speed != 1
            ? 'running ${clock.speed.round()}× fast'
            : '${_weekday(now.weekday)}, previewing';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: hh),
                  // The colon blinks with the seconds, like a station clock.
                  TextSpan(
                    text: ':',
                    style: TextStyle(color: now.second.isEven ? Palette.ink : Palette.ink.withValues(alpha: .25)),
                  ),
                  TextSpan(text: mm),
                ],
              ),
              style: Txt.display(24, weight: FontWeight.w600, height: 1),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: Motion.of(context, Motion.base),
              style: Txt.note(13, color: live ? Palette.muted : Palette.signal),
              child: Text(note),
            ),
          ],
        );
      },
    ),
  );
}

String _weekday(int d) => const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d - 1];

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
            Text('Speed', style: Txt.note(16)),
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
