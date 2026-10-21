"""Iris app icon and menu-bar glyph, two directions.

eye   : a glass iris seen like a camera aperture. Eight curved blades twist around a dark
        pupil with a specular glint; one blade is lit, the wheel's "picked" petal.
bloom : the iris as eye and flower at once. Six overlapping glass petals around the pupil;
        one is lit.

Both keep the app's teal Liquid Glass look (DesignTokens: teal #0378A8, tealDeep #00578F) and the
wheel's idea: petals around a well, one swollen and lit. Translucent shapes are wrapped in a
group with `opacity`, so a shape's fill and its rounding stroke composite as one layer.
"""
import math, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent.parent
TEAL, DEEP = "#0378A8", "#00578F"
CX, CY = 512, 520

def pt(cx, cy, r, a):
    t = math.radians(a); return cx + r * math.cos(t), cy + r * math.sin(t)

def f(p): return f"{p[0]:.2f},{p[1]:.2f}"

def blade(cx, cy, r_in, r_out, a0, a1, twist, gap, sw, n=28):
    """A curved aperture blade. Its edges spiral by `twist` degrees from inner to outer radius.
    `sw` is the width of the round-joined stroke that rounds its corners, so the outline is
    pulled in by sw/2 and the gap widened by sw."""
    ri, ro, g = r_in + sw / 2, r_out - sw / 2, gap + sw
    def edge(a, side):
        pts = []
        for k in range(n + 1):
            r = ri + (ro - ri) * k / n
            ang = a + twist * (r - r_in) / (r_out - r_in) + side * math.degrees(math.asin(min(g / 2 / r, 0.99)))
            pts.append(pt(cx, cy, r, ang))
        return pts
    e0, e1 = edge(a0, 1), edge(a1, -1)
    big = 1 if (a1 - a0) > 180 else 0
    d = "M" + f(e0[0]) + " " + " ".join("L" + f(p) for p in e0[1:])
    d += f" A{ro:.2f},{ro:.2f} 0 {big} 1 {f(e1[-1])} " + " ".join("L" + f(p) for p in reversed(e1[:-1]))
    d += f" A{ri:.2f},{ri:.2f} 0 {big} 0 {f(e0[0])}Z"
    return d

def eye_blades(cx, cy, r_in, r_out, n, lit, swell, widen, twist, gap, sw):
    step = 360 / n
    out = []
    for i in range(n):
        a0 = -90 - step / 2 + i * step
        hot = i == lit
        out.append(blade(cx, cy, r_in, r_out + (swell if hot else 0), a0 - (widen if hot else 0),
                         a0 + step + (widen if hot else 0), twist, gap, sw))
    return out

def petal_ellipse(cx, cy, d, rx, ry, a):
    """An elliptical petal centred d from the centre along angle a, long axis radial."""
    x, y = pt(cx, cy, d, a)
    return f'<ellipse cx="{x:.2f}" cy="{y:.2f}" rx="{rx:.2f}" ry="{ry:.2f}" transform="rotate({a + 90:.2f} {x:.2f} {y:.2f})"'

THEMES = {
    "light": dict(bg=["#1AA6DA", TEAL, DEEP], glow=0.22, blade=["#6CC8EA", "#2394C4"], blade_op=1.0,
                  petal_fill="#FFFFFF", petal_op=0.26, disc_op=0.14, rim="#FFFFFF",
                  pupil=["#00507C", "#00243B"], lit=["#FFFFFF", "#DDF1FA"], lit_shadow="#00304F"),
    "dark": dict(bg=["#33373C", "#1C1E21", "#0C0D0E"], glow=0.08, blade=["#50555C", "#2B2E32"], blade_op=1.0,
                 petal_fill="#FFFFFF", petal_op=0.12, disc_op=0.06, rim="#FFFFFF",
                 pupil=["#14181C", "#000000"], lit=["#2BA9DE", TEAL], lit_shadow="#000000"),
}

