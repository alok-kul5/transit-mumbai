import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transit/app.dart';
import 'package:transit/brand/tokens.dart';
import 'package:transit/data/timetable.dart';
import 'package:transit/screens/line.dart';
import 'package:transit/state/app_state.dart';
import 'package:transit/widgets/transit_map.dart';
import 'package:transit/widgets/ui.dart';

final _tt = Timetable.parse(File('assets/transit.json').readAsStringSync());

/// A button by its accessible label.
Finder labelled(Pattern l) => find.byWidgetPredicate(
  (w) => w is Pressable && w.label != null && (l is RegExp ? l.hasMatch(w.label!) : w.label == l),
);

/// Tuesday 09:00 in Mumbai, frozen.
TransitClock _rush() => TransitClock(source: () => DateTime.utc(2026, 11, 24, 9));

void main() {
  setUp(() {
    Txt.useGoogleFonts = false;
    MapTiles.enabled = false;
  });

  Future<void> pumpFor(WidgetTester tester, Duration d) async {
    final end = tester.binding.clock.now().add(d);
    while (tester.binding.clock.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<TransitState> pumpApp(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(prefs);
    final state = TransitState(_tt, prefs: await SharedPreferences.getInstance(), clock: _rush());
    await tester.pumpWidget(TransitApp(state: state, showSplash: false));
    await pumpFor(tester, const Duration(seconds: 3));
    return state;
  }

  Future<void> openStation(WidgetTester tester, String query, String name) async {
    await tester.tap(labelled('Search stations'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField), query);
    await pumpFor(tester, const Duration(milliseconds: 600));
    await tester.tap(labelled(name).first);
    await pumpFor(tester, const Duration(seconds: 2));
  }

  testWidgets('the load sequence plays, then hands over to the map', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(TransitApp(state: TransitState(_tt, clock: _rush())));
    // Mid-sequence: the wordmark is up.
    await pumpFor(tester, const Duration(milliseconds: 1500));
    expect(find.text('MUMBAI LOCALS  ·  METRO'), findsOneWidget);
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('MUMBAI LOCALS  ·  METRO'), findsNothing);
    expect(find.text('Next trains'), findsOneWidget);
    expect(find.text('SCHEDULE-BASED'), findsOneWidget);
  });

  testWidgets('search a station and see its next trains', (tester) async {
    await pumpApp(tester);
    await openStation(tester, 'andh', 'Andheri');
    expect(find.text('NEXT TRAIN'), findsOneWidget);
    expect(find.text('Andheri'), findsWidgets);
    // At 9am the board is full, with fast trains among them.
    expect(find.text('FAST'), findsWidgets);
    expect(find.textContaining('to '), findsWidgets);
  });

  testWidgets('a starred station is kept and shows its next train', (tester) async {
    final state = await pumpApp(tester);
    await openStation(tester, 'thane', 'Thane');
    await tester.tap(labelled('Add to your stations'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    final thane = _tt.stations.firstWhere((s) => s.code == 'TNA').id;
    expect(state.favourites, [thane]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('favourites.v1'), ['TNA']);

    await tester.tap(labelled('Close'));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('YOUR STATIONS'), findsOneWidget);
    expect(labelled('Thane'), findsOneWidget);
  });

  testWidgets('favourites survive a restart', (tester) async {
    final state = await pumpApp(
      tester,
      prefs: {
        'favourites.v1': ['CCG', 'NOPE'],
      },
    );
    expect(state.favourites.map((id) => _tt.stations[id].name), ['Churchgate']);
  });

  testWidgets("where's my train: the line view counts trains on the move", (tester) async {
    final state = await pumpApp(tester);
    final tile = labelled(RegExp(r'^Western line, \d+ trains running'));
    await tester.ensureVisible(tile);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(tile, warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.byType(LineScreen), findsOneWidget);
    expect(find.text("WHERE'S MY TRAIN"), findsOneWidget);
    expect(find.text('Positions follow the timetable. Not live GPS.'), findsOneWidget);
    final running = _tt.running(state.clock.now, line: 0, branch: 0).length;
    expect(running, greaterThan(40));
    expect(find.text('$running'), findsOneWidget);
    expect(find.text('Churchgate'), findsWidgets);
  });

  testWidgets('a metro station says its times are estimates', (tester) async {
    await pumpApp(tester);
    await openStation(tester, 'versova', 'Versova');
    expect(find.text('EST'), findsWidgets);
    expect(find.text('M1'), findsWidgets);
  });

  testWidgets('time controls jump to the evening rush and back to live', (tester) async {
    final state = await pumpApp(tester);
    await tester.tap(labelled('Time controls').first);
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text('Evening rush · 18:30'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(state.clock.now.minute, closeTo(18 * 60 + 30, .1));
    expect(state.clock.isLive, isFalse);
    await tester.tap(find.text('Live'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(state.clock.isLive, isTrue);
  });

  test('jumping to a rush hour skips the weekend', () {
    // Saturday 10:00.
    final c = TransitClock(source: () => DateTime.utc(2026, 11, 28, 10));
    c.jumpTo(9);
    expect(c.ist.weekday, DateTime.monday);
    expect(c.ist.hour, 9);
  });

  test('speeding up the clock moves app time faster', () {
    var real = DateTime.utc(2026, 11, 24, 9);
    final c = TransitClock(source: () => real)..speed = 60;
    c.tick(Duration.zero);
    real = real.add(const Duration(seconds: 1));
    c.tick(const Duration(seconds: 1));
    expect(c.now.minute, closeTo(9 * 60 + 1, 1e-6)); // one real second = one app minute
  });
}
