"""Iris icon round 3: variations that look like an iris.

1 bloom       : front view of an iris flower. Three standards rise and lean in, three falls droop
                out and down, each with a gold beard. Mirror-symmetric. Violet glass.
2 bloom-teal  : the same flower in the app's teal.
3 fleur       : the fleur-de-lis, the classic stylised iris: a tall centre petal, two side petals
                curling out and down, a gold band, three short lobes below.
4 flat        : the bloom as flat two-tone shapes on a pale ground; no rims, just colour.
5 petal-eye   : the eye's iris made of petals: a ring of overlapping glass petals around a plain
                pupil, ringed in gold. Iris the eye and iris the flower at once.
"""
import math, pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent

def rot(x, y, a, cx, cy):
    t = math.radians(a); return cx + x * math.cos(t) - y * math.sin(t), cy + x * math.sin(t) + y * math.cos(t)

def P(p): return f"{p[0]:.1f},{p[1]:.1f}"

def petal(cx, cy, a, L, W, bend=0.0, base=0.0, tipw=0.62):
    """Teardrop petal from (cx, cy) pointing at a (0 up, clockwise). `bend` shifts the tip
    sideways (in petal units) so the petal curves."""
    b = bend
    pts = [(0, -base), (W * 0.95, -base - L * 0.3), (W * tipw + b, -base - L * 0.95), (b, -base - L),
           (-W * tipw + b, -base - L * 0.95), (-W * 0.95, -base - L * 0.3), (0, -base)]
    q = [rot(x, y, a, cx, cy) for x, y in pts]
    return f"M{P(q[0])} C{P(q[1])} {P(q[2])} {P(q[3])} C{P(q[4])} {P(q[5])} {P(q[6])}Z"

def frame(bg, glow, body, extra_defs=""):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
  <clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
  <linearGradient id="bg" x1="0.2" y1="0" x2="0.8" y2="1"><stop offset="0" stop-color="{bg[0]}"/><stop offset="0.55" stop-color="{bg[1]}"/><stop offset="1" stop-color="{bg[2]}"/></linearGradient>
  <radialGradient id="glow" cx="0.3" cy="0.12" r="0.8"><stop offset="0" stop-color="#FFFFFF" stop-opacity="{glow}"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>
  <linearGradient id="rim" x1="0.2" y1="0" x2="0.8" y2="1"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.9"/><stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.12"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0.5"/></linearGradient>
  <linearGradient id="edge" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.45"/><stop offset="0.35" stop-color="#FFFFFF" stop-opacity="0.04"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0.18"/></linearGradient>
  <filter id="tileShadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.3"/></filter>
  {extra_defs}
</defs>
<g filter="url(#tileShadow)"><g clip-path="url(#tile)">
  <rect x="100" y="100" width="824" height="824" fill="url(#bg)"/>
  <rect x="100" y="100" width="824" height="824" fill="url(#glow)"/>
  {body}
