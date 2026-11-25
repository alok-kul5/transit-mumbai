"""Builds assets/transit.json, the timetable the app ships with.

Sources (both open, both credited in the README):
  * Suburban timetable: the Rush Hour project's SQLite database, parsed from the
    official Western and Central Railway timetable PDFs. MIT licence.
    https://github.com/SphericalKat/rush-hour
  * Metro stations and line order: OpenStreetMap route relations, via Overpass.
    (c) OpenStreetMap contributors, ODbL.

Downloads are cached in tool/.cache, so a rebuild works offline.

Run:  py -3.11 tool/build_data.py
"""

from __future__ import annotations

import json
import math
import sqlite3
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / 'tool' / '.cache'
OUT = ROOT / 'assets' / 'transit.json'

# Pinned so the bundled data is reproducible.
RUSH_HOUR_COMMIT = 'e78b04982fcd7cb5249f72cae0ca6a9d8e9fecfb'
RUSH_HOUR_DB = f'https://raw.githubusercontent.com/SphericalKat/rush-hour/{RUSH_HOUR_COMMIT}/backend/mumbai_trains.db'
OVERPASS = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter']
USER_AGENT = 'transit-mumbai-data-tool/1.0 (+https://github.com/alok-kul5/transit-mumbai)'

# One relation per metro line, in one direction. The other direction is the reverse.
METRO_RELATIONS = {'M1': 3808111, 'M2A': 13989912, 'M7': 13989915, 'M3': 7898597}

# Suburban lines. The Rush Hour line_stations order is not geographic, so each line
# is written out here as branches of station codes, checked against the database.
_CR_CORE = ('CSTM MSD SNRD BY CHG CRD PR DR MTN SIN CLA VVH GC VK KJMG BND NHU MLND TNA KLVA MBQ DIVA KOPR DI THK KYN')
_HB_SOUTH = 'CSTM MSD SNRD DKRD RRD CTGN SVE VDLR'
_HB_EAST = 'GTBN CHF CLA TKNG CMBR GV MNKD VSH SNCR JNJ NEU SWDV BEPR KHAG MANR KNDS PNVL'
_HB_WEST = 'KCE MM BA KHAR STC VLP ADH JOS RMMD GMN'
_TH = 'TNA DGHA AIRL RABE GNSL KPHN TUH'
RAIL_LINES = [
    {
        'id': 'WR', 'db': 'WR-ML', 'name': 'Western', 'color': '#FF6A3D',
        'branches': [('Churchgate – Dahanu Road', 'CCG MEL CYR GTR BCT MX PL PBHD DR MRU MM BA KHAR STC VLP ADH JOS '
                      'RMMD GMN MDD KILE BVI DIC MIRA BYR NIG BSR NSP VR VTN SAH KLV PLG UOI BOR VGN DRD')],
    },
    {
        'id': 'CR', 'db': 'CR-ML', 'name': 'Central', 'color': '#C6F432',
        'branches': [
            ('CSMT – Kasara', _CR_CORE + ' SHAD ABY TLA KDV VSD ASO ATG THST KE UMBL KSRA'),
            ('CSMT – Khopoli', _CR_CORE + ' VLDI ULNR ABH BUD VGI SHLU NRL BVS KJT PDI KVL DVL LWJ KHPI'),
        ],
    },
    {
        'id': 'HB', 'db': 'CR-HB', 'name': 'Harbour', 'color': '#2BD9A8',
        'branches': [
            ('CSMT – Panvel', f'{_HB_SOUTH} {_HB_EAST}'),
            ('CSMT – Goregaon', f'{_HB_SOUTH} {_HB_WEST}'),
            ('Goregaon – Panvel', ' '.join(reversed(_HB_WEST.split())) + f' VDLR {_HB_EAST}'),
        ],
    },
    {
        'id': 'TH', 'db': 'CR-TH', 'name': 'Trans-Harbour', 'color': '#F25CA2',
        'branches': [
            ('Thane – Panvel', f'{_TH} JNJ NEU SWDV BEPR KHAG MANR KNDS PNVL'),
            ('Thane – Vashi', f'{_TH} SNCR VSH'),
        ],
    },
    {
        'id': 'UR', 'db': 'CR-UR', 'name': 'Uran', 'color': '#B48CFF',
        'branches': [
            ('Nerul – Uran', 'NEU SWDV TRGR BMDG KRKP GVHN SMTK DRNG URAN'),
            ('Belapur – Uran', 'BEPR TRGR BMDG KRKP GVHN SMTK DRNG URAN'),
        ],
    },
]

