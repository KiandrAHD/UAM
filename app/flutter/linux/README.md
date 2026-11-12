# Linux branding assets

`assets/com.kiandrahd.uam.desktop` and `assets/uam_icon_<size>.png` are generated
from `app/flutter/assets/branding/uam_logo.svg` by
`python scripts/branding/generate_brand_assets.py --render` at repository root.

The Linux CMake install rules place the launcher in
`share/applications/` and the icons in the standard freedesktop
`share/icons/hicolor/<size>x<size>/apps/` locations.
