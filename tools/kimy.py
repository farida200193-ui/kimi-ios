"""Draws Kimy, the little sticker ghost, for the iOS app from the same shapes as the design page.
Run: python3 tools/kimy.py
  -> KimiWidget/Assets.xcassets/kimy-<phase>.imageset  (Dynamic Island / lock screen, 120 px)
  -> Kimi/Assets.xcassets/AppIcon.appiconset/icon-1024.png"""
import json
import os
import re

from PIL import Image, ImageDraw, ImageFilter

BLUE, INK, WHITE, PAPER = "#1E8CFF", "#17161C", "#FFFFFF", "#F6F2E9"
GREEN, PURPLE, ORANGE = "#1FE07C", "#8B7CF6", "#FF6A13"
BODY = ("M48 146 L48 100 C48 68 71 46 100 46 C129 46 152 68 152 100 L152 146 C152 156 143 160 137 152 "
        "C132 145 124 145 119 152 C114 160 105 160 100 152 C95 145 86 145 81 152 C76 160 67 160 62 152 "
        "C57 145 48 156 48 146 Z")
PHASES = ("idle", "listening", "thinking", "speaking")
HERE = os.path.dirname(os.path.abspath(__file__))


def points(d, steps=24):
    """Absolute M/L/Q/C/Z path -> polygon points."""
    t = re.findall(r"[MLQCZ]|-?\d*\.?\d+", d)
    out, i, cur = [], 0, (0.0, 0.0)

    def pt():
        nonlocal i
        i += 2
        return float(t[i - 2]), float(t[i - 1])
    while i < len(t):
        c = t[i]
        i += 1
        if c in "ML":
            cur = pt()
            out.append(cur)
        elif c == "Q":
            q, p = pt(), pt()
            out += [tuple((1 - s) ** 2 * a + 2 * (1 - s) * s * b + s * s * e for a, b, e in zip(cur, q, p))
                    for s in (n / steps for n in range(1, steps + 1))]
            cur = p
        elif c == "C":
            a1, a2, p = pt(), pt(), pt()
            out += [tuple((1 - s) ** 3 * a + 3 * (1 - s) ** 2 * s * b + 3 * (1 - s) * s * s * c2 + s ** 3 * e
                          for a, b, c2, e in zip(cur, a1, a2, p))
                    for s in (n / steps for n in range(1, steps + 1))]
            cur = p
    return out


def draw(phase, size, ground=None, scale=8, view=(0, 30, 210, 180)):
    """One sticker image. view = (x, y, w, h) of the 210-wide drawing to show."""
    vx, vy, vw, vh = view
    k = size * scale / max(vw, vh)
    img = Image.new("RGBA", (size * scale, size * scale), ground or (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox, oy = (size * scale - vw * k) / 2 - vx * k, (size * scale - vh * k) / 2 - vy * k
    P = lambda pts: [(ox + x * k, oy + y * k) for x, y in pts]

    def sticker(pts, color):
        pp = P(pts)
        d.line(pp + pp[:2], fill=WHITE, width=int(9 * k), joint="curve")   # white sticker outline under the fill
        d.polygon(pp, fill=color)

    def oval(cx, cy, rx, ry, color=INK):
        d.ellipse([ox + (cx - rx) * k, oy + (cy - ry) * k, ox + (cx + rx) * k, oy + (cy + ry) * k], fill=color)

    def arc(x0, y0, x1, y1, a0, a1):
        d.arc([ox + x0 * k, oy + y0 * k, ox + x1 * k, oy + y1 * k], a0, a1, fill=INK, width=int(5 * k))

    sticker(points(BODY), BLUE)
    if phase == "speaking":                                  # happy closed eyes, open mouth
        arc(79, 86, 93, 102, 200, 340)
        arc(107, 86, 121, 102, 200, 340)
        d.polygon(P(points("M89 108 Q100 108 111 108 Q109 123 100 123 Q91 123 89 108 Z")), fill=INK)
    else:
        dx, dy = (2, -2) if phase == "thinking" else (0, 0)
        oval(86 + dx, 92 + dy, 5, 7)
        oval(114 + dx, 92 + dy, 5, 7)
        if phase == "idle":
            arc(87, 96, 113, 114, 20, 160)                   # smile
        else:
            arc(93, 106, 107, 116, 20, 160)                  # small mouth
    if phase in ("listening", "thinking"):                   # a little bubble beside the ghost
        color = GREEN if phase == "listening" else PURPLE
        box = [ox + 140 * k, oy + 38 * k, ox + 196 * k, oy + 78 * k]
        tail = P([(152, 76), (144, 90), (166, 76)])
        pad = 4.5 * k
        d.rounded_rectangle([box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad], radius=16 * k, fill=WHITE)
        d.polygon(tail, fill=WHITE, outline=WHITE, width=int(9 * k))
        d.rounded_rectangle(box, radius=12 * k, fill=color)
        d.polygon(tail, fill=color)
        if phase == "thinking":
            for x in (155, 168, 181):
                oval(x, 58, 4, 4)
        else:
            arc(150, 46, 166, 70, -60, 60)
            arc(156, 40, 176, 76, -60, 60)
    return img.resize((size, size), Image.LANCZOS)


def sparkle(img, cx, cy, r):
    """A four-point star, drawn on the final image."""
    d = ImageDraw.Draw(img)
    pts = []
    import math
    for n in range(16):
        a = n * math.pi / 8
        rr = r if n % 4 == 0 else r * (0.22 if n % 2 else 0.32)
        pts.append((cx + rr * math.sin(a), cy - rr * math.cos(a)))
    d.polygon(pts, fill=INK)


def main():
    meta = {"version": 1, "author": "xcode"}
    root = os.path.join(HERE, "..", "KimiWidget", "Assets.xcassets")
    os.makedirs(root, exist_ok=True)
    with open(os.path.join(root, "Contents.json"), "w") as f:
        json.dump({"info": meta}, f)
    for phase in PHASES:
        folder = os.path.join(root, f"kimy-{phase}.imageset")
        os.makedirs(folder, exist_ok=True)
        draw(phase, 120).save(os.path.join(folder, "kimy.png"))
        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump({"images": [{"idiom": "universal", "filename": "kimy.png"}], "info": meta}, f)
    # the App Store icon must be square and opaque: paper ground, Kimy, one sparkle; iOS rounds the corners
    icon = draw("idle", 1024, ground=PAPER, scale=2, view=(0, 10, 200, 200)).convert("RGB")
    shadow = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse([382, 860, 642, 892], fill=(23, 22, 28, 40))
    icon = Image.alpha_composite(icon.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(8))).convert("RGB")
    sparkle(icon, 800, 220, 70)
    icon.save(os.path.join(HERE, "..", "Kimi", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png"))
    print("ok")


if __name__ == "__main__":
    main()
