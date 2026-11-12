# Laporan Implementasi Fase 3 — Data Lokal dan Pertukaran Preset

**Status:** Implementasi selesai dan tervalidasi secara lokal pada 2026-11-12.  
**Branch:** `feat/phase-3-local-data-preset-exchange`  
**Commit:** akan dicatat setelah perubahan Fase 3 dikomit.  
**PR:** belum dibuat pada saat laporan ini ditulis.

## Ringkasan

Fase 3 menambahkan penyimpanan lokal SQLite, CRUD preset, persistensi pengaturan, impor/ekspor preset, serta backup/restore. Aplikasi bekerja tanpa akun atau cloud. Kegagalan pembukaan atau pemeriksaan database ditampilkan sebagai layar error bootstrap; aplikasi produksi tidak memakai fallback database in-memory.

## Penyelesaian per fase kerja

| Area | Status | Bukti implementasi dan validasi |
|---|---|---|
| Fondasi database | Selesai, diuji unit | `UamDatabase` membuka `<application-support>/UAM/uam.db`, memakai WAL, foreign key, `busy_timeout`, `PRAGMA user_version`, migrasi, serta `integrity_check` dan `foreign_key_check`. `database_migration_test.dart` memiliki 18 pengujian. |
| Persistensi preset | Selesai, diuji unit dan widget | Repository SQLite menyimpan preset, filter berurutan, favorit, sumber, metadata, dan preset aktif. Built-in di-seed idempoten serta tidak dapat diubah/dihapus. `sqlite_preset_repository_test.dart` memiliki 26 pengujian. |
| Persistensi settings | Selesai, diuji unit dan widget | Pengaturan tema, reduced motion, dan launch at startup diserialisasi sebagai JSON. Bootstrap membaca nilai sebelum frame pertama. `settings_repository_test.dart` memiliki 16 pengujian. |
| Pertukaran preset | Selesai, diuji unit dan widget | Impor memverifikasi batas ukuran, UTF-8, bentuk/rentang schema v1, preview, peringatan kompatibilitas, dan resolusi duplikat. Ekspor memakai dialog file native serta tidak melaporkan sukses ketika dibatalkan. `preset_exchange_service_test.dart` memiliki 26 pengujian. |
| Backup dan restore | Selesai, diuji unit dan widget | Paket `.uam-backup` memiliki format/version/checksum SHA-256, batas 8 MiB, penulisan atomik, snapshot pra-restore, konfirmasi, dan restore transaksional. `backup_service_test.dart` memiliki 24 pengujian. |
| Integrasi UI | Selesai, diuji widget | Halaman Presets menyediakan preview/commit impor dan pemilihan resolusi konflik. Settings menyediakan pembuatan, pemilihan, konfirmasi restore, serta pesan kegagalan yang eksplisit. `phase3_persistence_test.dart` memiliki 8 pengujian. |
| CI | Diperbarui | `flutter-ci.yml` menjalankan validasi fixture preset dan menambahkan job Windows debug build. |

## Desain yang diterapkan

- Database: SQLite melalui `sqflite_common_ffi` dan `sqlite3_flutter_libs` pada lima target Flutter.
- Versi schema: `PRAGMA user_version` adalah satu-satunya sumber versi migrasi.
- Tabel v1: `presets`, `preset_filters`, `app_settings`, `profiles`, dan `device_aliases`.
- Kontrak preset: `uam-preset` schema v1 di `database/schema/preset.schema.json`; validasi aplikasi dilakukan oleh Dart `PresetCodec` pada fase ini.
- Kontrak backup: `uam-backup` versi 1 dengan data JSON kanonis dan checksum SHA-256.
- Dependency injection: `UamServices` menjadi composition root database, repository, exchange service, backup service, dan file gateway.

Dokumen desain rinci: [DATABASE_DESIGN.md](DATABASE_DESIGN.md), [DATABASE_MIGRATIONS.md](DATABASE_MIGRATIONS.md), [PRESET_EXCHANGE.md](PRESET_EXCHANGE.md), dan [BACKUP_RESTORE.md](BACKUP_RESTORE.md).

## File yang berubah

### Implementasi Flutter

