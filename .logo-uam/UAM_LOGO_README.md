# UAM Logo Asset

- `uam_logo.svg`: scalable vector source (512 × 512 viewBox).
- `uam_logo_1024.png`: 1024 × 1024 raster export.

Brand direction: midnight navy, electric blue and cyan. The central U-shaped mark represents Universe Audio Management; paired earbud forms indicate TWS, while side arcs evoke wireless audio.

## Flutter / Android integration

For a clean asset integration, use `flutter_launcher_icons` or the Android adaptive icon resources generated from this source. Do not replace only `mipmap/ic_launcher.png` while leaving adaptive icon XML pointing to the old foreground/background assets.

Suggested Flutter asset registration:

```yaml
flutter:
  assets:
    - assets/branding/uam_logo.png
```

The Android launcher icon is configured in `app/flutter/android/app/src/main/AndroidManifest.xml` via `android:icon="@mipmap/ic_launcher"`. Generate all mipmap densities and adaptive icon foreground/background assets from the logo, then rebuild the APK.
