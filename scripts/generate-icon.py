#!/usr/bin/env python3
"""Generate VoiceNative app icon as .icns via iconutil."""

import math
import os
import subprocess
import sys
from PIL import Image, ImageDraw

BG = (59, 107, 80)       # #3B6B50 — earthy green
FG = (255, 255, 255)     # white waveform
CORNER_RATIO = 0.22       # macOS icon corner radius ~22% of size

def rounded_rect_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask

def draw_waveform(draw, cx, cy, width, height, bar_count, bar_width_ratio, size):
    """Draw a symmetric waveform centered at (cx, cy)."""
    bar_w = int(size * bar_width_ratio)
    gap = (width - bar_count * bar_w) / (bar_count - 1) if bar_count > 1 else 0
    total_w = bar_count * bar_w + (bar_count - 1) * gap
    start_x = cx - total_w / 2

    # Heights: symmetric bell-curve-ish pattern
    ratios = []
    for i in range(bar_count):
        t = (i / (bar_count - 1)) * 2 - 1 if bar_count > 1 else 0  # -1 to 1
        r = math.exp(-2.5 * t * t)  # Gaussian envelope
        # Add slight variation for organic feel
        r *= 0.55 + 0.45 * math.cos(i * 1.2)
        r = max(0.18, min(1.0, abs(r)))
        ratios.append(r)

    for i, r in enumerate(ratios):
        x = start_x + i * (bar_w + gap)
        bar_h = height * r
        y0 = cy - bar_h / 2
        y1 = cy + bar_h / 2
        corner = bar_w * 0.4
        draw.rounded_rectangle(
            [x, y0, x + bar_w, y1],
            radius=corner,
            fill=FG,
        )

def make_icon(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    radius = int(size * CORNER_RATIO)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=BG)

    cx, cy = size / 2, size / 2
    waveform_w = size * 0.52
    waveform_h = size * 0.42
    bar_count = 5
    bar_width_ratio = 0.058

    draw_waveform(draw, cx, cy, waveform_w, waveform_h, bar_count, bar_width_ratio, size)

    mask = rounded_rect_mask(size, radius)
    img.putalpha(mask)

    return img

def main():
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    iconset_dir = os.path.join(project_root, "VoiceNative", "Resources", "AppIcon.iconset")
    os.makedirs(iconset_dir, exist_ok=True)

    # iconutil requires exact file pairs: base + @2x retina variant
    pairs = [
        (16, 32), (32, 64), (128, 256), (256, 512), (512, 1024),
    ]
    for base_px, retina_px in pairs:
        make_icon(base_px).save(os.path.join(iconset_dir, f"icon_{base_px}x{base_px}.png"))
        make_icon(retina_px).save(os.path.join(iconset_dir, f"icon_{base_px}x{base_px}@2x.png"))

    print(f"Generated iconset at {iconset_dir}")

    icns_path = os.path.join(project_root, "VoiceNative", "Resources", "AppIcon.icns")
    result = subprocess.run(
        ["iconutil", "-c", "icns", iconset_dir, "-o", icns_path],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"iconutil failed: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    print(f"Generated {icns_path} ({os.path.getsize(icns_path)} bytes)")

    # Clean up iconset
    import shutil
    shutil.rmtree(iconset_dir)

if __name__ == "__main__":
    main()
