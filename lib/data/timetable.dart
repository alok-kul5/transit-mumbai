import 'dart:convert';
import 'dart:math' as math;

/// The bundled timetable and every question the app asks it.
///
/// Times are minutes after midnight in Mumbai (IST). A train keeps counting past
/// 1440 when it runs after midnight, and its service day is the day it left.
/// Nothing here is live: positions come from the schedule.

const _fast = 1, _ac = 2, _ladies = 4;

/// Minutes a train is assumed to stand at a platform before it leaves.
const dwell = 0.35;

class Station {
  Station(this.id, this.code, this.name, this.lat, this.lng) : metro = code.contains(':');
  final int id;
  final String code;
  final String name;
  final double lat, lng;
  final bool metro;

  /// Lines that call here, in timetable order.
  final List<int> lines = [];

  /// Stations within a short walk on another line or system.
  final List<int> links = [];

  /// Short code for chips: "ADH", or "M1" for a metro stop.
  String get short => metro ? code.split(':').first : code;
}

class Branch {
  Branch(this.name, this.stations, this.km);
  final String name;
  final List<int> stations;

  /// Distance along the branch at each station, from its first station.
  final List<double> km;

  double get length => km.last;
  int indexOf(int station) => stations.indexOf(station);
}

class MetroService {
  const MetroService({
    required this.first,
    required this.last,
    required this.peak,
    required this.offpeak,
    required this.runs,
  });
  final int first, last, peak, offpeak;
  final List<int> runs;

  /// Typical gap between trains at [minute], or null outside service hours.
  int? headwayAt(double minute) {
    if (minute < first || minute > last) return null;
    return isPeak(minute) ? peak : offpeak;
  }

  static bool isPeak(double m) => (m >= 480 && m < 660) || (m >= 1020 && m < 1260);
}

class Line {
  Line(this.index, this.id, this.name, this.metro, this.color, this.branches, this.service);
  final int index;
  final String id;
  final String name;
  final bool metro;
  final int color;
  final List<Branch> branches;
  final MetroService? service;

  /// Every station on any branch, without repeats, in branch order.
  late final List<int> stations = {for (final b in branches) ...b.stations}.toList();
}

class Train {
  Train({
    required this.id,
    required this.line,
    required this.branch,
    required this.number,
    required this.flags,
    required this.days,
    required this.generalDays,
    required this.stations,
    required this.times,
    this.platforms,
    this.estimated = false,
  });

  final int id;
  final int line;
  final int branch;
  final String number;
  final int flags;

  /// Bit 0 is Monday, bit 6 Sunday.
  final int days;

  /// Days the AC or ladies rake runs as an ordinary train.
  final int generalDays;
  final List<int> stations;
  final List<double> times;
  final List<String>? platforms;

  /// Metro trains are generated from published frequencies, not a timetable.
  final bool estimated;

  bool get fast => flags & _fast != 0;
  bool runsOn(int weekday) => days & (1 << (weekday - 1)) != 0;
  bool acOn(int weekday) => flags & _ac != 0 && generalDays & (1 << (weekday - 1)) == 0;
  bool ladiesOn(int weekday) => flags & _ladies != 0 && generalDays & (1 << (weekday - 1)) == 0;
  bool get hasAc => flags & _ac != 0;
  bool get hasLadies => flags & _ladies != 0;

  int get origin => stations.first;
  int get destination => stations.last;
  double get start => times.first;
  double get end => times.last;

  int stopIndex(int station) => stations.indexOf(station);
  String? platformAt(int stop) {
    final p = platforms?[stop];
    return p == null || p.isEmpty ? null : p;
  }
}

/// A moment in Mumbai: the day of the week and minutes after midnight.
class Moment {
  const Moment(this.weekday, this.minute);

  factory Moment.of(DateTime ist) =>
      Moment(ist.weekday, ist.hour * 60 + ist.minute + ist.second / 60 + ist.millisecond / 60000);

  final int weekday;
  final double minute;

  /// The weekday [days] away (negative for earlier days).
  int dayShift(int days) => (weekday - 1 + days) % 7 + 1;

  Moment plus(double minutes) {
    var m = minute + minutes;
    var d = 0;
    while (m >= 1440) {
      m -= 1440;
      d++;
    }
    while (m < 0) {
      m += 1440;
      d--;
    }
    return Moment(dayShift(d), m);
  }

