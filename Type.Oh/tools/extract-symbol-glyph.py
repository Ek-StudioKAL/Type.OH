#!/usr/bin/env python3
"""Extract one weight of an SF Symbols *template* SVG (the kind Xcode stores in
a .symbolset) into a plain, tightly cropped SVG that NSImage can render as a
template image.  Usage: extract-symbol-glyph.py in.svg out.svg [Regular-S]

Without this, the whole 3300x2200 artboard (notes, guides, all weights) is
rendered and the "icon" comes out as a solid rectangle."""
import re, sys

src, dst = sys.argv[1], sys.argv[2]
variant = sys.argv[3] if len(sys.argv) > 3 else "Regular-S"
s = open(src).read()

m = re.search(r'<g id="%s"([^>]*)>(.*?)</g>' % re.escape(variant), s, re.S)
if not m:
    sys.exit("variant %s not found in %s" % (variant, src))
attrs, inner = m.group(1), m.group(2)
tx = ty = 0.0
t = re.search(r'transform="matrix\(1 0 0 1 ([-\d.]+) ([-\d.]+)\)"', attrs)
if t:
    tx, ty = float(t.group(1)), float(t.group(2))

# --- bounding box from path data (control points included; good enough) -----
num = r'[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?'
xs, ys = [], []
for d in re.findall(r'\sd="([^"]+)"', inner):
    tokens = re.findall(r'[MmLlHhVvCcSsQqTtAaZz]|' + num, d)
    cmd, cx, cy, i = None, 0.0, 0.0, 0
    startx = starty = 0.0
    def take():
        global i
        v = float(tokens[i]); i += 1; return v
    while i < len(tokens):
        if re.match(r'[A-Za-z]', tokens[i]):
            cmd = tokens[i]; i += 1
            if cmd in "Zz":
                cx, cy = startx, starty
                continue
        rel = cmd.islower()
        c = cmd.upper()
        if c == "M":
            x, y = take(), take()
            if rel: x += cx; y += cy
            cx, cy = x, y; startx, starty = x, y; cmd = "l" if rel else "L"
        elif c == "L" or c == "T":
            x, y = take(), take()
            if rel: x += cx; y += cy
            cx, cy = x, y
        elif c == "H":
            x = take(); cx = cx + x if rel else x
        elif c == "V":
            y = take(); cy = cy + y if rel else y
        elif c == "C":
            pts = [take() for _ in range(6)]
            if rel: pts = [pts[k] + (cx if k % 2 == 0 else cy) for k in range(6)]
            xs += pts[0::2]; ys += pts[1::2]; cx, cy = pts[4], pts[5]
        elif c == "S" or c == "Q":
            pts = [take() for _ in range(4)]
            if rel: pts = [pts[k] + (cx if k % 2 == 0 else cy) for k in range(4)]
            xs += pts[0::2]; ys += pts[1::2]; cx, cy = pts[2], pts[3]
        elif c == "A":
            take(); take(); take(); take(); take()
            x, y = take(), take()
            if rel: x += cx; y += cy
            cx, cy = x, y
        xs.append(cx); ys.append(cy)

minx, maxx, miny, maxy = min(xs) + tx, max(xs) + tx, min(ys) + ty, max(ys) + ty
w, h = maxx - minx, maxy - miny
side = max(w, h) * 1.12                     # square, ~6% padding
ox, oy = minx - (side - w) / 2, miny - (side - h) / 2

# Strip classes/styles so the glyph is a plain black shape (alpha is all a
# template image uses), keeping any explicit fill-rule.
inner = re.sub(r'\s(class|style|fill|stroke)="[^"]*"', '', inner)
out = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%.3f %.3f %.3f %.3f">\n'
       '<g fill="black" transform="translate(%.3f %.3f)">%s</g>\n</svg>\n'
       % (ox, oy, side, side, tx, ty, inner.strip()))
open(dst, "w").write(out)
print("%s: %s -> %s  bbox %.0fx%.0f" % (src.split('/')[-1], variant, dst, w, h))
