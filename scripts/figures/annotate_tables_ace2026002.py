"""Annotate the Singh (1997) table screenshots for ACE2026002.

Pink = a reported value that the audit finds inconsistent or impossible.
Cyan = the article's own statement of what the parentheses contain.
Every flagged value gets its own box; a legend sits above the image and the
whole thing is wrapped in the labeled 'SCREENSHOT' frame (acefig.py).
Coordinates are in the original image pixels. `frac` is the width the figure
is displayed at in the report, so the legend and tag are the same size on
the page for every figure."""
from PIL import Image, ImageDraw
import acefig

import os
SRC = OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "reports", "ACE2026002", "images") + os.sep
PURPLE, PURPLE_TXT = (226, 98, 226), (207, 80, 207)
CYAN, CYAN_TXT = (3, 229, 255), (14, 156, 176)
COL = {"pink": (PURPLE, PURPLE_TXT), "cyan": (CYAN, CYAN_TXT)}


def annotate(src, out, label, items, crop=None, frac=1.0):
    """items: list of (color, legend text, [boxes]); color is 'pink' or 'cyan'."""
    im = Image.open(SRC + src).convert("RGBA")
    if crop:
        im = im.crop(crop)
        items = [(c, t, [(b[0]-crop[0], b[1]-crop[1], b[2]-crop[0], b[3]-crop[1]) for b in bx]) for c, t, bx in items]
    k = acefig.scale(im, frac)
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for c, _txt, boxes in items:
        for b in boxes:
            d.rectangle(list(b), fill=COL[c][0] + (acefig.A_FILL,), outline=COL[c][0] + (220,), width=max(2, round(3 * k)))
    im = Image.alpha_composite(im, ov)
    im = acefig.legend_band(im, [(COL[c][0], COL[c][1], t) for c, t, _ in items], k)
    im = acefig.frame(im, label, k)
    im.save(OUT + out)
    print(out, im.size, f"k={k:.2f}")


def col_boxes(x0, x1, centers, up=25, down=22):
    return [(x0, y - up, x1, y + down) for y in centers]


# --- sec-se-sd: the Methods paragraph alone (panel B of the source image) ----
annotate("singh_methods_table1.png", "singh_methods_annotated.png", "Singh et al. (1997), Methods", [
    ("cyan", "The article's statements of what the parentheses contain",
     [(1520, 420, 1945, 465), (1520, 507, 1985, 552)]),
], crop=(1500, 30, 2595, 1020), frac=0.70)

# --- sec-se-sd: Tables 3 and 4 (2378 x 2701) ------------------------------------
annotate("singh_tables_3_4.png", "singh_tables_3_4_annotated.png", "Singh et al. (1997), Tables 3 and 4", [
    ("pink", "Reported SDs that are smaller than the floor the Table 4 subgroup means impose",
     col_boxes(768, 950, [304, 346, 757, 800]) + col_boxes(1108, 1262, [304, 346, 757, 800])),
    ("cyan", "The article's statements of what the parentheses contain",
     [(215, 1335, 465, 1375), (215, 2555, 465, 2600)]),
])

# --- sec-baseline-column: Table 5 (2208 x 1474) ---------------------------------
annotate("singh_table_5.png", "singh_table_5_annotated.png", "Singh et al. (1997), Table 5", [
    ("pink", "Baseline p values that no test of the baseline scores can return (seven of the eight entries)",
     col_boxes(1420, 1495, [338, 474, 612, 746, 882, 1019, 1157])),
    ("cyan", "The article's statement of what the parentheses contain",
     [(85, 1385, 335, 1425)]),
])

# --- sec-baseline-column: Table 3 only, baseline p column ----------------------
annotate("singh_tables_3_4.png", "singh_table_3_baseline_annotated.png", "Singh et al. (1997), Table 3", [
    ("pink", "Baseline p values that do not reproduce as baseline comparisons under the standard error reading",
     col_boxes(1465, 1545, [304, 483, 621, 757, 935, 1115])),
], crop=(110, 40, 2378, 1400))

# --- sec-baseline-cat: Table 1 only, categorical p values ----------------------
annotate("singh_methods_table1.png", "singh_table_1_categorical_annotated.png", "Singh et al. (1997), Table 1", [
    ("pink", "Reported p values that neither the chi-square test nor Fisher's exact test reproduces",
     col_boxes(1082, 1150, [450, 585, 980, 1350, 1830])),   # gender, marital, residence, smoking, DSM-IV
], crop=(110, 80, 1230, 2360), frac=0.62)

# --- sec-grim: Table 4 only, the GRIM failure ----------------------------------
annotate("singh_tables_3_4.png", "singh_table_4_grim_annotated.png", "Singh et al. (1997), Table 4", [
    ("pink", "A reported mean that no set of four integer scores can produce",
     [(940, 2358, 1075, 2408)]),
], crop=(110, 1560, 2378, 2701))