  @override
  String toString() => 'Moment($weekday, ${clock(minute)})';
}

/// The current time in Mumbai, wherever the phone is.
DateTime istNow() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

/// "07:05" for 425, wrapping past midnight.
String clock(double minute) {
  final m = (minute.floor() % 1440 + 1440) % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

class Departure {
  const Departure(this.train, this.stop, this.at, this.minutesAway, this.weekday);
  final Train train;
  final int stop;

  /// Minutes after the query day's midnight (may pass 1440).
  final double at;
  final double minutesAway;

  /// Service day of the train.
  final int weekday;

  bool get ac => train.acOn(weekday);
  bool get ladies => train.ladiesOn(weekday);
  String? get platform => train.platformAt(stop);
}

class Position {
  const Position({
    required this.train,
    required this.weekday,
    required this.stop,
    required this.progress,
    required this.lat,
    required this.lng,
    required this.km,
    required this.forward,
    required this.atPlatform,
  });
  final Train train;
  final int weekday;

  /// Index of the last stop the train left (or is standing at).
  final int stop;

  /// 0 at [stop], 1 at the next stop, eased like a train that speeds up and brakes.
  final double progress;
  final double lat, lng;

  /// Distance along the branch it is drawn on.
  final double km;

  /// True when running in the branch's own direction.
  final bool forward;
  final bool atPlatform;

  int get nextStop => math.min(stop + 1, train.stations.length - 1);
}

class Timetable {
  Timetable._(this.stations, this.lines, this.trains, this.sources) {
    for (final t in trains) {
      for (var i = 0; i < t.stations.length; i++) {
        (_calls[t.stations[i]] ??= []).add((t, i));
      }
    }
  }

  final List<Station> stations;
  final List<Line> lines;
  final List<Train> trains;
  final List<Map<String, dynamic>> sources;
  final Map<int, List<(Train, int)>> _calls = {};
  final Map<(int, int), List<Train>> _onBranch = {};
  final Map<(int, int), List<int>> _branchIdx = {};

  factory Timetable.parse(String json) => Timetable.fromJson(jsonDecode(json) as Map<String, dynamic>);

  factory Timetable.fromJson(Map<String, dynamic> j) {
    final stations = <Station>[
      for (final (i, s) in (j['stations'] as List).indexed)
        Station(i, s[0] as String, s[1] as String, (s[2] as num).toDouble(), (s[3] as num).toDouble()),
    ];
    final lines = <Line>[];
    for (final (li, l) in (j['lines'] as List).indexed) {
      final branches = <Branch>[];
      for (final b in l['branches'] as List) {
        final ids = (b['stations'] as List).cast<int>();
        final km = <double>[0];
        for (var i = 1; i < ids.length; i++) {
          km.add(km.last + distanceKm(stations[ids[i - 1]], stations[ids[i]]));
        }
        branches.add(Branch(b['name'] as String, ids, km));
      }
      final s = l['service'] as Map<String, dynamic>?;
      lines.add(
        Line(
          li,
          l['id'] as String,
          l['name'] as String,
          l['kind'] == 'metro',
          int.parse('FF${(l['color'] as String).substring(1)}', radix: 16),
          branches,
          s == null
              ? null
              : MetroService(
                  first: _hm(s['first'] as String),
                  last: _hm(s['last'] as String),
                  peak: s['peak'] as int,
                  offpeak: s['offpeak'] as int,
                  runs: (s['runs'] as List).cast<int>(),
                ),
        ),
      );
      for (final b in branches) {
        for (final st in b.stations) {
          if (!stations[st].lines.contains(li)) stations[st].lines.add(li);
        }
      }
    }
    for (final link in j['links'] as List? ?? const []) {
      final a = link[0] as int, b = link[1] as int;
      stations[a].links.add(b);
      stations[b].links.add(a);
    }

    final trains = <Train>[];
    for (final r in j['trains'] as List) {
      final ids = (r[7] as List).cast<int>();
      final deltas = (r[8] as List).cast<int>();
      final times = <double>[(r[6] as num).toDouble()];
      for (final d in deltas) {
        times.add(times.last + d);
      }
      trains.add(
        Train(
          id: trains.length,
          line: r[0] as int,
          branch: r[1] as int,
          number: r[2] as String,
          flags: r[3] as int,
          days: r[4] as int,
          generalDays: r[5] as int,
          stations: ids,
          times: times,
          platforms: r.length > 9 ? (r[9] as List).cast<String>() : null,
        ),
      );
    }
    for (final line in lines) {
      if (line.service != null) _generateMetro(line, trains);
    }
    return Timetable._(stations, lines, trains, ((j['meta'] as Map)['sources'] as List).cast<Map<String, dynamic>>());
  }

  /// Metro lines run to a frequency: one train every few minutes each way.
  static void _generateMetro(Line line, List<Train> out) {
    final s = line.service!;
    final b = line.branches.first;
    for (final forward in [true, false]) {
      final ids = forward ? b.stations : b.stations.reversed.toList();
      final runs = forward ? s.runs : s.runs.reversed.toList();
      var t = s.first.toDouble();
      var n = 1;
      while (t <= s.last) {
        final times = <double>[t];
        for (final r in runs) {
          times.add(times.last + r);
        }
        out.add(
          Train(
            id: out.length,
            line: line.index,
            branch: 0,
            number: '${line.id}-${forward ? 'A' : 'B'}${n.toString().padLeft(3, '0')}',
            flags: _ac,
            days: 0x7F,
            generalDays: 0,
            stations: ids,
            times: times,
            estimated: true,
          ),
        );
        t += s.headwayAt(t)!;
        n++;
      }
    }
  }

  static int _hm(String s) {
    final p = s.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  // ---- Lookups ---------------------------------------------------------

  Line lineOf(Train t) => lines[t.line];
  Station stationOf(int id) => stations[id];

  /// Trains that call at [station], with the index of that call.
  List<(Train, int)> callsAt(int station) => _calls[station] ?? const [];

  /// The next departures from [station] after [now], soonest first. Trains that
  /// end here are left out: you cannot board them.
  List<Departure> departures(
    int station,
    Moment now, {
    int limit = 20,
    double window = 240,
    int? line,
    bool Function(Departure)? where,
  }) {
    final out = <Departure>[];
    for (final (t, i) in callsAt(station)) {
      if (i == t.stations.length - 1) continue;
      if (line != null && t.line != line) continue;
      for (final day in const [-1, 0, 1]) {
        final wd = now.dayShift(day);
        if (!t.runsOn(wd)) continue;
        final at = t.times[i] + day * 1440;
        final away = at - now.minute;
        if (away < -0.25 || away > window) continue;
        final d = Departure(t, i, at, away, wd);
        if (where == null || where(d)) out.add(d);
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  /// The first train from [from] that later calls at [to].
  Departure? nextBetween(int from, int to, Moment now, {double window = 360}) {
    final ds = departures(
      from,
      now,
      limit: 400,
      window: window,
      where: (d) {
        final j = d.train.stations.indexOf(to);
        return j > d.stop;
      },
    );
    return ds.isEmpty ? null : ds.first;
  }

  /// Trains of [line] that could be drawn on [branch]: every stop lies on it.
  List<Train> trainsOnBranch(int line, int branch) => _onBranch.putIfAbsent((line, branch), () {
    final b = lines[line].branches[branch];
    final set = b.stations.toSet();
    return [
      for (final t in trains)
        if (t.line == line && t.stations.every(set.contains)) t,
    ];
  });

  /// Where each stop of [t] sits on [branch].
  List<int> branchIndices(Train t, int branch) => _branchIdx.putIfAbsent((t.id, branch), () {
    final b = lines[t.line].branches[branch];
    return [for (final s in t.stations) b.indexOf(s)];
  });

  /// Where [t] is at [now] if it is running, from the schedule alone.
  Position? positionOf(Train t, Moment now, {int? branch}) {
    final bi = branch ?? t.branch;
    final b = lines[t.line].branches[bi];
    final idx = branchIndices(t, bi);
    if (idx.contains(-1)) return null;
    for (final day in const [-1, 0]) {
      final wd = now.dayShift(day);
      if (!t.runsOn(wd)) continue;
      final m = now.minute - day * 1440;
      // Shown from a minute before it leaves until it reaches the end.
      if (m < t.start - 1 || m > t.end) continue;
      final p = interpolate(t.times, m);
      final from = b.km[idx[p.$1]];
      final to = b.km[idx[math.min(p.$1 + 1, idx.length - 1)]];
      final km = from + (to - from) * p.$2;
      final (lat, lng) = pointAt(b, km, stations);
      return Position(
        train: t,
        weekday: wd,
        stop: p.$1,
        progress: p.$2,
        lat: lat,
        lng: lng,
        km: km,
        forward: idx.last > idx.first,
        atPlatform: p.$2 == 0,
      );
    }
    return null;
  }

  /// Every train running on [line] (or every line) at [now].
  List<Position> running(Moment now, {int? line, int? branch}) {
    final out = <Position>[];
    if (line != null && branch != null) {
      for (final t in trainsOnBranch(line, branch)) {
        final p = positionOf(t, now, branch: branch);
        if (p != null) out.add(p);
      }
      return out;
    }
    for (final t in trains) {
      if (line != null && t.line != line) continue;
      final p = positionOf(t, now);
      if (p != null) out.add(p);
    }
    return out;
  }

  // ---- Places ------------------------------------------------------------

  /// Stations nearest to a point, closest first, with distance in km.
  List<(Station, double)> nearest(double lat, double lng, {int count = 3}) {
    final all = [for (final s in stations) (s, distance(lat, lng, s.lat, s.lng))];
    all.sort((a, b) => a.$2.compareTo(b.$2));
    return all.take(count).toList();
  }

  /// Stations matching [query]: name, code or a common alias. Every word must match.
  List<Station> search(String query, {int limit = 30}) {
    final words = _norm(query).split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    final scored = <(Station, int)>[];
    for (final s in stations) {
      final name = _norm(s.name);
      final parts = name.split(' ');
      final alias = _aliases[s.code] ?? '';
      var score = 0;
      var ok = true;
      for (final w in words) {
        if (name.startsWith(w)) {
          score += 30;
        } else if (parts.any((p) => p.startsWith(w))) {
          score += 20;
        } else if (s.short.toLowerCase() == w) {
          score += 25;
        } else if (alias.split(' ').any((a) => a.startsWith(w))) {
          score += 15;
        } else if (name.replaceAll(' ', '').contains(w)) {
          score += 5;
        } else {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      if (!s.metro) score += 2; // the suburban station first when names tie
      score -= name.length ~/ 8;
      scored.add((s, score));
    }
    scored.sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.name.compareTo(b.$1.name));
    return [for (final e in scored.take(limit)) e.$1];
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r' +'), ' ').trim();

  static const _aliases = {
    'CSTM': 'vt victoria terminus chhatrapati shivaji terminus cst',
    'BCT': 'bombay central',
    'CCG': 'churchgate',
    'DR': 'dadar',
    'BA': 'bandra',
    'CLA': 'kurla',
    'TNA': 'thane',
    'BEPR': 'belapur',
    'STC': 'santa cruz',
    'NSP': 'nala sopara',
  };
}

/// Finds the segment of [times] that [m] falls in, and how far along it the
/// train is, allowing for a short stand at each platform.
(int, double) interpolate(List<double> times, double m) {
  if (m <= times.first) return (0, 0);
  for (var i = 0; i < times.length - 1; i++) {
    final dep = times[i], next = times[i + 1];
    if (m >= next) continue;
    final gap = next - dep;
    final arrive = next - math.min(dwell, gap * .3);
    if (m >= arrive) return (i + 1, 0); // standing at the next platform
    final p = ((m - dep) / (arrive - dep)).clamp(0.0, 1.0);
    return (i, ease(p));
  }
  return (times.length - 1, 0);
}

/// Pulls away gently, cruises, then brakes: smoothstep.
double ease(double p) => p * p * (3 - 2 * p);

/// The point [km] along [b], following its stations.
(double, double) pointAt(Branch b, double km, List<Station> st) {
  final ids = b.stations;
  if (km <= 0) return (st[ids.first].lat, st[ids.first].lng);
  for (var i = 1; i < ids.length; i++) {
    if (km <= b.km[i]) {
      final seg = b.km[i] - b.km[i - 1];
      final f = seg == 0 ? 0.0 : (km - b.km[i - 1]) / seg;
      final a = st[ids[i - 1]], c = st[ids[i]];
      return (a.lat + (c.lat - a.lat) * f, a.lng + (c.lng - a.lng) * f);
    }
  }
  return (st[ids.last].lat, st[ids.last].lng);
}

double distanceKm(Station a, Station b) => distance(a.lat, a.lng, b.lat, b.lng);

/// Great-circle distance in km.
double distance(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final dp = p2 - p1, dl = (lng2 - lng1) * math.pi / 180;
  final h = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.asin(math.sqrt(h));
}
