"""Exports the MetroMitra network map as SVG from a built dataset.

Everything drawn comes from the dataset (stations, lines, colours, names in
English and Hindi, order of stops). No third-party map artwork is used.
Run:  python tools/export_map.py [dataset.sqlite] [out.svg]
Then PNG / PDF are made from the SVG with headless Chrome (see docs/map.md),
which also shapes the Devanagari text correctly.
"""
import math
import sqlite3
import sys
from xml.sax.saxutils import escape

DB = sys.argv[1] if len(sys.argv) > 1 else 'build/pipeline/check.sqlite'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'map/MetroMitra_map.svg'

W, H = 8400, 9000          # canvas (large: every station gets a readable label)
TOP, BOTTOM = 300, 520     # title band, legend band
PAD = 340

db = sqlite3.connect(DB)
c = db.cursor()
meta = dict(c.execute('select key, value from meta'))
lines = {r[0]: r for r in c.execute(
    "select id, name_en, name_hi, color_hex, sort from line where status='open' order by sort, id")}
stations = {r[0]: r for r in c.execute(
    "select id, name_en, name_hi, lat, lng from station where status='open'")}
line_of_service = dict(c.execute('select id, line_id from line_service'))
stops = {}
for sid, seq, st in c.execute('select service_id, seq, station_id from service_stop order by service_id, seq'):
    stops.setdefault(sid, []).append(st)
lines_at = {}
for st, ln in c.execute('select station_id, line_id from station_line'):
    lines_at.setdefault(st, set()).add(ln)

# same projection as MapGeometry: x = (lng - lng0) * cos(lat0), y = -(lat - lat0)
lats = [s[3] for s in stations.values()]
lngs = [s[4] for s in stations.values()]
lat0 = (min(lats) + max(lats)) / 2
lng0 = (min(lngs) + max(lngs)) / 2
k = math.cos(math.radians(lat0))
pts = {i: ((s[4] - lng0) * k, -(s[3] - lat0)) for i, s in stations.items()}
minx = min(p[0] for p in pts.values()); maxx = max(p[0] for p in pts.values())
miny = min(p[1] for p in pts.values()); maxy = max(p[1] for p in pts.values())
scale = min((W - 2 * PAD) / (maxx - minx), (H - TOP - BOTTOM - 2 * PAD) / (maxy - miny))
ox = (W - (maxx - minx) * scale) / 2 - minx * scale
oy = TOP + PAD + ((H - TOP - BOTTOM - 2 * PAD) - (maxy - miny) * scale) / 2 - miny * scale
xy = {i: (p[0] * scale + ox, p[1] * scale + oy) for i, p in pts.items()}