# Metro lines publish frequencies, not timetables. These are the operators' typical
# service hours and headways as reported in late 2026; the app labels every metro
# time as an estimate. Peaks are 08:00–11:00 and 17:00–21:00.
METRO_LINES = [
    {'id': 'M1', 'name': 'Metro 1', 'long': 'Versova – Ghatkopar', 'color': '#3E7BFF',
     'first': '05:30', 'last': '23:50', 'peak': 4, 'offpeak': 7},
    {'id': 'M2A', 'name': 'Metro 2A', 'long': 'Andheri West – Dahisar East', 'color': '#FFD23F',
     'first': '05:50', 'last': '23:00', 'peak': 6, 'offpeak': 9},
    {'id': 'M7', 'name': 'Metro 7', 'long': 'Dahisar East – Gundavali', 'color': '#FF3355',
     'first': '05:50', 'last': '23:00', 'peak': 6, 'offpeak': 9},
    {'id': 'M3', 'name': 'Metro 3', 'long': 'Aarey JVLR – Cuffe Parade', 'color': '#22D3EE',
     'first': '05:55', 'last': '23:00', 'peak': 5, 'offpeak': 8},
]

# Station names the timetable writes in capitals, and a few clean-ups.
NAME_FIX = {
    'CSMT': 'CSMT', 'GTB NAGAR': 'GTB Nagar', 'MAHIM JN': 'Mahim Jn', 'DIVA JN': 'Diva Jn',
    'BELAPUR CBD': 'CBD Belapur', 'KOPARKHAIRNE': 'Kopar Khairane', 'SEAWOOD DARAVE KARAVE': 'Seawood Darave',
    'SANTA CRUZ': 'Santacruz', 'TILAKNAGAR': 'Tilak Nagar', 'KINGS CIRCLE': "King's Circle",
    'ULHAS NAGAR': 'Ulhasnagar', 'VIDYAVIHAR': 'Vidyavihar', 'NALLA SOPARA': 'Nalasopara',
}
METRO_NAME_FIX = {
    'Western Express Highway (eastbound)': 'WEH',
    'Marol Naka (Line 1)': 'Marol Naka',
    'Marol Naka (Line 3)': 'Marol Naka',
    'Dahisar (East) [Line 2]': 'Dahisar East',
    'Dahisar (East) [Line 7]': 'Dahisar East',
    'Chhatrapati Shivaji Maharaj Terminus': 'CSMT Metro',
    'Jagannath Shankar Sheth Metro': 'Mumbai Central Metro',
    'Andheri (West)': 'Andheri West',
    'Goregaon (West)': 'Goregaon West',
    'Kandivali (West)': 'Kandivali West',
    'Borivali (West)': 'Borivali West',
    'Goregaon (East)': 'Goregaon East',
    'Jogeshwari (East)': 'Jogeshwari East',
    'Bandra Kurla Complex (BKC)': 'BKC',
    'Mandapeshwar - I.C. Colony': 'Mandapeshwar',
    'Chakala - J.B. Nagar': 'Chakala',
    'MIDC - Andheri': 'MIDC',
    'CSMIA International T2': 'Airport T2',
    'CSMIA Domestic': 'Airport T1',
}

