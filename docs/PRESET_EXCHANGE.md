# Preset Exchange

## File format

UAM imports and exports UTF-8 JSON files ending in `.uam-preset.json`. The current contract is schema version 1, defined by `database/schema/preset.schema.json` and mirrored by Dart `PresetCodec` for this phase.

Required root fields:

```json
{
  "format": "uam-preset",
  "schemaVersion": 1,
  "metadata": { "name": "Example" },
  "compatibility": {
    "minimumUamVersion": "0.1.0",
    "deviceIndependent": true
  },
  "audio": {
    "preampDb": 0,
    "equalizer": { "bands": [] }
  }
}
```

## Import behavior

1. Choose a file or paste JSON.
2. UAM bounds input to 256 KiB, requires UTF-8, then validates strict schema fields and DSP numeric limits.
3. A preview shows preset name, band count, preamp, and compatibility/editor warnings.
4. Validation is read-only. Rejected or cancelled imports never modify the library.
5. A valid candidate is committed only after the user selects a duplicate outcome.

Duplicate options:

- **Keep existing:** no write.
- **Import as new:** creates an `imported-<micros>` ID.
- **Replace existing:** only offered for eligible user/imported conflicts.

Built-ins can never be overwritten. An identical built-in document reports a built-in collision and defaults to keeping the existing preset.

## Export behavior

Export serializes the normalized local record back to pretty, deterministic schema-v1 JSON. File names derive from the preset name and replace filesystem-reserved characters. The native save picker is used in production; widget tests use an injected gateway.

## Compatibility notes

Import validation confirms document shape, not attached-device support. Warnings explain required capabilities, shelving filters, and documents with more than ten bands because the graphic editor maps rather than perfectly represents those filters.

## Validation evidence

- `python scripts/test/validate_presets.py`
- `test/unit/preset_codec_test.dart`
- `test/unit/preset_exchange_service_test.dart`
- `test/widget/presets_import_test.dart`
