# Backup and Restore

## Backup format

A `.uam-backup` file is UTF-8 JSON with format ID `uam-backup`, version 1, a database schema version, a data section, and SHA-256 checksum over canonical JSON data.

The data section contains presets (including source/favorite/timestamps), user-facing settings, and active preset ID. Keys beginning `internal.` are excluded. Backup payloads are limited to 8 MiB.

## Create a backup

1. Open **Settings**.
2. Select the backup action and choose a destination.
3. UAM self-parses the generated package before writing it atomically.
4. On success it records the timestamp and file basename in local settings.

A backup requires at least one preset. The seeded built-ins mean a normal initialized library satisfies this requirement.

## Restore a backup

1. Choose a `.uam-backup` file.
2. UAM reads it with a size bound, parses it, verifies format/version/checksum, and validates every embedded preset.
3. Review the displayed summary and explicitly confirm.
4. UAM attempts to write a pre-restore snapshot.
5. Restore replaces non-built-in presets and user-facing appearance/general settings in one SQLite transaction, restores eligible active selection, then runs integrity/equivalence checks.

Cancelled, corrupt, future-format, future-schema, or invalid-preset packages do not modify local data. Built-in rows are protected; restore may update backed-up built-in content only through the controlled transaction.

## Recovery

A pre-restore snapshot is saved under the UAM support backup directory when writable. If snapshot creation fails, the restore can still proceed only after validation and transaction protection; the event is logged. Keep exported backups in a user-controlled location for long-term recovery.

## Validation evidence

`test/unit/backup_service_test.dart` covers package creation, atomic write/inspect, checksum corruption, malformed/future containers, duplicate IDs, confirmation, future schema rejection, invalid preset rejection, pre-restore snapshot, replacement behavior, and restored data equivalence.