</g><rect x="101.5" y="101.5" width="821" height="821" rx="183.5" fill="none" stroke="url(#edge)" stroke-width="3"/></g>
</svg>'''

def glassy(d, fill, op, rim=True, rim_w=3):
    s = f'<path d="{d}" fill="{fill}" fill-opacity="{op}"/>'
    return s + (f'<path d="{d}" fill="none" stroke="url(#rim)" stroke-width="{rim_w}"/>' if rim else "")

GOLD = "#FFC94A"

# ---------- the bloom (front view) ----------
BX, BY = 512, 540
def bloom_shapes():
    """(standards, falls, beards) path lists for the front-view iris."""
    standards = [petal(BX, BY - 10, 0, 300, 112, 0, 20),
                 petal(BX - 14, BY - 4, -24, 262, 100, 46, 20),
                 petal(BX + 14, BY - 4, 24, 262, 100, -46, 20)]
    falls = [petal(BX - 8, BY + 10, -118, 270, 140, -70, 10),
             petal(BX + 8, BY + 10, 118, 270, 140, 70, 10),
             petal(BX, BY + 16, 180, 210, 128, 0, 10)]
    beards = [petal(BX - 8, BY + 10, -118, 120, 16, -12, 40),
              petal(BX + 8, BY + 10, 118, 120, 16, 12, 40),
              petal(BX, BY + 16, 180, 100, 16, 0, 36)]
    return standards, falls, beards

PAL = {
    "violet": dict(light=dict(bg=["#8C74FF", "#5A3FE0", "#2E1A9E"], glow=0.2, std=("#FFFFFF", 0.32), fall=("#FFFFFF", 0.5)),
                   dark=dict(bg=["#2A2146", "#16112A", "#08060F"], glow=0.06, std=("#B9A8FF", 0.3), fall=("#8E78FF", 0.45))),
    "teal": dict(light=dict(bg=["#1AA6DA", "#0378A8", "#00507F"], glow=0.2, std=("#FFFFFF", 0.32), fall=("#FFFFFF", 0.5)),
                 dark=dict(bg=["#1E3A44", "#0E1E24", "#050C0F"], glow=0.06, std=("#8FE0F5", 0.28), fall=("#2FB4E3", 0.45))),
}

def bloom(palette, dark):
    t = PAL[palette]["dark" if dark else "light"]
    st, fa, be = bloom_shapes()
    body = "".join(glassy(d, *t["std"]) for d in st) + "".join(glassy(d, *t["fall"]) for d in fa)
    body += "".join(f'<path d="{d}" fill="{GOLD}"/>' for d in be)
    return frame(t["bg"], t["glow"], body)

# ---------- fleur ----------
FX, FY = 512, 520
def fleur_shapes():
    centre = petal(FX, FY, 0, 320, 120, 0, 0, 0.5)
    sides = [petal(FX - 30, FY + 10, -62, 240, 92, -95, 0), petal(FX + 30, FY + 10, 62, 240, 92, 95, 0)]
    lower = [petal(FX, FY + 40, 180, 150, 70, 0, 0), petal(FX - 30, FY + 40, -150, 150, 66, -40, 0),
             petal(FX + 30, FY + 40, 150, 150, 66, 40, 0)]
    band = f'<rect x="{FX - 130}" y="{FY + 14}" width="260" height="46" rx="23"'
    return centre, sides, lower, band

def fleur(dark):
    t = PAL["violet"]["dark" if dark else "light"]
    c, sides, lower, band = fleur_shapes()
    body = "".join(glassy(d, *t["std"]) for d in lower) + "".join(glassy(d, *t["fall"]) for d in sides)
    body += glassy(c, *t["fall"])
    body += f'{band} fill="{GOLD}"/>'
    return frame(t["bg"], t["glow"], body)

# ---------- flat ----------
def flat(dark):
    st, fa, be = bloom_shapes()
    if dark:
        bg, s, f = ["#1D1A2B", "#141220", "#0B0A12"], "#6F5BE8", "#9B8BFF"
    else:
        bg, s, f = ["#F6F3FF", "#ECE6FF", "#DCD2FF"], "#7B63F2", "#4A30C9"
    body = "".join(f'<path d="{d}" fill="{s}"/>' for d in st) + "".join(f'<path d="{d}" fill="{f}"/>' for d in fa)
    body += "".join(f'<path d="{d}" fill="{GOLD}"/>' for d in be)
    return frame(bg, 0.0 if dark else 0.3, body)

# ---------- petal eye ----------
EX, EY = 512, 520
def petal_eye(dark):
    t = PAL["violet"]["dark" if dark else "light"]
    n = 12
    body = []
    for i in range(n):  # back ring, offset half a step
        body.append(glassy(petal(EX, EY, i * 360 / n + 15, 230, 62, 0, 96), *t["std"], rim_w=2.5))
    for i in range(n):
        body.append(glassy(petal(EX, EY, i * 360 / n, 210, 58, 0, 96), *t["fall"], rim_w=2.5))
    body.append(f'<circle cx="{EX}" cy="{EY}" r="104" fill="none" stroke="{GOLD}" stroke-width="10"/>')
    body.append(f'<circle cx="{EX}" cy="{EY}" r="90" fill="{"#05040A" if dark else "#170C4A"}"/>')
    return frame(t["bg"], t["glow"], "".join(body))

# ---------- petal iris: the petal flower with an eye's iris at its heart ----------
IR, PUP = 132, 48
def iris_centre(dark):
    rad = (f'<radialGradient id="irisFill" gradientUnits="userSpaceOnUse" cx="{EX}" cy="{EY}" r="{IR}">'
           f'<stop offset="0.36" stop-color="#F2B640"/><stop offset="0.5" stop-color="#E0A35A"/><stop offset="0.68" stop-color="#9A7BFF"/>'
           f'<stop offset="0.85" stop-color="{"#4A30C9" if not dark else "#3F25A8"}"/><stop offset="1" stop-color="#21115E"/></radialGradient>')
    out = [f'<circle cx="{EX}" cy="{EY}" r="{IR}" fill="url(#irisFill)"/>']
    lines = []
    for k in range(36):
        a = math.radians(k * 10 + 5)
        r0, r1 = PUP + 10, IR - 14 - (8 if k % 2 else 0)
        lines.append(f'<line x1="{EX + r0 * math.cos(a):.1f}" y1="{EY + r0 * math.sin(a):.1f}" x2="{EX + r1 * math.cos(a):.1f}" y2="{EY + r1 * math.sin(a):.1f}"/>')
    out.append(f'<g stroke="#FFFFFF" stroke-opacity="0.28" stroke-width="5" stroke-linecap="round">{"".join(lines)}</g>')
    pts = []
    for k in range(48):
        a = math.radians(360 * k / 48); r = PUP + 34 + (4 if k % 2 else -4)
        pts.append(f"{EX + r * math.cos(a):.1f},{EY + r * math.sin(a):.1f}")
    out.append(f'<polygon points="{" ".join(pts)}" fill="none" stroke="#FFD978" stroke-opacity="0.85" stroke-width="3.5" stroke-linejoin="round"/>')
    out.append(f'<circle cx="{EX}" cy="{EY}" r="{IR - 4}" fill="none" stroke="#120838" stroke-opacity="0.75" stroke-width="9"/>')
    out.append(f'<circle cx="{EX}" cy="{EY}" r="{PUP}" fill="#07040F"/>')
    out.append(f'<circle cx="{EX - 17}" cy="{EY - 19}" r="10" fill="#FFFFFF"/>')
    return rad, "".join(out)

def petal_iris(dark):
    t = PAL["violet"]["dark" if dark else "light"]
    n = 12
    body = []
    for i in range(n):
        body.append(glassy(petal(EX, EY, i * 360 / n + 15, 222, 64, 0, IR - 30), *t["std"], rim_w=2.5))
    for i in range(n):
        body.append(glassy(petal(EX, EY, i * 360 / n, 200, 60, 0, IR - 30), *t["fall"], rim_w=2.5))
    rad, centre = iris_centre(dark)
    body.append(centre)
    return frame(t["bg"], t["glow"], "".join(body), rad)

def petal_iris_glyph():
    n = 12
    lay = [(petal(EX, EY, i * 360 / n, 222, 64, 0, IR - 30), 0.5) for i in range(n)]
    g = glyph(lay)
    ring = (f'<path fill-rule="evenodd" d="M{EX - IR},{EY} a{IR},{IR} 0 1,0 {2 * IR},0 a{IR},{IR} 0 1,0 {-2 * IR},0Z '
            f'M{EX - 80},{EY} a80,80 0 1,0 160,0 a80,80 0 1,0 -160,0Z"/><circle cx="{EX}" cy="{EY}" r="46"/>')
    return g.replace("</g></svg>", ring + "</g></svg>")

# ---------- glyphs: the same shapes scaled into a 24 pt template ----------
def glyph(layers):
    """layers: list of (path, opacity). Content area ~ 170..870 maps to 0..24."""
    s = 24 / 720
    g = "".join(f'<path d="{d}" fill-opacity="{o}"/>' for d, o in layers)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="#000">'
            f'<g transform="scale({s:.5f}) translate(-152,-150)">{g}</g></svg>')

def bloom_glyph():
    st, fa, be = bloom_shapes()
    return glyph([(d, 0.5) for d in st] + [(d, 1) for d in fa])

def fleur_glyph():
    c, sides, lower, band = fleur_shapes()
    g = glyph([(d, 0.5) for d in lower] + [(d, 1) for d in sides] + [(c, 1)])
    return g

def eye_glyph():
    n = 12
    lay = [(petal(EX, EY, i * 360 / n, 230, 62, 0, 96), 0.55) for i in range(n)]
    g = glyph(lay)
    return g.replace("</g></svg>", f'<circle cx="{EX}" cy="{EY}" r="90"/></g></svg>')

V = [("1-bloom", lambda d: bloom("violet", d), bloom_glyph),
     ("2-bloom-teal", lambda d: bloom("teal", d), bloom_glyph),
     ("3-fleur", fleur, fleur_glyph),
     ("4-flat", flat, bloom_glyph),
     ("5-petal-eye", petal_eye, eye_glyph),
     ("6-petal-iris", petal_iris, petal_iris_glyph)]
for name, fn, gl in V:
    d = OUT / name; d.mkdir(exist_ok=True)
    (d / "AppIcon.svg").write_text(fn(False)); (d / "AppIcon-Dark.svg").write_text(fn(True)); (d / "HotbarIcon.svg").write_text(gl())
print("ok")
