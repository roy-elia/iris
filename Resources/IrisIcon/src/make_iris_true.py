"""Iris icon, third round: less camera lens, more iris. Built on the current wheel.

The changes against the current icon, each taken from how a real iris looks:
  - the disc shades from a bright inner ring (near the pupil) to deep teal at the rim;
  - dense radial fibres of varying length run across the whole disc;
  - a zigzag collarette ring sits around the pupil;
  - the pupil is flat ink with a soft edge and no glossy dome, so it doesn't read as glass;
  - a dark, blurred limbal ring edges the disc;
  - the lit petal is a sector of a different, luminous colour (sectoral heterochromia).
The petals stay as translucent bubbles on top, so it is still the wheel.
"""
import math, pathlib, random, re

HERE = pathlib.Path(__file__).resolve().parent.parent
SRC = (HERE.parent / "AppIcon" / "src" / "make_icons.py").read_text()
ns = {"__file__": str(HERE.parent / "AppIcon" / "src" / "make_icons.py")}
exec(compile(SRC[: SRC.index('(OUT / "AppIcon.svg")')], "make_icons.py", "exec"), ns)
CX, CY, R, N, LIT, WELL_R, PETALS = (ns[k] for k in ("CX", "CY", "R", "N", "LIT", "WELL_R", "PETALS"))
THEMES, wheel, app_icon_base = ns["THEMES"], ns["wheel"], ns["app_icon"]

PR = WELL_R * 0.9          # pupil radius
COL_R = PR * 1.62          # collarette radius

PAL = {
    "light": dict(disc=[("0", "#B8F0F7"), ("0.34", "#6FD0E8"), ("0.62", "#2A9BCB"), ("1", "#08588C")],
                  fibre="#FFFFFF", fibre_op=(0.10, 0.34), limbus="#00304F", limbus_op=0.55,
                  pupil=("#00243B", "#001423"), petal_op=0.13, collar="#FFFFFF"),
    "dark": dict(disc=[("0", "#8A939B"), ("0.34", "#575E65"), ("0.62", "#363A3F"), ("1", "#1A1C1F")],
                 fibre="#FFFFFF", fibre_op=(0.05, 0.22), limbus="#000000", limbus_op=0.7,
                 pupil=("#0A0C0E", "#000000"), petal_op=0.07, collar="#FFFFFF"),
}

def fibres(name, simple=False):
    p = PAL[name]
    rnd = random.Random(7)
    lines = []
    count = 48 if simple else 168
    for k in range(count):
        a = 360 * k / count + rnd.uniform(-0.9, 0.9)
        r0 = PR + rnd.uniform(4, 16)
        r1 = R * rnd.uniform(0.7, 1.02)
        w = rnd.uniform(3.2, 4.6) if simple else rnd.uniform(1.2, 3.2)
        op = rnd.uniform(*p["fibre_op"]) * (1.25 if simple else 1)
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        lines.append(f'<line x1="{CX + r0 * c:.1f}" y1="{CY + r0 * s:.1f}" x2="{CX + r1 * c:.1f}" y2="{CY + r1 * s:.1f}" stroke-width="{w:.1f}" stroke-opacity="{op:.2f}"/>')
    return f'<g stroke="{p["fibre"]}" stroke-linecap="round">{"".join(lines)}</g>'

def collarette(name, simple=False):
    p = PAL[name]
    pts = []
    n = 22 if simple else 36
    for k in range(n * 2):
        a = 360 * k / (n * 2)
        r = COL_R + ((6 if k % 2 else -6) if simple else (7 if k % 2 else -7))
        t = math.radians(a)
        pts.append(f"{CX + r * math.cos(t):.1f},{CY + r * math.sin(t):.1f}")
    return (f'<polygon points="{" ".join(pts)}" fill="none" stroke="{p["collar"]}" stroke-opacity="0.5" stroke-width="{4 if simple else 3}" stroke-linejoin="round"/>'
            f'<circle cx="{CX}" cy="{CY}" r="{COL_R + 12:.1f}" fill="none" stroke="{p["collar"]}" stroke-opacity="0.16" stroke-width="2"/>')

G_DARK = dict(disc=[("0", "#6E8E99"), ("0.34", "#41606B"), ("0.62", "#26393F"), ("1", "#121C20")],
              pupil=("#050B0D", "#000000"), limbus="#000000")

