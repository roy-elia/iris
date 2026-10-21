"""Three refinements of the current icon. Same tile, wheel, petals and lit petal; the changes
only make it read as an iris:

  a  pupil     : the dark well becomes a pupil, with a glint and a fine collarette ring.
  b  striations: a plus fine radial fibres across each petal, like the texture of an iris.
  c  limbus    : a plus a darker limbus ring around the wheel and a soft vignette on the tile,
                 so the wheel sits in the tile like an eye in its socket.
"""
import pathlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent.parent
SRC = (HERE.parent / "AppIcon" / "src" / "make_icons.py").read_text()
# Use the current generator as a library: everything above the file-writing lines.
lib = SRC[: SRC.index('(OUT / "AppIcon.svg")')]
ns = {"__file__": str(HERE.parent / "AppIcon" / "src" / "make_icons.py")}
exec(compile(lib, "make_icons.py", "exec"), ns)
import math

CX, CY, R, N, LIT, WELL_R, PETALS = (ns[k] for k in ("CX", "CY", "R", "N", "LIT", "WELL_R", "PETALS"))
THEMES, wheel, app_icon_base = ns["THEMES"], ns["wheel"], ns["app_icon"]

def pupil(name):
    r = WELL_R
    gx, gy = CX - r * 0.38, CY - r * 0.42
    ring = "#FFFFFF" if name == "light" else "#7FD4F2"
    return (
        f'<circle cx="{CX}" cy="{CY}" r="{r + 9:.1f}" fill="none" stroke="{ring}" stroke-opacity="0.38" stroke-width="3"/>'
        f'<circle cx="{CX}" cy="{CY}" r="{r:.1f}" fill="url(#pupil)"/>'
        f'<circle cx="{CX}" cy="{CY}" r="{r - 1:.1f}" fill="none" stroke="url(#rimInv)" stroke-width="2.5"/>'
        f'<ellipse cx="{gx:.1f}" cy="{gy:.1f}" rx="{r * 0.26:.1f}" ry="{r * 0.14:.1f}" fill="#FFFFFF" fill-opacity="0.62" transform="rotate(-38 {gx:.1f} {gy:.1f})"/>'
        f'<circle cx="{CX + r * 0.36:.1f}" cy="{CY + r * 0.38:.1f}" r="{r * 0.06:.1f}" fill="#FFFFFF" fill-opacity="0.35"/>')

def fibres(name):
    out = []
    step = 360 / N
    col = "#FFFFFF"
    for i in range(N):
        if i == LIT: continue
        a0 = -90 - step / 2 + i * step
        out.append(f'<clipPath id="pc{i}"><path d="{PETALS[i]}"/></clipPath>')
        lines = []
        for k in range(1, 12):
            a = a0 + step * k / 12
            x1, y1 = CX + (WELL_R + 14) * math.cos(math.radians(a)), CY + (WELL_R + 14) * math.sin(math.radians(a))
            x2, y2 = CX + (R + 10) * math.cos(math.radians(a)), CY + (R + 10) * math.sin(math.radians(a))
            lines.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}"/>')
        out.append(f'<g clip-path="url(#pc{i})" stroke="{col}" stroke-opacity="{0.2 if name == "light" else 0.1}" stroke-width="2" stroke-linecap="round">{"".join(lines)}</g>')
    return "".join(out)

def build(variant, name):
    svg = app_icon_base(name)
    t = THEMES[name]
    # 1. replace the flat well with the pupil
    svg = re.sub(r'<circle cx="%s" cy="%s" r="%.1f" fill="%s" fill-opacity="%s"/>' % (CX, CY, WELL_R, t["well"], t["well_op"]), "", svg)
    svg = re.sub(r'<circle cx="%s" cy="%s" r="%.1f" fill="none" stroke="url\(#rimInv\)" stroke-width="2"/>' % (CX, CY, WELL_R - 1), pupil(name), svg)
    # pupil gradient
    pg = ("#00507C", "#00243B") if name == "light" else ("#14181C", "#000000")
    svg = svg.replace("</defs>", f'<radialGradient id="pupil" cx="0.5" cy="0.45" r="0.6"><stop offset="0" stop-color="{pg[1]}"/><stop offset="1" stop-color="{pg[0]}"/></radialGradient>\n</defs>', 1)
    if variant in "bc":
        # striations go under the pupil and lit petal: insert before the pupil ring
        marker = f'<circle cx="{CX}" cy="{CY}" r="{WELL_R + 9:.1f}"'
        svg = svg.replace(marker, fibres(name) + marker, 1)
    if variant == "c":
        dark = "#00304F" if name == "light" else "#000000"
        limbus = (f'<circle cx="{CX}" cy="{CY}" r="{R + 9}" fill="none" stroke="{dark}" stroke-opacity="{0.42 if name == "light" else 0.55}" stroke-width="18"/>'
                  f'<circle cx="{CX}" cy="{CY}" r="{R + 18.5}" fill="none" stroke="url(#rim)" stroke-width="2.5"/>')
        svg = svg.replace(f'<circle cx="{CX}" cy="{CY}" r="{R - 1.5}" fill="none" stroke="url(#rim)" stroke-width="3"/>', f'<circle cx="{CX}" cy="{CY}" r="{R - 1.5}" fill="none" stroke="url(#rim)" stroke-width="3"/>' + limbus, 1)
        vig = ('<radialGradient id="vig" cx="0.5" cy="0.5" r="0.75"><stop offset="0.55" stop-color="#000" stop-opacity="0"/>'
               f'<stop offset="1" stop-color="#001a2e" stop-opacity="{0.28 if name == "light" else 0.45}"/></radialGradient>')
        svg = svg.replace("</defs>", vig + "\n</defs>", 1)
        svg = svg.replace('<rect x="100" y="100" width="824" height="824" fill="url(#glow)"/>', '<rect x="100" y="100" width="824" height="824" fill="url(#glow)"/><rect x="100" y="100" width="824" height="824" fill="url(#vig)"/>', 1)
    return svg

def glyph():
    # The current five-petal glyph plus a solid pupil dot in the well.
    g = wheel(11.4, 12.6, 9.2, 5, 1, 1.7, widen=2, gap=1.6, corner=1.2, inner=2.6)
    idle = "".join(f'<path d="{d}" fill-opacity="0.5"/>' for i, d in enumerate(g) if i != 1)
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="#000">{idle}<path d="{g[1]}"/><circle cx="11.4" cy="12.6" r="1.35"/></svg>'

for v in "abc":
    d = HERE / f"current-{v}"; d.mkdir(exist_ok=True)
    (d / "AppIcon.svg").write_text(build(v, "light"))
    (d / "AppIcon-Dark.svg").write_text(build(v, "dark"))
    (d / "HotbarIcon.svg").write_text(glyph())
print("ok")