DAYS = {  # bit 0 = Monday ... bit 6 = Sunday
    'daily': 0b1111111, 'not_sunday': 0b0111111, 'sunday_only': 0b1000000, 'weekdays_only': 0b0011111,
    'not_saturday': 0b1011111, 'not_fri_sat': 0b1001111, 'not_thu_fri': 0b1100111,
}
FAST, AC, LADIES = 1, 2, 4


def fetch(url: str, dest: Path, data: bytes | None = None) -> Path:
    if dest.exists():
        return dest
    CACHE.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, data=data, headers={'User-Agent': USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as r:
        dest.write_bytes(r.read())
    return dest


def overpass_metro() -> dict:
    dest = CACHE / 'metro_osm.json'
    ids = ','.join(str(i) for i in METRO_RELATIONS.values())
    q = f'[out:json][timeout:90];relation(id:{ids});out body;node(r);out body qt;'
    body = urllib.parse.urlencode({'data': q}).encode()
    last: Exception | None = None
    for url in OVERPASS:
        try:
            fetch(url, dest, body)
            data = json.loads(dest.read_text(encoding='utf8'))
            if data.get('elements'):
                return data
        except Exception as e:  # busy server: try the next mirror
            last = e
        dest.unlink(missing_ok=True)
    raise SystemExit(f'Overpass unavailable: {last}')


def title(name: str) -> str:
    if name in NAME_FIX:
        return NAME_FIX[name]
    return ' '.join(w.capitalize() for w in name.split())


def km(a: tuple[float, float], b: tuple[float, float]) -> float:
    la1, lo1, la2, lo2 = map(math.radians, (*a, *b))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(h))


def is_subsequence(stops: list[str], branch: list[str]) -> bool:
    it = iter(branch)
    return all(s in it for s in stops)


