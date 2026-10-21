"""Iris icon, clean-slate concepts. Each writes AppIcon.svg (light), AppIcon-Dark.svg and
HotbarIcon.svg (a black-on-transparent template glyph) into v2/<concept>/.

A triad  : the iris flower as geometry: three standards up, three wider falls, overlapping glass;
           the falls carry the flower's gold beard. Violet.
B ring   : a ring of glass bubbles around a pupil, one bubble lit: the carousel as an iris. Teal.
C almond : an eye outline in glass, its iris a ring of small bubbles. Midnight indigo, cyan.

Shapes are flat with clear edges; the only "glass" is translucency and a thin rim, so the
system's Liquid Glass effects have room to work (app-icons.md: Visual effects).
"""
import math, pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent
CX, CY = 512, 520

def rot(x, y, a, cx=CX, cy=CY):
    t = math.radians(a); return cx + x * math.cos(t) - y * math.sin(t), cy + x * math.sin(t) + y * math.cos(t)

def P(p): return f"{p[0]:.1f},{p[1]:.1f}"

def petal(a, length, width, base=0, cx=CX, cy=CY):
    """A teardrop petal from the centre outward, pointing at angle a (0 = up, clockwise)."""
    pts = [(0, -base), (width * 0.95, -base - length * 0.28), (width * 0.62, -base - length * 0.96), (0, -base - length),
           (-width * 0.62, -base - length * 0.96), (-width * 0.95, -base - length * 0.28), (0, -base)]
    q = [rot(x, y, a, cx, cy) for x, y in pts]
    return f"M{P(q[0])} C{P(q[1])} {P(q[2])} {P(q[3])} C{P(q[4])} {P(q[5])} {P(q[6])}Z"

def frame(bg, glow, body, defs=""):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
  <clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
  <linearGradient id="bg" x1="0.2" y1="0" x2="0.8" y2="1"><stop offset="0" stop-color="{bg[0]}"/><stop offset="0.55" stop-color="{bg[1]}"/><stop offset="1" stop-color="{bg[2]}"/></linearGradient>
  <radialGradient id="glow" cx="0.3" cy="0.12" r="0.8"><stop offset="0" stop-color="#FFFFFF" stop-opacity="{glow}"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>
  <linearGradient id="rim" x1="0.2" y1="0" x2="0.8" y2="1"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.9"/><stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.12"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0.5"/></linearGradient>
  <linearGradient id="edge" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.45"/><stop offset="0.35" stop-color="#FFFFFF" stop-opacity="0.04"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0.18"/></linearGradient>
  <filter id="tileShadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.3"/></filter>
  {defs}
</defs>
<g filter="url(#tileShadow)"><g clip-path="url(#tile)">
  <rect x="100" y="100" width="824" height="824" fill="url(#bg)"/>
  <rect x="100" y="100" width="824" height="824" fill="url(#glow)"/>
  {body}
