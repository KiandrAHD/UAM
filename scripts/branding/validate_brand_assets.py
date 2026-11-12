#!/usr/bin/env python3
"""Validate generated UAM launcher assets and platform references."""

from __future__ import annotations

import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
FLUTTER = ROOT / "app" / "flutter"
BRANDING = FLUTTER / "assets" / "branding"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def png(path: Path, expected: tuple[int, int] | None = None) -> tuple[int, int, str]:
    require(path.is_file(), f"missing PNG: {path.relative_to(ROOT)}")
    with Image.open(path) as image:
        image.load()
        size = image.size
        mode = image.mode
        if expected is not None:
            require(size == expected, f"{path.relative_to(ROOT)}: {size} != {expected}")
        return size[0], size[1], mode


def verify_asset_catalog(path: Path, platform: str) -> int:
    data = json.loads(path.read_text(encoding="utf-8"))
    require(data.get("info", {}).get("version") == 1, f"{platform} info.version must be 1")
    images = data.get("images")
    require(isinstance(images, list) and images, f"{platform} catalog has no images")
    for item in images:
        filename = item.get("filename")
        if not filename:
            continue
        asset = path.parent / filename
        require(asset.is_file(), f"{platform} catalog missing {filename}")
        with Image.open(asset) as image:
            image.load()
            require(image.width == image.height, f"{filename} is not square")
            if platform == "ios":
                require(image.mode in ("RGB", "P"), f"iOS icon {filename} has alpha mode {image.mode}")
                if image.mode == "P":
                    require("transparency" not in image.info, f"iOS icon {filename} has palette alpha")
                else:
                    require("A" not in image.getbands(), f"iOS icon {filename} has alpha channel")
    return len(images)


def main() -> int:
    print("UAM asset validation")
    print("-" * 64)

    svg_path = BRANDING / "uam_logo.svg"
    svg = svg_path.read_text(encoding="utf-8")
    ET.fromstring(svg)
    require("id=\"bg\"" in svg and "id=\"blue\"" in svg, "official SVG gradients missing")
    source_svg = (ROOT / ".logo-uam" / "uam_logo.svg").read_bytes()
    require(svg_path.read_bytes() == source_svg, "canonical SVG differs from official source")
    print("PASS canonical SVG valid and byte-identical to official source")

    tile = BRANDING / "uam_logo.png"
    mark = BRANDING / "uam_logo_mark.png"
    foreground = BRANDING / "uam_app_icon_foreground.png"
    background = BRANDING / "uam_app_icon_background.png"
    fullbleed = BRANDING / "uam_app_icon.png"
    for path in (tile, mark, foreground, background, fullbleed):
        png(path, (1024, 1024))
    with Image.open(mark) as image:
        require(image.mode == "RGBA", "transparent mark must be RGBA")
        require(image.getpixel((0, 0))[3] == 0, "mark corner must be transparent")
    with Image.open(foreground) as image:
        require(image.mode == "RGBA", "adaptive foreground must preserve alpha")
        require(image.getpixel((0, 0))[3] == 0, "adaptive foreground corner must be transparent")
    with Image.open(background) as image:
        require(image.mode == "RGBA", "adaptive background must be RGBA")
        require(image.getpixel((0, 0))[3] == 255, "adaptive background must be opaque")
    print("PASS branding master dimensions and alpha policies")

    mipmap = FLUTTER / "android" / "app" / "src" / "main" / "res"
    expected_android = {"mdpi": (48, 108), "hdpi": (72, 162), "xhdpi": (96, 216), "xxhdpi": (144, 324), "xxxhdpi": (192, 432)}
    for density, (legacy, adaptive) in expected_android.items():
        folder = mipmap / f"mipmap-{density}"
        for name in ("ic_launcher.png", "ic_launcher_round.png"):
            png(folder / name, (legacy, legacy))
        for name in ("ic_launcher_foreground.png", "ic_launcher_background.png"):
            png(folder / name, (adaptive, adaptive))
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        icon_xml = mipmap / "mipmap-anydpi-v26" / name
        root = ET.parse(icon_xml).getroot()
        require(root.tag.endswith("adaptive-icon"), f"{name} is not an adaptive icon")
        refs = [node.attrib.get("{http://schemas.android.com/apk/res/android}drawable") for node in root]
        require(refs == ["@mipmap/ic_launcher_background", "@mipmap/ic_launcher_foreground"], f"{name} references unexpected layers: {refs}")
    manifest = (FLUTTER / "android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
    require('android:icon="@mipmap/ic_launcher"' in manifest, "Android manifest does not reference ic_launcher")
    require('applicationId = "com.kiandrahd.uam"' in (FLUTTER / "android/app/build.gradle.kts").read_text(encoding="utf-8"), "Android application ID changed")
    print("PASS Android densities, adaptive XML, manifest and application ID")

    ico_path = FLUTTER / "windows/runner/resources/app_icon.ico"
    with Image.open(ico_path) as ico:
        require(ico.format == "ICO", "Windows icon is not an ICO")
        sizes = set(ico.info.get("sizes", set()))
        expected = {(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)}
        require(expected.issubset(sizes), f"Windows ICO sizes missing: {sorted(expected - sizes)}")
    runner_rc = (FLUTTER / "windows/runner/Runner.rc").read_text(encoding="utf-8")
    require('resources\\\\app_icon.ico' in runner_rc or 'resources\\app_icon.ico' in runner_rc, "Runner.rc ICO reference missing")
    print(f"PASS Windows ICO embedded sizes {sorted(sizes)}")

    mac_count = verify_asset_catalog(FLUTTER / "macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json", "macos")
    ios_count = verify_asset_catalog(FLUTTER / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json", "ios")
    require(ios_count >= 19, "iOS catalog must include iPhone and iPad slots")
    plist = (FLUTTER / "ios/Runner/Info.plist").read_text(encoding="utf-8")
    ET.fromstring(plist)
    require("<string>UAM</string>" in plist, "iOS display name is not UAM")
    print(f"PASS macOS catalog ({mac_count} entries) and iOS catalog ({ios_count} entries), all files/dimensions and alpha policies valid")

    desktop = FLUTTER / "linux/assets/com.kiandrahd.uam.desktop"
    text = desktop.read_text(encoding="utf-8")
    require("Name=UAM" in text and "Icon=com.kiandrahd.uam" in text, "Linux desktop entry missing identity/icon")
    icon_sizes = (16, 24, 32, 48, 64, 128, 256, 512)
    for size in icon_sizes:
        png(FLUTTER / f"linux/assets/uam_icon_{size}.png", (size, size))
    cmake = (FLUTTER / "linux/CMakeLists.txt").read_text(encoding="utf-8")
    require("share/applications" in cmake and "share/icons/hicolor" in cmake, "Linux install paths are missing")
    print("PASS Linux icon sizes, desktop entry and freedesktop install paths")

    pubspec = (FLUTTER / "pubspec.yaml").read_text(encoding="utf-8")
    require("assets/branding/uam_logo.png" in pubspec, "pubspec branding asset registration missing")
    component = (FLUTTER / "lib/design_system/components/uam_components.dart").read_text(encoding="utf-8")
    require("assets/branding/uam_logo.png" in component, "UamBrandMark is not wired to official asset")
    require((BRANDING / "preview/uam_icon_preview.png").is_file(), "icon preview missing")
    require((BRANDING / "preview/uam_mark_preview.png").is_file(), "mark preview missing")
    print("PASS pubspec, in-app branding and preview contact sheets")
    print("\nALL BRAND ASSET CHECKS PASSED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, OSError, ValueError, json.JSONDecodeError, ET.ParseError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
