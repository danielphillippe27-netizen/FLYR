#!/usr/bin/env python3
"""
Resize session summary image to 1920x1080, make checkerboard transparent,
and move + enlarge the FLYR logo.
"""
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    raise SystemExit("Install Pillow: pip install Pillow")

# Paths: image from Cursor assets; output next to script in workspace
CURSOR_ASSETS = Path("/Users/danielphillippe/.cursor/projects/Users-danielphillippe-Desktop-FLYR-IOS/assets")
SRC = CURSOR_ASSETS / "Screenshot_2026-02-13_at_3.17.54_PM-2c653827-5591-467e-9017-a84f9061c7c9.png"
OUT = Path(__file__).resolve().parent.parent / "session_summary_1920x1080_transparent.png"

# Target size
W, H = 1920, 1080

# Checkerboard: treat pixels that are near these greys as transparent
def is_checker_grey(r, g, b, a=255):
    if a < 200:
        return True
    # Dark and mid greys (checkerboard tiles)
    g_avg = (r + g + b) / 3
    return 25 <= g_avg <= 120 and abs(r - g) <= 25 and abs(g - b) <= 25 and abs(r - b) <= 25


def main():
    if not SRC.exists():
        raise SystemExit(f"Source image not found: {SRC}")
    OUT.parent.mkdir(parents=True, exist_ok=True)

    im = Image.open(SRC).convert("RGBA")
    w, h = im.size
    px = im.load()

    # Make checkerboard pixels transparent
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if is_checker_grey(r, g, b, a):
                px[x, y] = (r, g, b, 0)

    # Crop to content bounds (optional: trim full-transparent rows/cols for scaling)
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    w, h = im.size

    # New canvas 1920x1080, fully transparent
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    # Scale content to fit width 1920 (keep aspect ratio), center vertically
    scale = W / w
    new_w, new_h = W, int(h * scale)
    if new_h > H:
        scale = H / h
        new_w, new_h = int(w * scale), H
    resized = im.resize((new_w, new_h), Image.Resampling.LANCZOS)
    x0 = (W - new_w) // 2
    y0 = (H - new_h) // 2
    canvas.paste(resized, (x0, y0), resized)

    # Extract FLYR logo from bottom of original content (just the logo strip)
    logo_height = max(int(new_h * 0.10), 36)
    logo_strip = resized.crop((0, new_h - logo_height, new_w, new_h))
    # Scale logo way up and place higher on canvas
    logo_scale = 7
    lw, lh = logo_strip.size
    big_w, big_h = lw * logo_scale, lh * logo_scale
    big_logo = logo_strip.resize((big_w, big_h), Image.Resampling.LANCZOS)
    logo_x = (W - big_w) // 2
    # Position: bring "up" — e.g. bottom 180px from bottom of canvas (way bigger and higher)
    logo_y = H - big_h - 120
    canvas.paste(big_logo, (logo_x, logo_y), big_logo)

    canvas.save(OUT, "PNG")
    print(f"Saved: {OUT}")


if __name__ == "__main__":
    main()
