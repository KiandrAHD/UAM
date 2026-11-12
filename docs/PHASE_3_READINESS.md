# Kesiapan Fase 3 — Data Lokal dan Pertukaran Preset

**Tanggal evaluasi:** 2026-11-12  
**Status:** Siap untuk review dan CI; tidak diklaim siap rilis lintas-platform atau bebas cacat.

## Gate kesiapan

| Gate | Status | Bukti |
|---|---|---|
| Database file produksi tanpa fallback volatile | Lulus | `UamServices.initialize()` membuka database pada application support. `bootstrap()` menampilkan `UamBootstrapErrorApp` bila inisialisasi gagal. |
| Migrasi dan pemeriksaan integritas | Lulus | `PRAGMA user_version`, transaksi migrasi, `integrity_check`, dan `foreign_key_check`; 18 test migrasi. |
| Preset CRUD offline | Lulus | `SqlitePresetRepository`; 26 test repository; coverage widget untuk aksi library. |
| Built-in terlindungi | Lulus | Seed idempoten; built-in tidak dapat diubah/dihapus/ditimpa melalui impor. |
| Setting persisten sejak startup | Lulus | Tema, reduced motion, dan launch at startup dibaca sebelum frame pertama; 16 test settings. |
| Impor aman dan dapat dipreview | Lulus | Batas input 256 KiB, validasi UTF-8/schema/rentang, preview read-only, resolusi konflik; 26 test exchange. |
| Ekspor tanpa false-success | Lulus | Pembatalan save picker menghasilkan hasil batal, tidak snackbar sukses; test widget tersedia. |
| Backup/restore tervalidasi dan transaksional | Lulus | Batas 8 MiB, SHA-256, snapshot, konfirmasi, dan transaksi; 24 test backup. |
| Regresi Flutter | Lulus | `flutter test --concurrency=1`: 190 test lulus. |
| Static analysis dan format Flutter | Lulus | `dart format --output=none --set-exit-if-changed .`: 0 perubahan; `flutter analyze`: tanpa isu. |
| Regresi Rust | Lulus | `cargo fmt --check`, `cargo clippy --workspace --all-targets --locked -- -D warnings`, dan `cargo test --workspace --locked` lulus. |
| Fixture preset dan aset merek | Lulus | `validate_presets.py`: 3 valid/8 invalid; `validate_brand_assets.py`: lulus. |
| Build Android debug arm64 | Lulus | APK dibuat di `build/app/outputs/flutter-apk/app-debug.apk`. |
| Build Windows debug lokal | Tertunda karena host | Developer Mode/izin symlink tidak tersedia. CI Windows ditambahkan, tetapi belum ada hasil workflow pada saat dokumen ini ditulis. |
| Uji perangkat Android | Belum dilakukan | Tidak ada perangkat fisik yang divalidasi. |
| Build macOS/Linux/iOS | Belum dilakukan | Tidak tersedia pada host Windows. |

## Rincian test Fase 3

| Berkas | Jumlah | Fokus |
|---|---:|---|
| `database_migration_test.dart` | 18 | Schema, WAL, FK, rollback, integrity, dan reuse koneksi |
| `settings_repository_test.dart` | 16 | Encoding, type safety, default, dan hapus settings |
| `sqlite_preset_repository_test.dart` | 26 | CRUD, query, filter, built-in, dan transaksi |
| `preset_exchange_service_test.dart` | 26 | Decode, preview, validasi, konflik, impor, dan ekspor |
| `backup_service_test.dart` | 24 | Kontainer, checksum, snapshot, restore, dan equivalence |
| `phase3_persistence_test.dart` | 8 | Alur UI impor, ekspor batal, settings, backup, dan restore |

## Risiko dan mitigasi

| Risiko | Mitigasi saat ini | Tindak lanjut |
|---|---|---|
| File database korup atau tidak dapat dibuka | Error database dipetakan ke `UamDataException`; bootstrap menghentikan aplikasi pada layar error eksplisit. | Tambahkan alur pemulihan/restore yang dapat dipilih pengguna pada fase berikutnya. |
| File impor berbahaya atau tidak valid | Batas ukuran, UTF-8, validasi schema/rentang, dan tidak ada write sebelum commit. | Uji fuzz/property untuk parser dan container backup. |
| Konflik ID preset | Preview dan resolusi eksplisit; built-in tidak dapat ditimpa. | Pertimbangkan UX batch-import bila dibutuhkan. |
| Restore menyebabkan data tidak konsisten | Validasi penuh, snapshot pra-restore, transaksi SQLite, integrity/equivalence checks. | Tambahkan observabilitas pemulihan dan retensi snapshot yang dapat dikonfigurasi. |
| Perbedaan platform file picker/database | Gateway file diisolasi dan database memakai FFI SQLite. | Jalankan CI serta pengujian manual di Windows, macOS, Linux, Android, dan iOS. |

## Keputusan siap lanjut

Implementasi Fase 3 dapat dilanjutkan ke review branch dan CI. Gate berikut masih wajib sebelum klaim dukungan platform yang lebih luas:

1. Push branch dan pastikan semua job GitHub Actions hijau, termasuk `windows-debug`.
2. Jalankan build dan smoke test pada host Windows dengan Developer Mode aktif.
3. Uji APK debug pada perangkat Android nyata.
4. Jalankan build/test native pada Linux, macOS, dan iOS di runner atau host yang sesuai.
5. Jangan klaim pemrosesan audio system-wide atau kontrol perangkat: keduanya berada di fase berikutnya.