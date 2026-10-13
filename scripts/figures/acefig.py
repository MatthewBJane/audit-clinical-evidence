"""Shared furniture for ACE screenshot figures: highlight legend band and the
labeled 'SCREENSHOT' frame. Everything is sized from k = image width divided
by the width the figure will be displayed at (2400 px for a full-text-width
figure), so the legend and tag come out the same size on the page whether the
image is wide or narrow and whether it is shown at 100% or 62% width."""
from PIL import Image, ImageDraw, ImageFont

BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
GREY = (118, 118, 118)
FULL_WIDTH_PX = 2400          # reference pixel width of a figure shown at 100% text width
LEGEND_PX = 34                # legend text size at k = 1
TAG_PX = 30                   # frame tag text size at k = 1
A_FILL = 75                   # alpha of the highlight fills


def scale(im, frac=1.0):
    """Size factor for an image displayed at `frac` of the text width."""
    return im.width / (FULL_WIDTH_PX * frac)


def swatch(base):
    f = A_FILL / 255
    return tuple(round(255 * (1 - f) + b * f) for b in base)


def legend_band(im, rows, k):
    """rows: list of (fill colour, text colour, text). All labels are set in
    the same regular weight."""
    im = im.convert("RGB")
    font_px = max(10, round(LEGEND_PX * k))
    font = ImageFont.truetype(REG, font_px)
    line_h = round(font_px * 1.45)
    x, sw = round(40 * k), round(font_px * 1.05)
    tx = x + sw + round(16 * k)
    maxw = im.width - tx - round(40 * k)
    probe = ImageDraw.Draw(im)

    def wrap(txt):
        words, lines, cur = txt.split(), [], ""
        for w in words:
            t = (cur + " " + w).strip()
            if probe.textlength(t, font=font) <= maxw:
                cur = t
            else:
                lines.append(cur); cur = w
        return lines + [cur]

    wrapped = [(fill, col, wrap(t)) for fill, col, t in rows]
    band = round(28 * k) + sum(line_h * len(ls) + round(font_px * 0.4) for _, _, ls in wrapped) + round(8 * k)
    canvas = Image.new("RGB", (im.width, im.height + band), "white")
    canvas.paste(im, (0, band))
    d = ImageDraw.Draw(canvas)
    y = round(28 * k)
    for fill, col, lines in wrapped:
        d.rectangle([x, y, x + sw, y + sw], fill=swatch(fill), outline=fill, width=max(1, round(2 * k)))
        for ln in lines:
            d.text((tx, y - font_px * 0.12), ln, font=font, fill=col)
            y += line_h
        y += round(font_px * 0.4)
    return canvas


def frame(im, label, k):
    """Grey rounded frame with a 'SCREENSHOT | label' tag riding the top edge.
    Everything outside the frame is transparent, so the figure sits cleanly
    on the dark theme; the inside is white, like the page it was taken from."""
    im = im.convert("RGB")
    pad, bw = round(34 * k), max(2, round(4 * k))
    fs = max(9, round(TAG_PX * k))
    font = ImageFont.truetype(MONO, fs)
    tag_h = round(fs * 1.9)
    W, H = im.width + 2 * pad, im.height + 2 * pad + tag_h
    # draw at 4x and scale down so the rounded corners are antialiased
    S = 4
    big = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
    ImageDraw.Draw(big).rounded_rectangle([0, 0, W * S - 1, H * S - 1], radius=round(14 * k) * S,
                                          fill=(255, 255, 255, 255), outline=GREY + (255,), width=bw * S)
    canvas = big.resize((W, H), Image.LANCZOS)
    canvas.paste(im, (pad, pad + tag_h))
    d = ImageDraw.Draw(canvas)
    text = "SCREENSHOT  |  " + label.upper()
    tw = d.textlength(text, font=font)
    tx0, ty0 = pad, bw + round(fs * 0.45)
    d.rounded_rectangle([tx0, ty0, tx0 + tw + fs, ty0 + fs * 1.5], radius=round(6 * k), fill=GREY)
    d.text((tx0 + fs * 0.5, ty0 + fs * 0.2), text, font=font, fill="white")
    return canvas
