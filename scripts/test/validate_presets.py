#!/usr/bin/env python3
"""Validate UAM preset fixtures against the published JSON Schema.

Valid fixtures must pass; files whose names start with ``invalid-`` must fail.
This script is development tooling only and is not part of the application
runtime. It uses the standard ``jsonschema`` package.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from jsonschema import Draft202012Validator, FormatChecker
except ImportError as error:  # pragma: no cover - environment guidance
    raise SystemExit(
        "jsonschema is required: python -m pip install jsonschema"
    ) from error

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = REPO_ROOT / "database" / "schema" / "preset.schema.json"
FIXTURE_DIR = REPO_ROOT / "database" / "fixtures" / "sample-presets"
MAX_BYTES = 256 * 1024


def load_schema() -> dict:
    with SCHEMA_PATH.open(encoding="utf-8") as handle:
        schema = json.load(handle)
    Draft202012Validator.check_schema(schema)
    return schema


def validate_file(validator: Draft202012Validator, path: Path) -> list[str]:
    if path.stat().st_size > MAX_BYTES:
        return [f"file exceeds {MAX_BYTES} bytes"]
    try:
        with path.open(encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        return [f"parse failure: {error}"]
    errors = sorted(validator.iter_errors(document), key=lambda item: list(item.path))
    return [error.message for error in errors]


def main() -> int:
    validator = Draft202012Validator(load_schema(), format_checker=FormatChecker())
    if not FIXTURE_DIR.is_dir():
        print(f"Fixture directory missing: {FIXTURE_DIR}")
        return 2

    failures: list[str] = []
    valid_count = 0
    invalid_count = 0

    for path in sorted(FIXTURE_DIR.glob("*.uam-preset.json")):
        errors = validate_file(validator, path)
        expected_invalid = path.name.startswith("invalid-")
        if expected_invalid:
            invalid_count += 1
            if not errors:
                failures.append(f"INVALID fixture accepted: {path.name}")
            else:
                print(f"REJECTED as expected: {path.name} -> {errors[0]}")
        else:
            valid_count += 1
            if errors:
                failures.append(f"VALID fixture rejected: {path.name} -> {errors[0]}")
            else:
                print(f"VALID: {path.name}")

    print()
    print(f"Valid fixtures: {valid_count}")
    print(f"Invalid fixtures: {invalid_count}")

    if valid_count == 0 or invalid_count == 0:
        failures.append("expected both valid and invalid fixtures")
    if failures:
        print("FAILED")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    print("PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())