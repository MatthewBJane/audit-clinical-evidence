"""Annotate the two forest plots for ACE2026002 (Cunha 2024, Nebiker 2018):
pink highlight over the Singh rows, two blue bands for the post-test range
(0 to -0.72) and the change-score range (0 to -1.72), legend and labeled
frame from acefig.py."""
from PIL import Image, ImageDraw
import acefig

import os
RAW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "reports", "ACE2026002", "images") + os.sep
OUT = RAW
PURPLE, PURPLE_TXT = (226, 98, 226), (207, 80, 207)
CYAN, CYAN_TXT = (3, 229, 255), (14, 156, 176)
POST, CHG = 0.72, 1.72
A_PINK, A_POST, A_CHG = 70, 95, 32


def blend(base, alphas):
    r, g, b = 255, 255, 255
    for a in alphas:
        f = a / 255
        r, g, b = (round(r * (1 - f) + base[0] * f), round(g * (1 - f) + base[1] * f), round(b * (1 - f) + base[2] * f))
    return (r, g, b)


# legend fills are the composited colours, so acefig.swatch() is bypassed by
# pre-blending and passing an opaque colour through a tiny shim
class Solid(tuple):
    pass


LEGEND = [
    (PURPLE, PURPLE_TXT, "Singh, Clements, and Fiatarone (1997), with its standard errors read as SDs"),
    (CYAN, CYAN_TXT, "Range of post-test SMDs the trial's own numbers support (0 to −0.72)"),
    (CYAN, CYAN_TXT, "Range of change-score SMDs standardized by the baseline SD (0 to −1.72)"),
]


def bands(d, x_of, top, bot):
    d.rectangle([x_of(-CHG), top, x_of(0), bot], fill=CYAN + (A_CHG,))
    d.rectangle([x_of(-POST), top, x_of(0), bot], fill=CYAN + (A_POST,))


def finish(plot, label, frac, out):
    plot = plot.convert("RGB")
    k = acefig.scale(plot, frac)
    # legend swatches: the second band is lighter than the first
    rows = LEGEND
    im = acefig.legend_band(plot, rows, k)
    # repaint the three swatches with the exact composited band colours
    d = ImageDraw.Draw(im)
    font_px = max(10, round(acefig.LEGEND_PX * k)); line_h = round(font_px * 1.45)
    x, sw = round(40 * k), round(font_px * 1.05)
    y = round(28 * k)
    for fill in (blend(PURPLE, [A_PINK]), blend(CYAN, [A_CHG, A_POST]), blend(CYAN, [A_CHG])):
        d.rectangle([x, y, x + sw, y + sw], fill=fill, outline=fill)
        y += line_h + round(font_px * 0.4)
    im = acefig.frame(im, label, k)
    im.save(OUT + out)
    print(out, im.size, f"k={k:.2f}")


# Cunha 2024 (592 x 762 source, upscaled 3x so the boxes are crisp), shown at 78% width
S = 3
src = Image.open(RAW + "Cunha2024_forest.png").convert("RGBA")
plot = src.resize((src.width * S, src.height * S), Image.LANCZOS)
ov = Image.new("RGBA", plot.size, (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
x_of = lambda es: (383 + 30 * es) * S
bands(d, x_of, 70 * S, 548 * S)
d.rectangle([20 * S, 380 * S, 560 * S, 448 * S], fill=PURPLE + (A_PINK,))
finish(Image.alpha_composite(plot, ov), "Cunha et al. (2024), forest plot", 0.78, "Cunha2024_forest_annotated.png")

# Nebiker 2018 (1546 x 540 source), shown at full width
src = Image.open(RAW + "Nebiker2018_forest.png").convert("RGBA")
ov = Image.new("RGBA", src.size, (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
zero = 1410; unit = (1410 - 1262) / 3.83
x_of = lambda es: zero + unit * es
bands(d, x_of, 40, 365)
d.rectangle([28, 46, 1500, 76], fill=PURPLE + (A_PINK,))
finish(Image.alpha_composite(src, ov), "Nebiker et al. (2018), forest plot", 1.0, "Nebiker2018_forest_annotated.png")