def build(variant, name):
    deep = variant == "g" and name == "dark"
    saved = dict(THEMES["dark"])
    if deep:
        THEMES["dark"]["bg"] = ["#27363C", "#121C20", "#070B0D"]
    p = dict(PAL[name])
    if deep: p.update(G_DARK)
    base = app_icon_base(name)
    THEMES["dark"].update(saved)
    stops = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in p["disc"])
    extra = f'''
  <radialGradient id="irisGrad" gradientUnits="userSpaceOnUse" cx="{CX}" cy="{CY}" r="{R}">{stops}</radialGradient>
  <radialGradient id="pupilInk" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{p["pupil"][1]}"/><stop offset="1" stop-color="{p["pupil"][0]}"/></radialGradient>
  <clipPath id="discClip"><circle cx="{CX}" cy="{CY}" r="{R}"/></clipPath>
  <filter id="soft6" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="6"/></filter>
  <filter id="soft14" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="14"/></filter>
'''
    svg = base.replace("</defs>", extra + "</defs>", 1)
    body = []
    body.append(f'<circle cx="{CX}" cy="{CY}" r="{R}" fill="url(#irisGrad)"/>')
    body.append(f'<g clip-path="url(#discClip)">{fibres(name, variant in "fg")}')
    # limbal ring: dark, soft, hugging the rim
    if variant in "fg":
        body.append(f'<circle cx="{CX}" cy="{CY}" r="{R - 12}" fill="none" stroke="{p["limbus"]}" stroke-opacity="{p["limbus_op"] * 0.8:.2f}" stroke-width="24"/></g>')
    else:
        body.append(f'<circle cx="{CX}" cy="{CY}" r="{R + 6}" fill="none" stroke="{p["limbus"]}" stroke-opacity="{p["limbus_op"]}" stroke-width="46" filter="url(#soft14)"/></g>')
    body.append(collarette(name, variant in "fg"))
    # petals as translucent bubbles with a rim, so it stays the wheel
    for i, d in enumerate(PETALS):
        if i == LIT: continue
        if variant in "fg":
            body.append(f'<path d="{d}" fill="none" stroke="{p["limbus"]}" stroke-opacity="0.3" stroke-width="9" stroke-linejoin="round"/>')
            body.append(f'<path d="{d}" fill="#FFFFFF" fill-opacity="{p["petal_op"] * 1.9:.2f}"/>')
            body.append(f'<path d="{d}" fill="none" stroke="url(#rim)" stroke-opacity="0.95" stroke-width="3.5"/>')
        elif variant == "e":
            # grooves between the bubbles, then brighter bubbles with a top sheen
            body.append(f'<path d="{d}" fill="none" stroke="{p["limbus"]}" stroke-opacity="0.35" stroke-width="12" stroke-linejoin="round" filter="url(#soft6)"/>')
            body.append(f'<path d="{d}" fill="#FFFFFF" fill-opacity="{p["petal_op"] * 1.9:.2f}"/>')
            body.append(f'<path d="{d}" fill="url(#discSheen)"/>')
            body.append(f'<path d="{d}" fill="none" stroke="url(#rim)" stroke-opacity="0.95" stroke-width="3.5"/>')
        else:
            body.append(f'<path d="{d}" fill="#FFFFFF" fill-opacity="{p["petal_op"]}"/>')
            body.append(f'<path d="{d}" fill="none" stroke="url(#rim)" stroke-opacity="0.5" stroke-width="2.5"/>')
    body.append(f'<circle cx="{CX}" cy="{CY}" r="{R - 1.5}" fill="none" stroke="url(#rim)" stroke-width="3"/>')
    # pupil: flat ink, soft edge, no dome
    if variant != "f":
        body.append(f'<circle cx="{CX}" cy="{CY}" r="{PR + 5}" fill="{p["pupil"][1]}" fill-opacity="0.55" filter="url(#soft6)"/>')
    body.append(f'<circle cx="{CX}" cy="{CY}" r="{PR}" fill="url(#pupilInk)"/>')
    body.append(f'<circle cx="{CX}" cy="{CY}" r="{PR - 1}" fill="none" stroke="#FFFFFF" stroke-opacity="0.10" stroke-width="2"/>')
    # lit sector: a luminous wedge with the fibres showing through
    lit = PETALS[LIT]
    body.append(f'<clipPath id="litClip"><path d="{lit}"/></clipPath>')
    lift = "" if variant in "fg" else ' filter="url(#lift)"'
    if deep:
        body.append(f'<radialGradient id="litRad" gradientUnits="userSpaceOnUse" cx="{CX}" cy="{CY}" r="{R + 70}"><stop offset="0.25" stop-color="#03435F"/><stop offset="0.55" stop-color="#0378A8"/><stop offset="1" stop-color="#52D2F7"/></radialGradient>')
        body.append(f'<path d="{lit}" fill="url(#litRad)"/>')
    else:
        body.append(f'<g{lift}><path d="{lit}" fill="url(#litGrad)"/></g>')
    hide = ' display="none"' if deep else ""
    if deep:
        body.append(f'<g clip-path="url(#litClip)">{fibres(name, True)}{collarette(name, True)}</g>')
    body.append(f'<g clip-path="url(#litClip)" stroke="#FFFFFF" stroke-linecap="round" stroke-opacity="{0.55 if name == "light" else 0.35}" stroke-width="2.2"{hide}>'
                + "".join(f'<line x1="{CX + (PR + 20) * math.cos(math.radians(a)):.1f}" y1="{CY + (PR + 20) * math.sin(math.radians(a)):.1f}" x2="{CX + (R + 70) * math.cos(math.radians(a)):.1f}" y2="{CY + (R + 70) * math.sin(math.radians(a)):.1f}"/>' for a in [-90 + 360 / N * (LIT - 0.5) + 360 / N * k / 9 for k in range(10)])
                + '</g>')
    mid = math.radians(-90 + 360 / N * LIT)
    gx1, gy1 = CX + PR * math.cos(mid), CY + PR * math.sin(mid)
    gx2, gy2 = CX + (R + 40) * math.cos(mid), CY + (R + 40) * math.sin(mid)
    glow = ("#7FDDF2", "#FFFFFF") if name == "light" else ("#0378A8", "#37B4E6")
    body.append(f'<linearGradient id="litGlow" gradientUnits="userSpaceOnUse" x1="{gx1:.1f}" y1="{gy1:.1f}" x2="{gx2:.1f}" y2="{gy2:.1f}"><stop offset="0" stop-color="{glow[0]}" stop-opacity="0.95"/><stop offset="1" stop-color="{glow[1]}" stop-opacity="0.95"/></linearGradient>')
    if not deep:
        body.append(f'<path d="{lit}" fill="url(#litGlow)"/>')
    body.append(f'<path d="{lit}" fill="url(#discSheen)"/>')
    body.append(f'<path d="{lit}" fill="none" stroke="url(#rim)" stroke-width="3"/>')
    new = "".join(body)
    return re.sub(r'(<rect x="100" y="100" width="824" height="824" fill="url\(#glow\)"/>).*?(\n  </g>\n  <rect x="101.5")', lambda m: m.group(1) + new + m.group(2), svg, flags=re.S)

