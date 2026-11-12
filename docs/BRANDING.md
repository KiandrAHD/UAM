# UAM Branding

## Official source and canonical assets

The authoritative artwork is `.logo-uam/uam_logo.svg`, introduced by commit
`b24b998`. It is copied byte-for-byte to
`app/flutter/assets/branding/uam_logo.svg`; its SHA-256 is
`FD0F157B62559A3DC5F53EA259E09E5658B33054B0CBE91A93E19805A06780D5`.

The logo is the UAM U-monogram with paired TWS earbuds and wireless wave
accents. Its palette is midnight navy (`#111D2D`/`#07111E`), electric blue,
and cyan. The original source remains unchanged.

## Generated assets

Run this from the repository root:

```powershell
python scripts/branding/generate_brand_assets.py --render
```

The generator uses Chromium to render SVG and Pillow to make deterministic
platform sizes. Set `UAM_CHROME_BIN` if Chrome or Edge is not auto-detected.
It produces:

- `app/flutter/assets/branding/uam_logo.png`: 1024px official in-app tile.
- `uam_logo_mark.png`: transparent logo mark.
- `uam_app_icon.png`, `uam_app_icon_foreground.png`, and
  `uam_app_icon_background.png`: opaque tile plus Android adaptive layers.
- `preview/uam_icon_preview.png` and `preview/uam_mark_preview.png`: review
  contact sheets.

The source SVG's decorative border rect has no `fill="none"`; SVG therefore
renders it as a black fill over the declared navy gradient. The generator adds
that missing paint attribute only while rasterising. This preserves all
artwork geometry, proportions, and declared colours while exposing the source
background gradient. It never changes the canonical SVG.

## Platform locations

| Platform | Assets/configuration |
| --- | --- |
| Android | `android/app/src/main/res/mipmap-*`, `mipmap-anydpi-v26`, `branding.xml`; `AndroidManifest.xml` keeps `@mipmap/ic_launcher` |
| Windows | `windows/runner/resources/app_icon.ico`; `Runner.rc` references it |
| Linux | `linux/assets/`; CMake installs the `.desktop` entry and hicolor icons |
| macOS | `macos/Runner/Assets.xcassets/AppIcon.appiconset` |
| iOS | `ios/Runner/Assets.xcassets/AppIcon.appiconset` |
| Flutter UI | `assets/branding/uam_logo.png`, used by `UamBrandMark` |

iOS icons are flattened RGB PNGs, because App Store icons may not include an
alpha channel. Android foreground assets preserve alpha and use a conservative
60% safe-zone scale. Legacy and Apple icons use the official navy background.

## Validation and host limits

`python scripts/branding/validate_brand_assets.py` checks PNG dimensions,
alpha policy, ICO embedded sizes, XML/JSON/plist structure, asset references,
and the Linux desktop entry. Inspect `preview/uam_icon_preview.png` before
shipping. Windows can build Windows and Android here; Linux, macOS, and iOS
need their native hosts for compilation.
