import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit/data/timetable.dart';

/// Three stations in a line, one slow train and one fast train that skips B.
Timetable fixture() => Timetable.fromJson({
  'meta': {'sources': []},
  'stations': [
    ['A', 'Alpha', 19.0, 72.80],
    ['B', 'Bravo', 19.0, 72.81],
    ['C', 'Charlie', 19.0, 72.82],
  ],
  'lines': [
    {
      'id': 'WR',
      'name': 'Western',
      'kind': 'rail',
      'color': '#FF6A3D',
      'branches': [
        {
          'name': 'A – C',
          'stations': [0, 1, 2],
        },
      ],
    },
  ],
  'links': [],
  'trains': [
    // line, branch, number, flags, days, generalDays, first, stations, deltas, platforms
    [
      0,
      0,
      '101',
      0,
      0x7F,
      0,
      600,
      [0, 1, 2],
      [4, 6],
      ['1', '2', ''],
    ],
    [
      0,
      0,
      '102',
      1 | 2,
      0x1F,
      0x60,
      610,
      [0, 2],
      [8],
    ], // fast AC, weekdays only
    [
      0,
      0,
      '103',
      0,
      0x7F,
      0,
      1430,
      [2, 1, 0],
      [12, 6],
    ], // runs past midnight
  ],
});