def glyph():
    g = wheel(11.4, 12.6, 9.2, 5, 1, 1.7, widen=2, gap=1.6, corner=1.2, inner=2.6)
    idle = "".join(f'<path d="{d}" fill-opacity="0.5"/>' for i, d in enumerate(g) if i != 1)
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="#000">{idle}<path d="{g[1]}"/><circle cx="11.4" cy="12.6" r="1.35"/></svg>'

def layers():
    w = lambda x: f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">{x}</svg>'
    fib = "".join(f'<line x1="{CX + (PR + 10) * math.cos(math.radians(a)):.1f}" y1="{CY + (PR + 10) * math.sin(math.radians(a)):.1f}" x2="{CX + (R - 10) * math.cos(math.radians(a)):.1f}" y2="{CY + (R - 10) * math.sin(math.radians(a)):.1f}" stroke="#FFFFFF" stroke-width="4.5" stroke-linecap="round"/>' for a in [9 * k for k in range(40)])
    zig = []
    for k in range(28):
        t = math.radians(360 * k / 28); r = COL_R + (10 if k % 2 else -10); zig.append(f"{CX + r * math.cos(t):.1f},{CY + r * math.sin(t):.1f}")
    return {
        "1-iris.svg": w(f'<circle cx="{CX}" cy="{CY}" r="{R}" fill="#FFFFFF"/>'),
        "2-fibres.svg": w(fib + f'<polygon points="{" ".join(zig)}" fill="none" stroke="#FFFFFF" stroke-width="5" stroke-linejoin="round"/>'),
        "3-petals.svg": w("".join(f'<path d="{d}" fill="#FFFFFF"/>' for i, d in enumerate(PETALS) if i != LIT)),
        "4-pupil.svg": w(f'<circle cx="{CX}" cy="{CY}" r="{PR:.1f}" fill="#000000"/>'),
        "5-lit-sector.svg": w(f'<path d="{PETALS[LIT]}" fill="#FFFFFF"/>'),
    }

for v in "defg":
    d = HERE / f"iris-{v}"; d.mkdir(exist_ok=True)
    (d / "AppIcon.svg").write_text(build(v, "light"))
    (d / "AppIcon-Dark.svg").write_text(build(v, "dark"))
    (d / "HotbarIcon.svg").write_text(glyph())
    if v in "fg":
        ld = d / "IconComposer-layers"; ld.mkdir(exist_ok=True)
        for n, x in layers().items(): (ld / n).write_text(x)
print("ok")
