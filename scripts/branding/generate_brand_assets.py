#!/usr/bin/env python3
"""Generate every UAM brand/launcher asset from the canonical logo source.

Canonical source
----------------
``app/flutter/assets/branding/uam_logo.svg`` (verbatim copy of the official
``.logo-uam/uam_logo.svg``). Never edit the generated files by hand: re-run this
script instead.

Pipeline
--------
1. Read the canonical SVG.
2. Apply two *documented, non-design* corrections used only for rasterisation:
   * the decorative border ``<rect>`` in the source has no ``fill`` attribute,
     so SVG's default black fill paints over the navy background gradient. The
     generator adds ``fill="none"`` to that rect so the declared
     ``#111D2D -> #07111E`` gradient is visible. No geometry, colour, or
     proportion of the mark changes.
   * the background ``<rect>`` elements are stripped to export the "mark" (U
     monogram + earbuds + wave accents) on transparency. Android adaptive icons
     require the foreground and background to be separate layers.
3. Rasterise the two SVG variants with a headless Chromium browser
   (Chrome/Edge). Set ``UAM_CHROME_BIN`` to override discovery.
4. Derive every platform icon with Pillow.

Usage
-----
    python scripts/branding/generate_brand_assets.py            # use cached masters
    python scripts/branding/generate_brand_assets.py --render   # re-render masters from SVG
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

# --------------------------------------------------------------------------- #
# Paths
# --------------------------------------------------------------------------- #

REPO_ROOT = Path(__file__).resolve().parents[2]
FLUTTER = REPO_ROOT / "app" / "flutter"

BRANDING = FLUTTER / "assets" / "branding"
CANONICAL_SVG = BRANDING / "uam_logo.svg"

MASTER_TILE = BRANDING / "uam_logo.png"  # 1024 rounded tile, in-app + reference
MASTER_MARK = BRANDING / "uam_logo_mark.png"  # 1024 mark, transparent

ANDROID_RES = FLUTTER / "android" / "app" / "src" / "main" / "res"
WINDOWS_ICO = FLUTTER / "windows" / "runner" / "resources" / "app_icon.ico"
MACOS_APPICON = (
    FLUTTER / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
)
IOS_APPICON = FLUTTER / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
LINUX_ASSETS = FLUTTER / "linux" / "assets"
PREVIEW_DIR = BRANDING / "preview"

MASTER_SIZE = 1024
VIEWBOX = 512

# Brand colours declared by the canonical SVG.
BG_STOP_START = (0x11, 0x1D, 0x2D)
BG_STOP_END = (0x07, 0x11, 0x1E)

# Android density buckets -> legacy icon px, adaptive layer px.
ANDROID_DENSITIES = {
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}

# Content scale inside generated composites.
ADAPTIVE_FOREGROUND_SCALE = 0.60  # within the 66% adaptive safe zone
BLEED_MARK_SCALE = 0.74  # opaque full-bleed square (iOS)
ROUND_MARK_SCALE = 0.62  # legacy circular launcher icon

CHROME_CANDIDATES = [
    os.environ.get("UAM_CHROME_BIN", ""),
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
]


# --------------------------------------------------------------------------- #
# SVG handling
# --------------------------------------------------------------------------- #


def read_svg() -> str:
    if not CANONICAL_SVG.exists():
        raise SystemExit(f"canonical SVG missing: {CANONICAL_SVG}")
    return CANONICAL_SVG.read_text(encoding="utf-8")


def corrected_svg(svg: str) -> str:
    """Add ``fill="none"`` to stroke-only rects (source paints them black)."""

    def fix(match: re.Match[str]) -> str:
        rect = match.group(0)
        return rect if "fill=" in rect else rect[: -len("/>")] + ' fill="none"/>'

    return re.sub(r"<rect\b[^>]*/>", fix, svg)


def mark_svg(svg: str) -> str:
    """Remove the background/border rects so the mark renders on transparency."""
    return re.sub(r"[ \t]*<rect\b[^>]*/>\n?", "", corrected_svg(svg))


def svg_document(svg: str, size: int) -> str:
    body = re.sub(
        r"<svg\b[^>]*>",
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
        f'viewBox="0 0 {VIEWBOX} {VIEWBOX}" preserveAspectRatio="xMidYMid meet">',
        svg,
        count=1,
    )
    return (
        "<!doctype html><html><head><meta charset=\"utf-8\"><style>"
        "html,body{margin:0;padding:0;background:transparent;overflow:hidden}"
        "svg{display:block}</style></head><body>" + body + "</body></html>"
    )


def find_chrome() -> str | None:
    for candidate in CHROME_CANDIDATES:
        if candidate and Path(candidate).exists():
            return candidate
    for name in ("google-chrome", "chromium", "chromium-browser", "chrome"):
        found = shutil.which(name)
        if found:
            return found
    return None


def render_svg(svg: str, size: int, out_png: Path) -> None:
    chrome = find_chrome()
    if chrome is None:
        raise SystemExit(
            "no Chromium-based browser found; set UAM_CHROME_BIN to render masters"
        )
    out_png.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        html = Path(tmp) / "render.html"
        html.write_text(svg_document(svg, size), encoding="utf-8")
        # Chromium requires an absolute file:// URL.
        url = html.resolve().as_uri()
        cmd = [
            chrome,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--force-device-scale-factor=1",
            "--no-first-run",
            "--no-default-browser-check",
            f"--window-size={size},{size}",
            "--default-background-color=00000000",
            f"--screenshot={out_png.resolve()}",
            url,
        ]
        subprocess.run(cmd, capture_output=True, check=False)
    if not out_png.exists():
        raise SystemExit(f"renderer produced no output for {out_png}")
    with Image.open(out_png) as raw:
        img = raw.convert("RGBA")
    if img.size != (size, size):
        img = img.resize((size, size), Image.LANCZOS)
    img.save(out_png)
    print(f"  rendered {out_png.relative_to(REPO_ROOT)} ({size}x{size})")


# --------------------------------------------------------------------------- #
# Pillow helpers
# --------------------------------------------------------------------------- #


def navy_gradient(size: int) -> Image.Image:
    """Diagonal navy gradient matching the canonical SVG background."""
    small = 256
    base = Image.new("RGBA", (small, small))
    px = base.load()
    span = 2 * (small - 1)
    for y in range(small):
        for x in range(small):
            t = (x + y) / span
            px[x, y] = (
                round(BG_STOP_START[0] + (BG_STOP_END[0] - BG_STOP_START[0]) * t),
                round(BG_STOP_START[1] + (BG_STOP_END[1] - BG_STOP_START[1]) * t),
                round(BG_STOP_START[2] + (BG_STOP_END[2] - BG_STOP_START[2]) * t),
                255,
            )
    if size == small:
        return base
    return base.resize((size, size), Image.LANCZOS)


def content_box(img: Image.Image) -> tuple[int, int, int, int]:
    box = img.getbbox()
    if box is None:
        raise ValueError("image has no visible content")
    return box


def mark_on_transparent(mark: Image.Image, size: int, frac: float) -> Image.Image:
    """Scale the mark so its longest side is ``frac`` of ``size``, centered."""
    box = content_box(mark)
    cropped = mark.crop(box)
    target = max(1, round(size * frac))
    w, h = cropped.size
    if w >= h:
        new = (target, max(1, round(h * target / w)))
    else:
        new = (max(1, round(w * target / h)), target)
    scaled = cropped.resize(new, Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(scaled, ((size - new[0]) // 2, (size - new[1]) // 2))
    return canvas


def on_navy(size: int, mark: Image.Image, frac: float) -> Image.Image:
    canvas = navy_gradient(size)
    canvas.alpha_composite(mark_on_transparent(mark, size, frac))
    return canvas


def circular(img: Image.Image) -> Image.Image:
    size = img.size[0]
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    out = img.copy()
    out.putalpha(mask)
    return out


def save_png(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, format="PNG", optimize=True)


# --------------------------------------------------------------------------- #
# Outputs
# --------------------------------------------------------------------------- #


def write_branding_masters(tile: Image.Image, mark: Image.Image) -> None:
    save_png(tile, MASTER_TILE)
    save_png(mark, MASTER_MARK)
    save_png(on_navy(MASTER_SIZE, mark, BLEED_MARK_SCALE), BRANDING / "uam_app_icon.png")
    save_png(
        mark_on_transparent(mark, MASTER_SIZE, ADAPTIVE_FOREGROUND_SCALE),
        BRANDING / "uam_app_icon_foreground.png",
    )
    save_png(navy_gradient(MASTER_SIZE), BRANDING / "uam_app_icon_background.png")


def write_android(tile: Image.Image, mark: Image.Image) -> None:
    anydpi = ANDROID_RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    for name in ("ic_launcher", "ic_launcher_round"):
        (anydpi / f"{name}.xml").write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            "</adaptive-icon>\n",
            encoding="utf-8",
        )
    for density, (legacy, adaptive) in ANDROID_DENSITIES.items():
        out = ANDROID_RES / f"mipmap-{density}"
        out.mkdir(parents=True, exist_ok=True)
        save_png(tile.resize((legacy, legacy), Image.LANCZOS), out / "ic_launcher.png")
        save_png(
            circular(on_navy(legacy, mark, ROUND_MARK_SCALE)),
            out / "ic_launcher_round.png",
        )
        save_png(
            mark_on_transparent(mark, adaptive, ADAPTIVE_FOREGROUND_SCALE),
            out / "ic_launcher_foreground.png",
        )
        save_png(navy_gradient(adaptive), out / "ic_launcher_background.png")


def write_windows(tile: Image.Image) -> None:
    WINDOWS_ICO.parent.mkdir(parents=True, exist_ok=True)
    tile.resize((256, 256), Image.LANCZOS).save(
        WINDOWS_ICO,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


def write_macos(tile: Image.Image) -> None:
    for size in (16, 32, 64, 128, 256, 512, 1024):
        save_png(
            tile.resize((size, size), Image.LANCZOS), MACOS_APPICON / f"app_icon_{size}.png"
        )


IOS_SIZES = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}


def write_ios(mark: Image.Image) -> None:
    # Apple rejects alpha in app icons: flatten onto the navy background.
    for name, size in IOS_SIZES.items():
        icon = on_navy(size, mark, BLEED_MARK_SCALE).convert("RGB")
        path = IOS_APPICON / name
        path.parent.mkdir(parents=True, exist_ok=True)
        icon.save(path, format="PNG", optimize=True)


LINUX_SIZES = (16, 24, 32, 48, 64, 128, 256, 512)


def write_linux(tile: Image.Image) -> None:
    for size in LINUX_SIZES:
        save_png(tile.resize((size, size), Image.LANCZOS), LINUX_ASSETS / f"uam_icon_{size}.png")
    (LINUX_ASSETS / "com.kiandrahd.uam.desktop").write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=UAM\n"
        "GenericName=Universe Audio Management\n"
        "Comment=Universe Audio Management\n"
        "Exec=uam\n"
        "Icon=com.kiandrahd.uam\n"
        "Terminal=false\n"
        "Categories=AudioVideo;Audio;Utility;\n"
        "StartupWMClass=com.kiandrahd.uam\n",
        encoding="utf-8",
    )


def write_preview(tile: Image.Image, mark: Image.Image) -> None:
    sizes = (16, 24, 32, 48, 64, 128, 256)
    pad, gap, label_h = 16, 20, 18
    width = pad * 2 + sum(sizes) + gap * (len(sizes) - 1)
    height = pad * 2 + max(sizes) + label_h
    sheet = Image.new("RGB", (width, height), (26, 26, 30))
    draw = ImageDraw.Draw(sheet)
    x = pad
    for size in sizes:
        icon = tile.resize((size, size), Image.LANCZOS)
        y = pad + (max(sizes) - size) // 2
        sheet.paste(icon, (x, y), icon)
        draw.text((x, pad + max(sizes) + 2), f"{size}px", fill=(200, 205, 212))
        x += size + gap
    save_png(sheet, PREVIEW_DIR / "uam_icon_preview.png")

    # Second row: the transparent mark and the adaptive layers, for review.
    mark_sizes = (64, 128, 256)
    row_h = max(mark_sizes)
    row = Image.new("RGB", (width, pad + row_h + label_h), (26, 26, 30))
    draw = ImageDraw.Draw(row)
    draw.text((pad, 2), "mark / adaptive foreground", fill=(200, 205, 212))
    x = pad
    for size in mark_sizes:
        icon = mark_on_transparent(mark, size, ADAPTIVE_FOREGROUND_SCALE)
        row.paste(icon, (x, 16), icon)
        draw.text((x, 16 + row_h + 2), f"{size}px", fill=(200, 205, 212))
        x += size + gap
    sheet = Image.new("RGB", (width, height + row.height + 8), (26, 26, 30))
    sheet.paste(Image.open(PREVIEW_DIR / "uam_icon_preview.png"), (0, 0))
    sheet.paste(row, (0, height + 8))
    save_png(sheet, PREVIEW_DIR / "uam_icon_preview.png")
    save_png(row, PREVIEW_DIR / "uam_mark_preview.png")


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #


def load_masters(render: bool) -> tuple[Image.Image, Image.Image]:
    if render or not (MASTER_TILE.exists() and MASTER_MARK.exists()):
        print("rendering masters from canonical SVG")
        svg = read_svg()
        render_svg(corrected_svg(svg), MASTER_SIZE, MASTER_TILE)
        render_svg(mark_svg(svg), MASTER_SIZE, MASTER_MARK)
    tile = Image.open(MASTER_TILE).convert("RGBA")
    mark = Image.open(MASTER_MARK).convert("RGBA")
    return tile, mark


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--render",
        action="store_true",
        help="re-render the 1024px masters from the canonical SVG before deriving icons",
    )
    args = parser.parse_args(argv)

    tile, mark = load_masters(args.render)
    write_branding_masters(tile, mark)
    write_android(tile, mark)
    write_windows(tile)
    write_macos(tile)
    write_ios(mark)
    write_linux(tile)
    write_preview(tile, mark)

    print(
        json.dumps(
            {
                "canonical_svg": str(CANONICAL_SVG.relative_to(REPO_ROOT)),
                "branding": sorted(
                    str(p.relative_to(REPO_ROOT)) for p in BRANDING.glob("*")
                ),
                "android_densities": {k: v for k, v in ANDROID_DENSITIES.items()},
                "windows_ico": str(WINDOWS_ICO.relative_to(REPO_ROOT)),
                "macos_icons": len(list(MACOS_APPICON.glob("*.png"))),
                "ios_icons": len(list(IOS_APPICON.glob("*.png"))),
                "linux_icons": len(list(LINUX_ASSETS.glob("uam_icon_*.png"))),
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
