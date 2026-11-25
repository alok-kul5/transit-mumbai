import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../brand/tokens.dart';
import '../data/timetable.dart';
import '../state/app_state.dart';

/// Map tiles come from openstreetmap.org. Off in tests, where nothing may touch the network.
abstract final class MapTiles {
  static bool enabled = true;

  /// OSM's tile usage policy asks apps to identify themselves.
  static const userAgent = 'dev.alok.transit';
  static const url = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
}

/// Night tint for the standard OSM tiles: grey out the colours, stretch the
/// contrast so water sinks and roads rise, leaving a cool graphite.
const _night = ColorFilter.matrix([
  0.1786, 0.6008, 0.0606, 0, -152, //
  0.1786, 0.6008, 0.0606, 0, -151,
  0.1913, 0.6437, 0.0650, 0, -156,
  0, 0, 0, 1, 0,
]);

const mumbai = LatLng(19.07, 72.88);

class TransitMap extends StatefulWidget {
  const TransitMap({
    super.key,
    required this.state,
    required this.controller,
    this.draw = 1,
    this.onStation,
    this.focusLine,
  });

  final TransitState state;
  final MapController controller;

  /// 0..1 while the lines draw themselves in on first load.
  final double draw;
  final ValueChanged<int>? onStation;

  /// Dims the other lines.
  final int? focusLine;

  @override
  State<TransitMap> createState() => _TransitMapState();
}

class _TransitMapState extends State<TransitMap> {
  double _zoom = 11;

  Timetable get tt => widget.state.timetable;

  void _onTap(TapPosition _, LatLng p) {
    // Pick the closest station within a finger's width at this zoom.
    final mpp = 156543.03 * math.cos(p.latitude * math.pi / 180) / math.pow(2, _zoom);
    final reach = 26 * mpp / 1000;
    Station? best;
    var bestD = reach;
    for (final s in tt.stations) {
      final d = distance(p.latitude, p.longitude, s.lat, s.lng);
      if (d < bestD) {
        bestD = d;
        best = s;
      }
    }
    if (best != null) widget.onStation?.call(best.id);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.state.selected;
    return FlutterMap(
      mapController: widget.controller,
      options: MapOptions(
        initialCenter: mumbai,
        initialZoom: 9.4,
        minZoom: 8.5,
        maxZoom: 17,
        backgroundColor: Palette.field,
        onTap: _onTap,
        onPositionChanged: (camera, _) {
          final z = camera.zoom;
          if ((z - _zoom).abs() > .25) setState(() => _zoom = z);
        },
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        cameraConstraint: CameraConstraint.containCenter(
          bounds: LatLngBounds(const LatLng(18.80, 72.60), const LatLng(20.10, 73.40)),
        ),
      ),
      children: [
        if (MapTiles.enabled)
          TileLayer(
            urlTemplate: MapTiles.url,
            userAgentPackageName: MapTiles.userAgent,
            maxNativeZoom: 18,
            tileDisplay: const TileDisplay.fadeIn(duration: Duration(milliseconds: 260)),
            tileBuilder: (context, tile, _) => ColorFiltered(colorFilter: _night, child: tile),
          ),
        PolylineLayer(polylines: _lines()),
        _TrainsLayer(state: widget.state, focusLine: widget.focusLine, visible: widget.draw >= 1, zoom: _zoom),
        CircleLayer(circles: _stations(selected)),
        if (selected != null) _SelectedPulse(station: tt.stations[selected]),
        if (widget.state.here != null) _HereMarker(here: widget.state.here!),
        const _Attribution(),
      ],
    );
  }