- `app/flutter/lib/core/database/`
- `app/flutter/lib/core/files/atomic_file_writer.dart`
- `app/flutter/lib/core/serialization/canonical_json.dart`
- `app/flutter/lib/app/services/uam_services.dart`
- `app/flutter/lib/bootstrap.dart`
- `app/flutter/lib/app/uam_app.dart`
- `app/flutter/lib/app/state/uam_app_controller.dart`
- `app/flutter/lib/features/presets/`
- `app/flutter/lib/features/settings/`
- `app/flutter/lib/features/backup/`
- `app/flutter/lib/platform/files/preset_file_gateway.dart`
- `app/flutter/lib/platform/share/preset_file_export.dart`
- `app/flutter/pubspec.yaml` dan `app/flutter/pubspec.lock`

### Pengujian

- `app/flutter/test/unit/database_migration_test.dart`
- `app/flutter/test/unit/settings_repository_test.dart`
- `app/flutter/test/unit/sqlite_preset_repository_test.dart`
- `app/flutter/test/unit/preset_exchange_service_test.dart`
- `app/flutter/test/unit/backup_service_test.dart`
- `app/flutter/test/widget/phase3_persistence_test.dart`
- Infrastruktur test di `app/flutter/test/support/`
- Penyesuaian test aplikasi dan integration smoke test.

### Konfigurasi dan dokumentasi

- `.github/workflows/flutter-ci.yml`
- `app/flutter/android/gradle.properties`
- `docs/DATABASE_DESIGN.md`
- `docs/DATABASE_MIGRATIONS.md`
- `docs/PRESET_EXCHANGE.md`
- `docs/BACKUP_RESTORE.md`
- `docs/PHASE_3_READINESS.md`

## Perintah validasi yang selesai dijalankan

Dari root repositori:

```powershell
python scripts/branding/validate_brand_assets.py
python scripts/test/validate_presets.py
```

Dari `crates/`:

```powershell
cargo fmt --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
```

Dari `app/flutter/`:

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --concurrency=1
flutter build apk --debug --target-platform android-arm64
```

Hasil tercatat:

- Validasi aset merek: lulus.
- Validasi fixture preset: lulus, 3 valid dan 8 invalid.
- Rust format, clippy, dan test: lulus.
- Flutter format: 105 berkas, 0 perubahan.
- Flutter analyze: `No issues found!`.
- Flutter test: `190 All tests passed!`.
- Android APK debug arm64: berhasil dibuat pada `app/flutter/build/app/outputs/flutter-apk/app-debug.apk`.

## Cara menggunakan

### Preset

1. Buka **Presets**.
2. Untuk impor, pilih file `.uam-preset.json` atau masukkan JSON bila UI tersebut tersedia.
3. Tinjau preview dan peringatan kompatibilitas.
4. Bila ID bentrok, pilih **Keep existing**, **Import as new**, atau **Replace existing** jika diizinkan.
5. Untuk ekspor, pilih preset lalu pilih lokasi tujuan. Pembatalan dialog tidak mengubah data dan tidak menampilkan sukses.

### Backup dan restore

1. Buka **Settings** dan pilih aksi backup.
2. Pilih lokasi file `.uam-backup`.
3. Untuk restore, pilih file backup, tinjau ringkasan, lalu konfirmasi secara eksplisit.
4. UAM memverifikasi format, versi, checksum, dan seluruh preset sebelum melakukan transaksi restore.

## Keterbatasan yang diketahui

- `flutter build windows --debug` belum dapat dijalankan pada host referensi. Flutter membutuhkan izin symlink Windows dan host ini tidak memiliki Developer Mode/privilege symlink. Job `windows-debug` telah ditambahkan ke CI GitHub Actions untuk memverifikasi build tersebut pada runner Windows.
- Build native macOS, Linux, dan iOS tidak tersedia pada host Windows ini.
- APK Android berhasil dibangun, tetapi belum diuji pada perangkat fisik.
- Validasi schema preset dalam aplikasi memakai `PresetCodec` Dart yang mencerminkan schema v1; FFI Rust tidak dipakai sebagai validator pada Fase 3.
- Fase ini tidak menambahkan backend audio, pemrosesan audio system-wide, discovery perangkat, atau kontrol perangkat keras.

## Penyerahan

Commit hash dan URL pull request harus ditambahkan setelah branch dipush dan PR dibuat. Lihat [PHASE_3_READINESS.md](PHASE_3_READINESS.md) untuk status gate rilis dan bukti kesiapan.