def defs(name):
    t = THEMES[name]
    return f'''<defs>
  <clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
  <linearGradient id="bg" x1="0.25" y1="0" x2="0.75" y2="1">
    <stop offset="0" stop-color="{t["bg"][0]}"/><stop offset="0.5" stop-color="{t["bg"][1]}"/><stop offset="1" stop-color="{t["bg"][2]}"/>
  </linearGradient>
  <radialGradient id="glow" cx="0.28" cy="0.15" r="0.75">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="{t["glow"]}"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="bladeGrad" gradientUnits="userSpaceOnUse" x1="260" y1="200" x2="760" y2="860">
    <stop offset="0" stop-color="{t["blade"][0]}"/><stop offset="1" stop-color="{t["blade"][1]}"/>
  </linearGradient>
  <linearGradient id="litGrad" gradientUnits="userSpaceOnUse" x1="520" y1="180" x2="860" y2="520">
    <stop offset="0" stop-color="{t["lit"][0]}"/><stop offset="1" stop-color="{t["lit"][1]}"/>
  </linearGradient>
  <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.22"/><stop offset="0.55" stop-color="#FFFFFF" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="rim" x1="0.2" y1="0" x2="0.8" y2="1">
    <stop offset="0" stop-color="{t["rim"]}" stop-opacity="0.85"/><stop offset="0.5" stop-color="{t["rim"]}" stop-opacity="0.08"/><stop offset="1" stop-color="{t["rim"]}" stop-opacity="0.45"/>
  </linearGradient>
  <linearGradient id="rimInv" x1="0.8" y1="1" x2="0.2" y2="0">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.5"/><stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/><stop offset="1" stop-color="#000000" stop-opacity="0.25"/>
  </linearGradient>
  <radialGradient id="pupil" cx="0.5" cy="0.45" r="0.6">
    <stop offset="0" stop-color="{t["pupil"][1]}"/><stop offset="1" stop-color="{t["pupil"][0]}"/>
  </radialGradient>
  <linearGradient id="edge" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.5"/><stop offset="0.35" stop-color="#FFFFFF" stop-opacity="0.04"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0.2"/>
  </linearGradient>
  <filter id="lift" x="-40%" y="-40%" width="180%" height="180%">
    <feDropShadow dx="-4" dy="16" stdDeviation="20" flood-color="{t["lit_shadow"]}" flood-opacity="0.45"/>
  </filter>
  <filter id="tileShadow" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.3"/>
  </filter>
</defs>'''

def frame(name, body):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
{defs(name)}
<g filter="url(#tileShadow)">
  <g clip-path="url(#tile)">
    <rect x="100" y="100" width="824" height="824" fill="url(#bg)"/>
    <rect x="100" y="100" width="824" height="824" fill="url(#glow)"/>
    {body}
  </g>
  <rect x="101.5" y="101.5" width="821" height="821" rx="183.5" fill="none" stroke="url(#edge)" stroke-width="3"/>
