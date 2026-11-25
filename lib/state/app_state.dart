import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/timetable.dart';

/// Time in the app. Normally it is now in Mumbai; the time controls can jump
/// to rush hour or run the schedule faster to watch trains move.
class TransitClock {
  TransitClock({DateTime Function()? source}) : _source = source ?? istNow {
    frame = ValueNotifier(Moment.of(_source()));
    second = ValueNotifier(_source().millisecondsSinceEpoch ~/ 1000);
  }

  final DateTime Function() _source;

  /// Updated every frame while something is listening.
  late final ValueNotifier<Moment> frame;

  /// Ticks once a second (of app time), for countdowns.
  late final ValueNotifier<int> second;

  /// App time minus real time.
  Duration offset = Duration.zero;
  double _speed = 1;
  final speedNotifier = ValueNotifier<double>(1);
  Duration? _lastElapsed;

  double get speed => _speed;
  bool get isLive => offset.inSeconds.abs() < 2 && _speed == 1;

  DateTime get ist => _source().add(offset);
  Moment get now => Moment.of(ist);

  set speed(double s) {
    _speed = s;
    speedNotifier.value = s;
  }

  /// Back to real time.
  void live() {
    offset = Duration.zero;
    speed = 1;
    _emit();
  }

  /// Jump to the next [hour]:[minute] on a weekday, e.g. the morning rush.
  void jumpTo(int hour, [int minute = 0]) {
    final real = _source();
    var target = DateTime.utc(real.year, real.month, real.day, hour, minute);
    while (!target.isAfter(real) || target.weekday > 5) {
      target = target.add(const Duration(days: 1));
    }
    offset = target.difference(real);
    _emit();
  }

  /// Called by the app's ticker with the time since it started.
  void tick(Duration elapsed) {
    final last = _lastElapsed;
    _lastElapsed = elapsed;
    if (last != null && _speed != 1) {
      final dt = elapsed - last;
      offset += dt * (_speed - 1);
    }
    _emit();
  }

  void _emit() {
    final t = ist;
    frame.value = Moment.of(t);
    second.value = t.millisecondsSinceEpoch ~/ 1000;
  }
}

/// Everything the screens share: the timetable, favourites and where you are.
class TransitState extends ChangeNotifier {
  TransitState(this.timetable, {SharedPreferences? prefs, TransitClock? clock})
    : _prefs = prefs,
      clock = clock ?? TransitClock() {
    final saved = prefs?.getStringList(_favKey) ?? const [];
    final byCode = {for (final s in timetable.stations) s.code: s.id};
    for (final c in saved) {
      final id = byCode[c];
      if (id != null) _favourites.add(id);
    }
  }

  static const _favKey = 'favourites.v1';

  final Timetable timetable;
  final TransitClock clock;
  final SharedPreferences? _prefs;
  final List<int> _favourites = [];

  /// The station the map and sheet are showing, if any.
  int? selected;

  /// Your position, once you have shared it.
  (double, double)? here;
  String? locationError;
  bool locating = false;

  List<int> get favourites => List.unmodifiable(_favourites);
  bool isFavourite(int station) => _favourites.contains(station);

  void toggleFavourite(int station) {
    if (!_favourites.remove(station)) _favourites.insert(0, station);
    unawaited(_prefs?.setStringList(_favKey, [for (final id in _favourites) timetable.stations[id].code]));
    notifyListeners();
  }

  void select(int? station) {
    if (selected == station) return;
    selected = station;
    notifyListeners();
  }

  void setLocating() {
    locating = true;
    locationError = null;
    notifyListeners();
  }

  void setHere(double lat, double lng) {
    here = (lat, lng);
    locating = false;
    locationError = null;
    notifyListeners();
  }

  void setLocationError(String e) {
    locating = false;
    locationError = e;
    notifyListeners();
  }

  /// Nearest stations to where you are, closest first.
  List<(Station, double)> get nearby => here == null ? const [] : timetable.nearest(here!.$1, here!.$2, count: 3);
}

class TransitScope extends InheritedNotifier<TransitState> {
  const TransitScope({super.key, required TransitState state, required super.child}) : super(notifier: state);

  static TransitState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TransitScope>()!.notifier!;
  static TransitState read(BuildContext context) => context.getInheritedWidgetOfExactType<TransitScope>()!.notifier!;
}