</g><rect x="101.5" y="101.5" width="821" height="821" rx="183.5" fill="none" stroke="url(#edge)" stroke-width="3"/></g>
</svg>'''

def glass(d, fill, op, rim_w=3):
    return f'<path d="{d}" fill="{fill}" fill-opacity="{op}"/><path d="{d}" fill="none" stroke="url(#rim)" stroke-width="{rim_w}"/>'

# ---------- A: triad ----------
def triad(dark):
    bg = ["#2A2146", "#16112A", "#08060F"] if dark else ["#8C74FF", "#5A3FE0", "#2E1A9E"]
    std = "#B9A8FF" if dark else "#FFFFFF"
    fall = "#8E78FF" if dark else "#FFFFFF"
    body = []
    for a in (0, 120, 240):           # standards, behind
        body.append(glass(petal(a, 300, 150, base=10), std, 0.30 if dark else 0.34))
    for a in (60, 180, 300):          # falls, in front, wider
        d = petal(a, 262, 196, base=6)
        body.append(glass(d, fall, 0.42 if dark else 0.5))
        # the gold beard: a short tapered stroke at the base of each fall
        body.append(f'<path d="{petal(a, 104, 15, base=44)}" fill="#FFC94A"/>')
    body.append(f'<circle cx="{CX}" cy="{CY}" r="30" fill="#FFFFFF" fill-opacity="{0.85 if dark else 0.95}"/>')
    return frame(bg, 0.06 if dark else 0.2, "".join(body))

def triad_glyph():
    s = []
    for a in (0, 120, 240):
        s.append(f'<path d="{petal(a, 10.6, 5.4, 0.3, 12, 12.6)}" fill-opacity="0.5"/>')
    for a in (60, 180, 300):
        s.append(f'<path d="{petal(a, 8.8, 5.6, 0.2, 12, 12.6)}"/>')
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="#000">{"".join(s)}</svg>'

# ---------- B: bubble ring ----------
RING_N, RING_LIT = 8, 1
def ring(dark):
    bg = ["#1E3A44", "#0E1E24", "#050C0F"] if dark else ["#1AA6DA", "#0378A8", "#00507F"]
    body = []
    R, r = 232, 74
    for i in range(RING_N):
        a = -90 + i * 360 / RING_N
        x, y = CX + R * math.cos(math.radians(a)), CY + R * math.sin(math.radians(a))
        if i == RING_LIT:
            continue
        body.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="#FFFFFF" fill-opacity="{0.16 if dark else 0.26}"/>'
                    f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r - 1.5}" fill="none" stroke="url(#rim)" stroke-width="3"/>')
    # pupil
    body.append(f'<circle cx="{CX}" cy="{CY}" r="118" fill="{"#000000" if dark else "#00243B"}" fill-opacity="{0.9 if dark else 0.8}"/>'
                f'<circle cx="{CX}" cy="{CY}" r="117" fill="none" stroke="url(#rim)" stroke-opacity="0.6" stroke-width="3"/>')
    # lit bubble, larger, pulled slightly out
    a = -90 + RING_LIT * 360 / RING_N
    x, y = CX + (R + 14) * math.cos(math.radians(a)), CY + (R + 14) * math.sin(math.radians(a))
    lit = "url(#litB)"
    defs = (f'<radialGradient id="litB" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="{"#7FE0FF" if dark else "#FFFFFF"}"/>'
            f'<stop offset="1" stop-color="{"#0378A8" if dark else "#BFEAF8"}"/></radialGradient>')
    body.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r + 16}" fill="{lit}"/><circle cx="{x:.1f}" cy="{y:.1f}" r="{r + 14.5}" fill="none" stroke="url(#rim)" stroke-width="3"/>')
    return frame(bg, 0.06 if dark else 0.22, "".join(body), defs)

def ring_glyph():
    s = []
    for i in range(RING_N):
        a = -90 + i * 360 / RING_N
        lit = i == RING_LIT
        R = 8.4 + (0.4 if lit else 0)
        x, y = 12 + R * math.cos(math.radians(a)), 12 + R * math.sin(math.radians(a))
        s.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{3.0 if lit else 2.3}" fill-opacity="{1 if lit else 0.5}"/>')
    s.append('<circle cx="12" cy="12" r="3.4"/>')
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="#000">{"".join(s)}</svg>'

# ---------- C: almond ----------
def almond_path(cx, cy, w, h):
    # two circular arcs meeting at sharp-ish corners, softened by quadratic ends
    k = h * 1.05
    return (f"M{cx - w / 2:.1f},{cy:.1f} C{cx - w * 0.22:.1f},{cy - k:.1f} {cx + w * 0.22:.1f},{cy - k:.1f} {cx + w / 2:.1f},{cy:.1f} "
            f"C{cx + w * 0.22:.1f},{cy + k:.1f} {cx - w * 0.22:.1f},{cy + k:.1f} {cx - w / 2:.1f},{cy:.1f}Z")

def almond(dark):
    bg = ["#232C5A", "#111733", "#070A18"] if dark else ["#4C5FD6", "#2C3A9E", "#18215E"]
    body = [glass(almond_path(CX, CY, 700, 330), "#FFFFFF", 0.10 if dark else 0.16, 4)]
    n, R, r = 10, 128, 30
    for i in range(n):
        a = -90 + i * 360 / n
        x, y = CX + R * math.cos(math.radians(a)), CY + R * math.sin(math.radians(a))
        lit = i == 1
        col = "#5FE3FF" if lit else "#FFFFFF"
        body.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r + (8 if lit else 0)}" fill="{col}" fill-opacity="{1 if lit else (0.22 if dark else 0.3)}"/>')
        body.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r + (8 if lit else 0) - 1.5}" fill="none" stroke="url(#rim)" stroke-width="2.5"/>')
    body.append(f'<circle cx="{CX}" cy="{CY}" r="70" fill="#000" fill-opacity="{0.85 if dark else 0.6}"/>')
    return frame(bg, 0.05 if dark else 0.18, "".join(body))

def almond_glyph():
    s = [f'<path d="{almond_path(12, 12, 22, 10.4)}" fill="none" stroke="#000" stroke-width="1.6" stroke-linejoin="round"/>']
    for i in range(8):
        a = -90 + i * 45
        lit = i == 1
        x, y = 12 + 4.6 * math.cos(math.radians(a)), 12 + 4.6 * math.sin(math.radians(a))
        s.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{1.45 if lit else 1.05}" fill-opacity="{1 if lit else 0.5}"/>')
    s.append('<circle cx="12" cy="12" r="2"/>')
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="#000">{"".join(s)}</svg>'

def triad_layers():
    w = lambda x: f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">{x}</svg>'
    return {
        "1-standards.svg": w("".join(f'<path d="{petal(a, 300, 150, base=10)}" fill="#FFFFFF"/>' for a in (0, 120, 240))),
        "2-falls.svg": w("".join(f'<path d="{petal(a, 262, 196, base=6)}" fill="#FFFFFF"/>' for a in (60, 180, 300))),
        "3-beards.svg": w("".join(f'<path d="{petal(a, 104, 15, base=44)}" fill="#FFC94A"/>' for a in (60, 180, 300))),
        "4-centre.svg": w(f'<circle cx="{CX}" cy="{CY}" r="30" fill="#FFFFFF"/>'),
    }

ld = OUT / "triad" / "IconComposer-layers"
ld.mkdir(parents=True, exist_ok=True)
for n, x in triad_layers().items(): (ld / n).write_text(x)

for name, fn, gl in [("triad", triad, triad_glyph), ("ring", ring, ring_glyph), ("almond", almond, almond_glyph)]:
    d = OUT / name; d.mkdir(exist_ok=True)
    (d / "AppIcon.svg").write_text(fn(False)); (d / "AppIcon-Dark.svg").write_text(fn(True)); (d / "HotbarIcon.svg").write_text(gl())
print("ok")