  List<Polyline> _lines() {
    final out = <Polyline>[];
    final glow = <Polyline>[];
    for (final line in tt.lines) {
      final dim = widget.focusLine != null && widget.focusLine != line.index;
      final c = Color(line.color);
      for (final b in line.branches) {
        final pts = _drawn(b, widget.draw);
        if (pts.length < 2) continue;
        glow.add(
          Polyline(
            points: pts,
            color: c.withValues(alpha: dim ? .04 : .22),
            strokeWidth: line.metro ? 9 : 11,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
        out.add(
          Polyline(
            points: pts,
            color: dim ? c.withValues(alpha: .25) : c,
            strokeWidth: line.metro ? 2.6 : 3.4,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
            pattern: line.metro ? StrokePattern.dashed(segments: const [10, 5]) : const StrokePattern.solid(),
          ),
        );
      }
    }
    return [...glow, ...out];
  }

  /// The first [t] of a branch, so lines can draw themselves in.
  List<LatLng> _drawn(Branch b, double t) {
    final s = tt.stations;
    final all = [for (final id in b.stations) LatLng(s[id].lat, s[id].lng)];
    if (t >= 1) return all;
    if (t <= 0) return const [];
    final km = b.length * t;
    final out = <LatLng>[all.first];
    for (var i = 1; i < all.length; i++) {
      if (b.km[i] <= km) {
        out.add(all[i]);
      } else {
        final (lat, lng) = pointAt(b, km, s);
        out.add(LatLng(lat, lng));
        break;
      }
    }
    return out;
  }

  List<CircleMarker> _stations(int? selected) {
    if (widget.draw < .6) return const [];
    final big = _zoom >= 12;
    final out = <CircleMarker>[];
    for (final s in tt.stations) {
      final line = tt.lines[s.lines.first];
      final dim = widget.focusLine != null && !s.lines.contains(widget.focusLine);
      final interchange = s.lines.length > 1 || s.links.isNotEmpty;
      final fav = widget.state.isFavourite(s.id);
      final small = _zoom < 10.8 && !interchange && s.id != selected && !fav;
      final r = small ? 2.0 : (interchange ? 4.2 : 3.2) * (big ? 1.35 : 1) * (s.id == selected ? 1.5 : 1);
      out.add(
        CircleMarker(
          point: LatLng(s.lat, s.lng),
          radius: r,
          color: dim ? Palette.field : (fav ? Palette.signal : (small ? Color(line.color) : Palette.field)),
          borderColor: dim ? Color(line.color).withValues(alpha: .3) : (interchange ? Palette.ink : Color(line.color)),
          borderStrokeWidth: small ? 0 : (interchange ? 2.2 : 1.8),
        ),
      );
    }
    return out;
  }
}

/// Running trains, redrawn about 15 times a second from the schedule.
class _TrainsLayer extends StatefulWidget {
  const _TrainsLayer({required this.state, required this.visible, required this.zoom, this.focusLine});
  final TransitState state;
  final bool visible;
  final double zoom;
  final int? focusLine;

  @override
  State<_TrainsLayer> createState() => _TrainsLayerState();
}

class _TrainsLayerState extends State<_TrainsLayer> {
  List<Position> _running = const [];
  DateTime _last = DateTime(0);

  ValueNotifier<Moment> get _frame => widget.state.clock.frame;

  @override
  void initState() {
    super.initState();
    _frame.addListener(_tick);
    _update();
  }

  @override
  void dispose() {
    _frame.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    final now = DateTime.now();
    if (now.difference(_last).inMilliseconds < 66) return;
    _last = now;
    setState(_update);
  }

  void _update() => _running = widget.state.timetable.running(_frame.value);

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    final tt = widget.state.timetable;
    final s = widget.zoom >= 12.5 ? 1.4 : (widget.zoom < 10.8 ? .75 : 1.0);
    final glow = <CircleMarker>[];
    final core = <CircleMarker>[];
    for (final p in _running) {
      final line = tt.lines[p.train.line];
      final dim = widget.focusLine != null && widget.focusLine != line.index;
      if (dim) continue;
      final pt = LatLng(p.lat, p.lng);
      final c = Color(line.color);
      glow.add(CircleMarker(point: pt, radius: 9 * s, color: c.withValues(alpha: .28)));
      core.add(
        CircleMarker(
          point: pt,
          radius: (p.train.fast ? 4.4 : 3.6) * s,
          color: Palette.ink,
          borderColor: c,
          borderStrokeWidth: 2.4 * s,
        ),
      );
    }
    return CircleLayer(circles: [...glow, ...core]);
  }
}

class _SelectedPulse extends StatefulWidget {
  const _SelectedPulse({required this.station});
  final Station station;

  @override
  State<_SelectedPulse> createState() => _SelectedPulseState();
}

class _SelectedPulseState extends State<_SelectedPulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_c.value);
        return CircleLayer(
          circles: [
            CircleMarker(
              point: LatLng(widget.station.lat, widget.station.lng),
              radius: 8 + 26 * t,
              color: Palette.signal.withValues(alpha: .28 * (1 - t)),
              borderColor: Palette.signal.withValues(alpha: .9 * (1 - t)),
              borderStrokeWidth: 2,
            ),
          ],
        );
      },
    );
  }
}

class _HereMarker extends StatelessWidget {
  const _HereMarker({required this.here});
  final (double, double) here;

  @override
  Widget build(BuildContext context) => CircleLayer(
    circles: [
      CircleMarker(point: LatLng(here.$1, here.$2), radius: 18, color: const Color(0x334D8DFF)),
      CircleMarker(
        point: LatLng(here.$1, here.$2),
        radius: 7,
        color: const Color(0xFF4D8DFF),
        borderColor: Colors.white,
        borderStrokeWidth: 2.5,
      ),
    ],
  );
}

class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topRight,
    child: Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 4, right: 8),
      child: Text(
        '© OpenStreetMap contributors',
        style: Txt.text(9.5, color: Palette.muted.withValues(alpha: .8), weight: FontWeight.w600),
      ),
    ),
  );
}

/// Flies the camera like a plane: up, across and down, rather than a flat slide.
class Flyer {
  Flyer(this.controller, this.vsync);
  final MapController controller;
  final TickerProvider vsync;
  AnimationController? _c;

  void to(LatLng target, double zoom, {Duration duration = Motion.fly, bool reduced = false}) {
    _c?.dispose();
    final cam = controller.camera;
    if (reduced) {
      controller.move(target, zoom);
      return;
    }
    final from = cam.center, z0 = cam.zoom;
    final dist = distance(from.latitude, from.longitude, target.latitude, target.longitude);
    // Rise more for longer hops.
    final lift = (dist / 12).clamp(0.0, 1.6);
    final c = AnimationController(vsync: vsync, duration: duration);
    _c = c;
    c.addListener(() {
      final t = Motion.inOut.transform(c.value);
      final lat = from.latitude + (target.latitude - from.latitude) * t;
      final lng = from.longitude + (target.longitude - from.longitude) * t;
      final z = z0 + (zoom - z0) * t - lift * math.sin(math.pi * c.value);
      controller.move(LatLng(lat, lng), z);
    });
    c.forward();
  }

  void dispose() => _c?.dispose();
}