def build() -> dict:
    db = sqlite3.connect(fetch(RUSH_HOUR_DB, CACHE / f'rush_hour_{RUSH_HOUR_COMMIT[:8]}.db'))
    q = db.execute

    stations: list[list] = []
    index: dict[str, int] = {}
    by_db_id: dict[int, str] = {}
    for sid, name, code, lat, lng in q('select id, name, code, lat, lng from stations order by id'):
        by_db_id[sid] = code
        index[code] = len(stations)
        stations.append([code, title(name), round(lat, 5), round(lng, 5)])

    lines: list[dict] = []
    trains: list[list] = []
    dropped = 0
    notes: list[str] = []
    for li, spec in enumerate(RAIL_LINES):
        (line_id,) = q('select id from lines where short_name = ?', (spec['db'],)).fetchone()
        branches = [(name, codes.split()) for name, codes in spec['branches']]
        for _, codes in branches:
            missing = [c for c in codes if c not in index]
            if missing:
                raise SystemExit(f'{spec["id"]}: unknown station codes {missing}')
        in_db = {by_db_id[s] for (s,) in q('select station_id from line_stations where line_id = ?', (line_id,))}
        covered = {c for _, codes in branches for c in codes}
        if in_db - covered:
            raise SystemExit(f'{spec["id"]}: stations not on any branch {sorted(in_db - covered)}')
        lines.append({
            'id': spec['id'], 'name': spec['name'], 'kind': 'rail', 'color': spec['color'],
            'branches': [{'name': n, 'stations': [index[c] for c in codes]} for n, codes in branches],
        })

        rows = q('select id, number, is_ac, is_fast, runs_on, note from trains where line_id = ? order by id', (line_id,))
        for tid, number, is_ac, is_fast, runs_on, note in rows.fetchall():
            stops = q('select station_id, departure, platform from stops where train_id = ? order by stop_sequence',
                      (tid,)).fetchall()
            codes = [by_db_id[s] for s, _, _ in stops]
            if len(codes) < 2:
                dropped += 1
                continue
            branch = next((bi for bi, (_, b) in enumerate(branches)
                           if is_subsequence(codes, b) or is_subsequence(codes, b[::-1])), None)
            if branch is None:
                dropped += 1
                continue
            flags = (FAST if is_fast else 0) | (AC if is_ac else 0) | (LADIES if 'Ladies' in note else 0)
            # "General on Sun": the AC or ladies rake runs as an ordinary train that day.
            general = 0b1100000 if 'Sat & Sun' in note else 0b1000000 if 'General on Sun' in note else 0
            first = stops[0][1]
            deltas = [(b[1] - a[1]) % 1440 for a, b in zip(stops, stops[1:])]
            platforms = [p or '' for _, _, p in stops]
            row = [li, branch, number, flags, DAYS[runs_on], general, first,
                   [index[c] for c in codes], deltas]
            if any(platforms):
                row.append(platforms)
            trains.append(row)
            if note and note not in notes:
                notes.append(note)

    # Metro: stations from OSM, in relation order.
    osm = overpass_metro()
    nodes = {e['id']: e for e in osm['elements'] if e['type'] == 'node'}
    rels = {e['id']: e for e in osm['elements'] if e['type'] == 'relation'}
    rail_coords = {i: (s[2], s[3]) for i, s in enumerate(stations)}
    for spec in METRO_LINES:
        rel = rels[METRO_RELATIONS[spec['id']]]
        seq: list[int] = []
        for m in rel['members']:
            if m['type'] != 'node' or not m['role'].startswith('stop') or m['ref'] not in nodes:
                continue
            n = nodes[m['ref']]
            tags = n.get('tags', {})
            raw = tags.get('name:en') or tags.get('name')
            name = METRO_NAME_FIX.get(raw, raw)
            code = f'{spec["id"]}:{name}'
            if code not in index:
                index[code] = len(stations)
                stations.append([code, name, round(n['lat'], 5), round(n['lon'], 5)])
            seq.append(index[code])
        # Minutes between stops: about 34 km/h door to door, never under 2 minutes.
        runs = [max(2, round(km(tuple(stations[a][2:4]), tuple(stations[b][2:4])) / 34 * 60))
                for a, b in zip(seq, seq[1:])]
        lines.append({
            'id': spec['id'], 'name': spec['name'], 'kind': 'metro', 'color': spec['color'],
            'branches': [{'name': spec['long'], 'stations': seq}],
            'service': {k: spec[k] for k in ('first', 'last', 'peak', 'offpeak')} | {'runs': runs},
        })

    # Interchanges: a metro station within 450 m of a suburban station (or another metro).
    links: list[list[int]] = []
    metro_ids = [i for i, s in enumerate(stations) if ':' in s[0]]
    for m in metro_ids:
        for o, s in enumerate(stations):
            if o == m or (':' in s[0] and o < m):
                continue
            if stations[m][0].split(':')[0] == s[0].split(':')[0]:
                continue
            if km(tuple(stations[m][2:4]), tuple(s[2:4])) < 0.45:
                links.append([m, o])

    print(f'{len(stations)} stations, {len(lines)} lines, {len(trains)} trains, {dropped} dropped', file=sys.stderr)
    return {
        'meta': {
            'version': 1,
            'sources': [
                {'name': 'Rush Hour timetable (Western & Central Railway PDFs)',
                 'url': 'https://github.com/SphericalKat/rush-hour', 'license': 'MIT', 'commit': RUSH_HOUR_COMMIT},
                {'name': 'OpenStreetMap', 'url': 'https://www.openstreetmap.org/copyright', 'license': 'ODbL'},
            ],
            'flags': {'fast': FAST, 'ac': AC, 'ladies': LADIES},
            'train': ['line', 'branch', 'number', 'flags', 'days', 'generalDays', 'first', 'stations', 'deltas',
                      'platforms?'],
        },
        'stations': stations,
        'lines': lines,
        'links': links,
        'trains': trains,
    }


def main() -> None:
    data = build()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, separators=(',', ':'), ensure_ascii=False), encoding='utf8')
    print(f'wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size // 1024} KB)', file=sys.stderr)


if __name__ == '__main__':
    main()
