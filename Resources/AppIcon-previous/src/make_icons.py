"""File Drop Utility app icon and hotbar glyph.

The icon is the app's own radial wheel: petals on a Liquid Glass disc around a centre well,
with the lit petal swelling past the rim. Proportions come from RadialWheel.swift
(inner 50/126 of the radius, 7pt gaps, 15pt corners). Colours come from DesignTokens.swift:
brand teal #0378A8 -> tealDeep #00578F, the app's only custom colour.

Light icon = the wheel's Tinted theme (teal disc, lit petal flips to white).
Dark icon  = the wheel's Regular theme (smoky glass, lit petal teal).
"""
import math, pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent
TEAL, TEAL_DEEP = "#0378A8", "#00578F"

def P(x, y): return f"{x:.2f},{y:.2f}"

def petal(cx, cy, r_in, r_out, a0, a1, gap, rc):
    """Annular sector with evenly rounded corners and a constant-width gap (like PetalShape)."""
    h = gap / 2
    big = 1 if (a1 - a0) > 180 else 0
    def off(r, a, side): return a + side * math.degrees(math.asin(min(h / r, 0.99)))
    def pt(r, a):
        t = math.radians(a); return cx + r * math.cos(t), cy + r * math.sin(t)
    s_in, s_out, e_in, e_out = off(r_in, a0, 1), off(r_out, a0, 1), off(r_in, a1, -1), off(r_out, a1, -1)
    A, B, C, D = pt(r_in, s_in), pt(r_out, s_out), pt(r_out, e_out), pt(r_in, e_in)
    def tw(p, q, d):
        L = math.dist(p, q); return p[0] + (q[0]-p[0]) * d / L, p[1] + (q[1]-p[1]) * d / L
    ri = min(rc, (r_out - r_in) / 2 - 0.5)
    do, di = math.degrees(rc / r_out), math.degrees(ri / r_in)
    return " ".join([
        f"M{P(*tw(A, B, ri))}", f"L{P(*tw(B, A, rc))}", f"Q{P(*B)} {P(*pt(r_out, s_out + do))}",
        f"A{r_out:.2f},{r_out:.2f} 0 {big} 1 {P(*pt(r_out, e_out - do))}",
        f"Q{P(*C)} {P(*tw(C, D, rc))}", f"L{P(*tw(D, C, ri))}", f"Q{P(*D)} {P(*pt(r_in, e_in - di))}",
        f"A{r_in:.2f},{r_in:.2f} 0 {big} 0 {P(*pt(r_in, s_in + di))}", f"Q{P(*A)} {P(*tw(A, B, ri))}Z"])

def wheel(cx, cy, R, n, lit, swell, widen=2.0, gap=None, corner=None, inner=None):
    """Petal paths for a wheel of radius R, segment 0 centred at the top (WheelGeometry)."""
    s = R / 126
    step = 360 / n
    out = []
    for i in range(n):
        a0 = -90 - step / 2 + i * step
        hot = i == lit
        w = widen if hot else 0
        out.append(petal(cx, cy, inner or 50 * s, R - 8 * s + (swell if hot else 0), a0 - w, a0 + step + w,
                         gap or 7 * s, corner or 15 * s))
    return out

# ---------- app icon ----------
N, LIT = 7, 1                 # petal 1 sits upper right
CX, CY, R = 500, 524, 296     # nudged down-left to balance the swollen petal
SWELL = 46                    # exaggerated past the app's 12pt so it reads at 32px
PETALS = wheel(CX, CY, R, N, LIT, SWELL)
WELL_R = 50 * R / 126 - 7 * R / 126 * 0.9

THEMES = {
    "light": dict(  # wheel Tinted theme on brand teal
        bg=["#1AA6DA", TEAL, TEAL_DEEP], disc="#FFFFFF", disc_op=0.16, petal="#FFFFFF",
        petal_op=[0.30, 0, 0.24, 0.20, 0.26, 0.22, 0.28], well="#003A5E", well_op=0.45,
        lit=["#FFFFFF", "#E3F3FA"], lit_shadow="#00304F", rim="#FFFFFF"),
    "dark": dict(   # wheel Regular theme: smoky glass, lit petal teal
        bg=["#33373C", "#1C1E21", "#0C0D0E"], disc="#FFFFFF", disc_op=0.07, petal="#FFFFFF",
        petal_op=[0.13, 0, 0.10, 0.08, 0.11, 0.09, 0.12], well="#000000", well_op=0.40,
        lit=["#1F9FD6", TEAL], lit_shadow="#000000", rim="#FFFFFF"),
}