void main() {
  group('departures', () {
    final tt = fixture();

    test('soonest first, from the query time', () {
      final d = tt.departures(0, const Moment(1, 595));
      expect(d.map((e) => e.train.number), ['101', '102']);
      expect(d.first.minutesAway, 5);
      expect(d.first.platform, '1');
    });

    test('a train that ends here is not a departure', () {
      final d = tt.departures(2, const Moment(1, 590), window: 1000);
      expect(d.map((e) => e.train.number), ['103']);
    });

    test('weekday-only trains are skipped at the weekend', () {
      final d = tt.departures(0, const Moment(6, 595));
      expect(d.map((e) => e.train.number), ['101']);
    });

    test('a train that left yesterday still departs after midnight', () {
      final d = tt.departures(1, const Moment(2, 1)); // Tuesday 00:01
      expect(d.single.train.number, '103');
      expect(d.single.minutesAway, closeTo(1, 1e-9)); // leaves Bravo at 00:02
      expect(d.single.weekday, 1);
    });

    test('late evening looks into tomorrow', () {
      final d = tt.departures(0, const Moment(7, 1420), window: 600);
      expect(d.isEmpty, isTrue); // 101 runs at 10:00, outside the window
      final later = tt.departures(0, const Moment(7, 1300), window: 1000);
      expect(later.first.weekday, 1); // Monday's 101
    });

    test('a train that has just left drops off the board', () {
      expect(tt.departures(0, const Moment(1, 600.2)).first.train.number, '101');
      expect(tt.departures(0, const Moment(1, 600.5)).first.train.number, '102');
    });

    test('next train between two stations skips trains that do not call', () {
      final d = tt.nextBetween(0, 1, const Moment(1, 605));
      expect(d, isNull); // 102 skips Bravo, 101 has gone
      expect(tt.nextBetween(0, 2, const Moment(1, 605))!.train.number, '102');
    });

    test('AC rakes run as general trains on their general days', () {
      final t = tt.trains[1];
      expect(t.fast, isTrue);
      expect(t.acOn(1), isTrue);
      expect(t.acOn(6), isFalse);
    });
  });

  group('positions', () {
    final tt = fixture();
    final slow = tt.trains[0];

    test('interpolate eases between stops and stands at platforms', () {
      final times = [0.0, 10.0];
      expect(interpolate(times, 0), (0, 0.0));
      final (i, p) = interpolate(times, (10 - dwell) / 2);
      expect(i, 0);
      expect(p, closeTo(.5, 1e-9));
      expect(interpolate(times, 9.9), (1, 0.0));
      expect(interpolate(times, 20), (1, 0.0));
      // Slow near the ends, quick in the middle.
      expect(interpolate(times, 1).$2, lessThan(.1));
    });

    test('a train halfway between stations is halfway along the branch', () {
      final p = tt.positionOf(slow, const Moment(1, 600 + (4 - dwell) / 2))!;
      expect(p.stop, 0);
      expect(p.progress, closeTo(.5, 1e-9));
      final b = tt.lines[0].branches[0];
      expect(p.km, closeTo(b.km[1] / 2, 1e-6));
      expect(p.lng, closeTo(72.805, 1e-6));
      expect(p.forward, isTrue);
    });

    test('a fast train glides past the station it skips', () {
      final fast = tt.trains[1];
      final p = tt.positionOf(fast, const Moment(1, 610 + (8 - dwell) / 2))!;
      expect(p.lng, closeTo(72.81, 1e-6)); // right over Bravo
      expect(p.atPlatform, isFalse);
    });

    test('not shown before it leaves or after it arrives', () {
      expect(tt.positionOf(slow, const Moment(1, 590)), isNull);
      expect(tt.positionOf(slow, const Moment(1, 599.5)), isNotNull); // boarding
      expect(tt.positionOf(slow, const Moment(1, 611)), isNull);
    });

    test('runs backwards on the branch for the other direction, past midnight', () {
      final p = tt.positionOf(tt.trains[2], const Moment(2, 4))!;
      expect(p.forward, isFalse);
      expect(p.weekday, 1);
      expect(p.lng, lessThan(72.81));
      expect(p.lng, greaterThan(72.80));
    });

    test('running lists every train under way', () {
      expect(tt.running(const Moment(1, 612)).map((p) => p.train.number), ['102']);
    });
  });

  group('places', () {
    final tt = fixture();
    test('nearest station by distance', () {
      final n = tt.nearest(19.0, 72.818, count: 2);
      expect(n.map((e) => e.$1.name), ['Charlie', 'Bravo']);
      expect(n.first.$2, lessThan(.3));
    });

    test('moments wrap across midnight and weeks', () {
      expect(const Moment(7, 1430).plus(20).weekday, 1);
      expect(const Moment(7, 1430).plus(20).minute, closeTo(10, 1e-9));
      expect(const Moment(1, 5).plus(-10).weekday, 7);
      expect(clock(1445), '00:05');
      expect(Moment.of(DateTime.utc(2026, 11, 25, 7, 30, 30)).minute, closeTo(450.5, 1e-9));
    });
  });

  group('bundled timetable', () {
    final tt = Timetable.parse(File('assets/transit.json').readAsStringSync());
    Station named(String n) => tt.stations.firstWhere((s) => s.name == n && !s.metro);

    test('has every suburban line and the metro', () {
      expect(tt.lines.map((l) => l.id), containsAll(['WR', 'CR', 'HB', 'TH', 'UR', 'M1', 'M2A', 'M3', 'M7']));
      expect(tt.trains.where((t) => !t.estimated).length, greaterThan(3000));
      expect(tt.sources.first['license'], 'MIT');
    });

    test('Dadar is busy on a weekday morning, on both Western and Central', () {
      final d = tt.departures(named('Dadar').id, const Moment(2, 8 * 60), window: 30, limit: 200);
      final lines = d.map((e) => tt.lineOf(e.train).id).toSet();
      expect(lines, containsAll(['WR', 'CR']));
      expect(d.length, greaterThan(20));
      expect(d.any((e) => e.train.fast), isTrue);
    });

    test('Churchgate to Andheri at 9am is minutes away', () {
      final d = tt.nextBetween(named('Churchgate').id, named('Andheri').id, const Moment(3, 540))!;
      expect(d.minutesAway, lessThan(10));
      final arrive = d.train.times[d.train.stopIndex(named('Andheri').id)];
      expect(arrive - d.train.times[d.stop], inInclusiveRange(20, 50));
    });

    test('Andheri metro and rail are linked', () {
      final m = tt.stations.firstWhere((s) => s.code == 'M1:Andheri');
      expect(m.links, contains(named('Andheri').id));
    });

    test('metro runs every few minutes at peak and not at 3am', () {
      final m = tt.stations.firstWhere((s) => s.code == 'M1:Versova');
      final peak = tt.departures(m.id, const Moment(2, 540), window: 20, limit: 50);
      expect(peak.length, inInclusiveRange(4, 6));
      expect(peak.every((d) => d.train.estimated), isTrue);
      expect(tt.departures(m.id, const Moment(2, 180), window: 60), isEmpty);
    });

    test('at rush hour the Western line has many trains under way', () {
      final run = tt.running(const Moment(2, 540), line: 0, branch: 0);
      expect(run.length, greaterThan(40));
      for (final p in run) {
        expect(p.lat, inInclusiveRange(18.9, 20.1));
      }
    });

    test('search finds stations by name, code and alias', () {
      expect(tt.search('andh').first.name, 'Andheri');
      expect(tt.search('vt').first.code, 'CSTM');
      expect(tt.search('ADH').first.name, 'Andheri');
      expect(tt.search('mira rd').isEmpty, isTrue);
      expect(tt.search('mira').first.name, 'Mira Road');
      expect(tt.search('zzz'), isEmpty);
    });
  });
}