out = []
a = out.append
a(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
a('<style>text{font-family:"Inter","Noto Sans Devanagari","Segoe UI",sans-serif;fill:#14213d}'
  'text.en,text.hi{paint-order:stroke;stroke:#fbfcfe;stroke-width:7px;stroke-linejoin:round}.hi{font-size:23px;fill:#4a5568}.en{font-size:28px;font-weight:600}'
  '.t{font-size:130px;font-weight:700;fill:#fff}.s{font-size:50px;fill:#dbe7ff}'
  '.lg{font-size:38px}.small{font-size:30px;fill:#4a5568}</style>')
a(f'<rect width="{W}" height="{H}" fill="#fbfcfe"/>')
a(f'<rect width="{W}" height="{TOP}" fill="#0b3d91"/>')
a(f'<text class="t" x="{PAD}" y="170">MetroMitra</text>')
a(f'<text class="s" x="{PAD}" y="250">Delhi Metro map · दिल्ली मेट्रो नक्शा · draft data, not verified</text>')

# segments, one per line and pair
seen = set()
by_line = {}
for sid, seq in stops.items():
    ln = line_of_service.get(sid)
    for u, v in zip(seq, seq[1:]):
        if u == v or u not in xy or v not in xy:
            continue
        key = (ln, *sorted((u, v)))
        if key in seen:
            continue
        seen.add(key)
        by_line.setdefault(ln, []).append((u, v))
for ln, segs in by_line.items():
    col = lines[ln][3] if ln in lines else '#607d8b'
    for u, v in segs:
        a(f'<line x1="{xy[u][0]:.1f}" y1="{xy[u][1]:.1f}" x2="{xy[v][0]:.1f}" y2="{xy[v][1]:.1f}" '
          f'stroke="{col}" stroke-width="12" stroke-linecap="round"/>')

# stations
for i, (x, y) in xy.items():
    inter = len(lines_at.get(i, ())) > 1
    r = 16 if inter else 8
    a(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="#fff" stroke="#14213d" stroke-width="{6 if inter else 4}"/>')
    if inter:
        a(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="5" fill="#14213d"/>')

# labels: greedy placement, 8 candidate positions, interchanges first
placed = []


def text_w(s, px):
    return sum(px * (0.95 if ord(ch) > 0x900 else 0.56) for ch in s)


def overlaps(r):
    for q in placed:
        if r[0] < q[2] and r[2] > q[0] and r[1] < q[3] and r[3] > q[1]:
            return True
    return False


order = sorted(stations, key=lambda i: (-len(lines_at.get(i, ())), stations[i][1]))
for i in order:
    _, en, hi, _, _ = stations[i]
    x, y = xy[i]
    w = max(text_w(en, 28), text_w(hi or '', 23))
    h = 62 if hi else 34
    cands = [
        ('start', x + 24, y - h / 2, x + 24),
        ('end', x - 24 - w, y - h / 2, x - 24),
        ('middle', x - w / 2, y - 30 - h, x),
        ('middle', x - w / 2, y + 28, x),
        ('start', x + 22, y - h - 14, x + 22),
        ('end', x - 22 - w, y - h - 14, x - 22),
        ('start', x + 22, y + 14, x + 22),
        ('end', x - 22 - w, y + 14, x - 22),
    ]
    for anchor, left, top, ax in cands:
        rect = (left, top, left + w, top + h)
        if overlaps(rect) or rect[0] < 10 or rect[2] > W - 10 or rect[1] < TOP + 10 or rect[3] > H - BOTTOM:
            continue
        placed.append(rect)
        ty = top + 27
        a(f'<text class="en" x="{ax:.1f}" y="{ty:.1f}" text-anchor="{anchor}">{escape(en)}</text>')
        if hi:
            a(f'<text class="hi" x="{ax:.1f}" y="{ty + 29:.1f}" text-anchor="{anchor}">{escape(hi)}</text>')
        break

# legend
ly = H - BOTTOM + 100
a(f'<rect y="{H - BOTTOM}" width="{W}" height="{BOTTOM}" fill="#eef2f9"/>')
x = PAD
for ln, (lid, en, hi, col, _) in lines.items():
    a(f'<rect x="{x}" y="{ly - 30}" width="90" height="20" rx="10" fill="{col}"/>')
    a(f'<text class="lg" x="{x + 110}" y="{ly - 8}">{escape(en)}</text>')
    a(f'<text class="small" x="{x + 110}" y="{ly + 36}">{escape(hi or "")}</text>')
    x += 800
    if x > W - 900:
        x = PAD
        ly += 110
ly += 80
a(f'<circle cx="{PAD + 17}" cy="{ly - 10}" r="17" fill="#fff" stroke="#14213d" stroke-width="6"/>'
  f'<circle cx="{PAD + 17}" cy="{ly - 10}" r="5" fill="#14213d"/>')
a(f'<text class="lg" x="{PAD + 55}" y="{ly}">Interchange · इंटरचेंज</text>')
a(f'<circle cx="{PAD + 760}" cy="{ly - 10}" r="9" fill="#fff" stroke="#14213d" stroke-width="4"/>')
a(f'<text class="lg" x="{PAD + 800}" y="{ly}">Station · स्टेशन</text>')
a(f'<text class="small" x="{PAD}" y="{H - 80}">Map not to scale. Map and station data © OpenStreetMap contributors (ODbL); '
  f'Wikidata (CC0); MetroMitra overlays. Dataset {escape(meta.get("dataset_version", "?"))} ({escape(meta.get("stage", "?"))}).</text>')
a(f'<text class="small" x="{PAD}" y="{H - 30}">MetroMitra is an independent app and is not affiliated with DMRC. '
  f'Check station signs and DMRC for official information.</text>')
a('</svg>')
open(OUT, 'w', encoding='utf8', newline='\n').write('\n'.join(out))
print(f'{OUT}: {len(stations)} stations, {len(lines)} lines, {len(placed)} labelled')