def app_icon(name):
    t = THEMES[name]
    body = [
        f'<circle cx="{CX}" cy="{CY}" r="{R}" fill="{t["disc"]}" fill-opacity="{t["disc_op"]}"/>',
        f'<circle cx="{CX}" cy="{CY}" r="{R}" fill="url(#discSheen)"/>',
        f'<circle cx="{CX}" cy="{CY}" r="{R - 1.5}" fill="none" stroke="url(#rim)" stroke-width="3"/>',
    ]
    for i, d in enumerate(PETALS):
        if i == LIT: continue
        body.append(f'<path d="{d}" fill="{t["petal"]}" fill-opacity="{t["petal_op"][i]}"/>')
        body.append(f'<path d="{d}" fill="none" stroke="url(#rim)" stroke-opacity="0.5" stroke-width="2"/>')
    body.append(f'<circle cx="{CX}" cy="{CY}" r="{WELL_R:.1f}" fill="{t["well"]}" fill-opacity="{t["well_op"]}"/>')
    body.append(f'<circle cx="{CX}" cy="{CY}" r="{WELL_R - 1:.1f}" fill="none" stroke="url(#rimInv)" stroke-width="2"/>')
    lit = PETALS[LIT]
    body.append(f'<g filter="url(#lift)"><path d="{lit}" fill="url(#litGrad)"/></g>')
    body.append(f'<path d="{lit}" fill="url(#discSheen)"/>')
    body.append(f'<path d="{lit}" fill="none" stroke="url(#rim)" stroke-width="3"/>')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
  <clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
  <linearGradient id="bg" x1="0.25" y1="0" x2="0.75" y2="1">
    <stop offset="0" stop-color="{t["bg"][0]}"/><stop offset="0.5" stop-color="{t["bg"][1]}"/><stop offset="1" stop-color="{t["bg"][2]}"/>
  </linearGradient>
  <radialGradient id="glow" cx="0.28" cy="0.15" r="0.75">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="{0.08 if name == "dark" else 0.22}"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="discSheen" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.16"/><stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="rim" x1="0.2" y1="0" x2="0.8" y2="1">
    <stop offset="0" stop-color="{t["rim"]}" stop-opacity="0.85"/><stop offset="0.5" stop-color="{t["rim"]}" stop-opacity="0.08"/><stop offset="1" stop-color="{t["rim"]}" stop-opacity="0.45"/>
  </linearGradient>
  <linearGradient id="rimInv" x1="0.8" y1="1" x2="0.2" y2="0">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.5"/><stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/><stop offset="1" stop-color="#000000" stop-opacity="0.25"/>
  </linearGradient>
  <linearGradient id="litGrad" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="{t["lit"][0]}"/><stop offset="1" stop-color="{t["lit"][1]}"/>
  </linearGradient>
  <linearGradient id="edge" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.5"/><stop offset="0.35" stop-color="#FFFFFF" stop-opacity="0.04"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0.2"/>
  </linearGradient>
  <filter id="lift" x="-40%" y="-40%" width="180%" height="180%">
    <feDropShadow dx="-4" dy="16" stdDeviation="20" flood-color="{t["lit_shadow"]}" flood-opacity="0.45"/>
  </filter>
  <filter id="tileShadow" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.3"/>
  </filter>
</defs>
<g filter="url(#tileShadow)">
  <g clip-path="url(#tile)">
    <rect x="100" y="100" width="824" height="824" fill="url(#bg)"/>
    <rect x="100" y="100" width="824" height="824" fill="url(#glow)"/>
    {"".join(body)}
  </g>
  <rect x="101.5" y="101.5" width="821" height="821" rx="183.5" fill="none" stroke="url(#edge)" stroke-width="3"/>
</g>
</svg>'''

def composer_layers():
    wrap = lambda s: f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">{s}</svg>'
    idle = "".join(f'<path d="{d}" fill="#FFFFFF"/>' for i, d in enumerate(PETALS) if i != LIT)
    return {
        "1-disc.svg": wrap(f'<circle cx="{CX}" cy="{CY}" r="{R}" fill="#FFFFFF"/>'),
        "2-petals.svg": wrap(idle),
        "3-well.svg": wrap(f'<circle cx="{CX}" cy="{CY}" r="{WELL_R:.1f}" fill="#000000"/>'),
        "4-lit-petal.svg": wrap(f'<path d="{PETALS[LIT]}" fill="#FFFFFF"/>'),
    }

# ---------- hotbar glyph: template image, black + alpha ----------
def glyph():
    # 5 petals: 7 turn to noise at 18pt. Idle petals at 45% alpha, the lit one solid and swollen,
    # so the "picked" state reads in monochrome without relying on colour.
    g = wheel(11.4, 12.6, 9.2, 5, 1, 1.7, widen=2, gap=1.6, corner=1.2, inner=2.6)
    idle = "".join(f'<path d="{d}" fill-opacity="0.5"/>' for i, d in enumerate(g) if i != 1)
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="#000">{idle}<path d="{g[1]}"/></svg>'

(OUT / "AppIcon.svg").write_text(app_icon("light"))
(OUT / "AppIcon-Dark.svg").write_text(app_icon("dark"))
(OUT / "HotbarIcon.svg").write_text(glyph())
lay = OUT / "IconComposer-layers"; lay.mkdir(exist_ok=True)
for n, s in composer_layers().items(): (lay / n).write_text(s)
print("ok")
