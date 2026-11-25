import 'package:material_ui/material_ui.dart';

import '../brand/tokens.dart';
import '../data/timetable.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// Station search. Pops with the chosen station's id.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _text = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = TransitScope.of(context);
    final tt = state.timetable;
    final results = _q.trim().isEmpty ? _suggestions(state) : tt.search(_q);
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Palette.field.withValues(alpha: .97),
      body: Column(
        children: [
          SizedBox(height: top + 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Hero(
              tag: 'search',
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.only(left: 6, right: 8),
                  decoration: BoxDecoration(
                    color: Palette.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Palette.signal.withValues(alpha: .6), width: 1.4),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded, color: Palette.ink),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _text,
                          autofocus: true,
                          onChanged: (v) => setState(() => _q = v),
                          onSubmitted: (_) {
                            if (results.isNotEmpty) Navigator.of(context).pop(results.first.id);
                          },
                          textInputAction: TextInputAction.search,
                          style: Txt.text(16.5, weight: FontWeight.w700),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'Station, code or "VT"',
                            hintStyle: Txt.text(16, color: Palette.faint, weight: FontWeight.w600),
                          ),
                        ),
                      ),
                      if (_q.isNotEmpty)
                        IconButton(
                          tooltip: 'Clear',
                          onPressed: () => setState(() {
                            _text.clear();
                            _q = '';
                          }),
                          icon: const Icon(Icons.close_rounded, color: Palette.muted),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _q.trim().isEmpty
                    ? 'The busiest interchanges'
                    : '${results.length} ${results.length == 1 ? 'station' : 'stations'}',
                style: Txt.note(16),
              ),
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No station called "$_q".\nTry part of the name, like "kurla".',
                      textAlign: TextAlign.center,
                      style: Txt.text(15, color: Palette.muted, height: 1.5),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(12, 6, 12, MediaQuery.paddingOf(context).bottom + 20),
                    itemCount: results.length,
                    itemBuilder: (context, i) => Reveal(
                      key: ValueKey(results[i].id),
                      delay: Duration(milliseconds: 18 * i.clamp(0, 12)),
                      dy: 10,
                      child: _Result(
                        station: results[i],
                        query: _q,
                        onTap: () => Navigator.of(context).pop(results[i].id),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<Station> _suggestions(TransitState state) {
    final tt = state.timetable;
    final favs = [for (final id in state.favourites) tt.stations[id]];
    final hubs = [...tt.stations]
      ..sort((a, b) {
        final c = (b.lines.length + b.links.length).compareTo(a.lines.length + a.links.length);
        return c != 0 ? c : tt.callsAt(b.id).length.compareTo(tt.callsAt(a.id).length);
      });
    return [...favs, ...hubs.where((s) => !favs.contains(s)).take(12)];
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.station, required this.query, required this.onTap});
  final Station station;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = TransitScope.of(context);
    final tt = state.timetable;
    return Pressable(
      onTap: onTap,
      scale: .98,
      label: station.name,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Palette.surface),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Palette.card, borderRadius: BorderRadius.circular(12)),
              child: Icon(
                station.metro ? Icons.subway_rounded : Icons.train_rounded,
                size: 20,
                color: Color(tt.lines[station.lines.first].color),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Highlighted(station.name, query),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [for (final l in station.lines) LineChip(tt.lines[l], small: true)],
                  ),
                ],
              ),
            ),
            if (state.isFavourite(station.id)) const Icon(Icons.star_rounded, color: Palette.signal, size: 20),
            if (!station.metro) ...[
              const SizedBox(width: 6),
              Text(station.code, style: Txt.label(11, color: Palette.faint)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The station name with the typed part in yellow.
class _Highlighted extends StatelessWidget {
  const _Highlighted(this.text, this.query);
  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final base = Txt.text(16, weight: FontWeight.w800);
    final q = query.trim().toLowerCase();
    final i = q.isEmpty ? -1 : text.toLowerCase().indexOf(q);
    if (i < 0) return Text(text, style: base);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, i), style: base),
          TextSpan(
            text: text.substring(i, i + q.length),
            style: base.copyWith(color: Palette.signal),
          ),
          TextSpan(text: text.substring(i + q.length), style: base),
        ],
      ),
    );
  }
}