</g>
</svg>'''

def pupil_group(r, name):
    gx, gy = CX - r * 0.36, CY - r * 0.40
    return (f'<circle cx="{CX}" cy="{CY}" r="{r}" fill="url(#pupil)"/>'
            f'<circle cx="{CX}" cy="{CY}" r="{r - 1}" fill="none" stroke="url(#rimInv)" stroke-width="2.5"/>'
            f'<ellipse cx="{gx:.1f}" cy="{gy:.1f}" rx="{r * 0.27:.1f}" ry="{r * 0.15:.1f}" fill="#FFFFFF" fill-opacity="0.6" transform="rotate(-38 {gx:.1f} {gy:.1f})"/>'
            f'<circle cx="{CX + r * 0.34:.1f}" cy="{CY + r * 0.36:.1f}" r="{r * 0.065:.1f}" fill="#FFFFFF" fill-opacity="0.35"/>')

# ---------------- eye ----------------
E_N, E_LIT = 8, 1
E_R, E_RIN, E_P = 296, 112, 96
def eye(name):
    t = THEMES[name]
    bl = eye_blades(CX, CY, E_RIN, E_R, E_N, E_LIT, 40, 3.0, 26, 11, 16)
    body = [f'<circle cx="{CX}" cy="{CY}" r="{E_R + 22}" fill="#FFFFFF" fill-opacity="{t["disc_op"]}"/>',
            f'<circle cx="{CX}" cy="{CY}" r="{E_R + 21}" fill="none" stroke="url(#rim)" stroke-width="3"/>']
    for i, d in enumerate(bl):
        if i == E_LIT: continue
        body.append(f'<g opacity="{0.55 if name == "light" else 0.7}"><path d="{d}" fill="url(#bladeGrad)" stroke="url(#bladeGrad)" stroke-width="16" stroke-linejoin="round"/></g>')
        body.append(f'<path d="{d}" fill="none" stroke="url(#rim)" stroke-opacity="0.7" stroke-width="2.5"/>')
    body.append(pupil_group(E_P, name))
    d = bl[E_LIT]
    body.append(f'<g filter="url(#lift)"><path d="{d}" fill="url(#litGrad)" stroke="url(#litGrad)" stroke-width="16" stroke-linejoin="round"/></g>')
    body.append(f'<path d="{d}" fill="url(#sheen)"/>')
    body.append(f'<path d="{d}" fill="none" stroke="url(#rim)" stroke-width="3"/>')
    return frame(name, "".join(body)), bl

def eye_glyph():
    # 6 blades read at 18pt; idle at half opacity, the lit one solid and swollen, hole = pupil.
    bl = eye_blades(12, 12.4, 3.4, 10.0, 6, 1, 1.2, 1.5, 28, 1.0, 1.1)
    idle = "".join(f'<g opacity="0.5"><path d="{d}" stroke="#000" stroke-width="1.1" stroke-linejoin="round"/></g>' for i, d in enumerate(bl) if i != 1)
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="#000">{idle}<path d="{bl[1]}" stroke="#000" stroke-width="1.1" stroke-linejoin="round"/></svg>'

# ---------------- bloom ----------------
B_N, B_LIT = 6, 1
B_D, B_RX, B_RY, B_P = 196, 92, 140, 84
def bloom(name):
    t = THEMES[name]
    body = [f'<circle cx="{CX}" cy="{CY}" r="{B_D + B_RY + 14}" fill="#FFFFFF" fill-opacity="{t["disc_op"]}"/>',
            f'<circle cx="{CX}" cy="{CY}" r="{B_D + B_RY + 13}" fill="none" stroke="url(#rim)" stroke-width="3"/>']
    angles = [-90 + i * 360 / B_N for i in range(B_N)]
    for i, a in enumerate(angles):
        if i == B_LIT: continue
        e = petal_ellipse(CX, CY, B_D, B_RX, B_RY, a)
        body.append(f'{e} fill="{t["petal_fill"]}" fill-opacity="{t["petal_op"]}"/>')
        body.append(f'{e} fill="none" stroke="url(#rim)" stroke-opacity="0.55" stroke-width="2.5"/>')
    body.append(pupil_group(B_P, name))
    e = petal_ellipse(CX, CY, B_D + 18, B_RX + 6, B_RY + 18, angles[B_LIT])
    body.append(f'<g filter="url(#lift)">{e} fill="url(#litGrad)"/></g>')
    body.append(f'{e} fill="url(#sheen)"/>')
    body.append(f'{e} fill="none" stroke="url(#rim)" stroke-width="3"/>')
    # the pupil sits over the petals' roots
    body.append(pupil_group(B_P, name))
    return frame(name, "".join(body))

def bloom_glyph():
    els = []
    for i in range(6):
        a = -90 + i * 60
        hot = i == 1
        e = petal_ellipse(12, 12.4, 6.7 + (0.5 if hot else 0), 2.5 + (0.2 if hot else 0), 3.9 + (0.5 if hot else 0), a)
        els.append(f'{e} fill-opacity="{1 if hot else 0.5}"/>')
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="#000">{"".join(els)}</svg>'

def layers_eye(bl):
    w = lambda s: f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">{s}</svg>'
    return {"1-disc.svg": w(f'<circle cx="{CX}" cy="{CY}" r="{E_R + 22}" fill="#FFFFFF"/>'),
            "2-blades.svg": w("".join(f'<path d="{d}" fill="#FFFFFF" stroke="#FFFFFF" stroke-width="16" stroke-linejoin="round"/>' for i, d in enumerate(bl) if i != E_LIT)),
            "3-pupil.svg": w(f'<circle cx="{CX}" cy="{CY}" r="{E_P}" fill="#000000"/>'),
            "4-lit-blade.svg": w(f'<path d="{bl[E_LIT]}" fill="#FFFFFF" stroke="#FFFFFF" stroke-width="16" stroke-linejoin="round"/>')}

def write(sub, light, dark, glyph, layers=None):
    d = HERE / sub; d.mkdir(exist_ok=True)
    (d / "AppIcon.svg").write_text(light); (d / "AppIcon-Dark.svg").write_text(dark); (d / "HotbarIcon.svg").write_text(glyph)
    if layers:
        ld = d / "IconComposer-layers"; ld.mkdir(exist_ok=True)
        for n, s in layers.items(): (ld / n).write_text(s)

el, bl = eye("light"); ed, _ = eye("dark")
write("eye", el, ed, eye_glyph(), layers_eye(bl))
write("bloom", bloom("light"), bloom("dark"), bloom_glyph())
print("ok")
