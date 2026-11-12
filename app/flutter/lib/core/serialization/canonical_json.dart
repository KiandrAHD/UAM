import 'dart:collection';

/// A deterministic, order-sensitive JSON encoder.
///
/// The backup container and the preset export use this encoder so an identical
/// dataset always produces byte-identical JSON (and therefore a stable
/// checksum). Keys are emitted in sorted order, and doubles use the shortest
/// round-trip representation Dart provides.
String encodeCanonicalJson(Object? value) {
  final buffer = StringBuffer();
  _write(value, buffer);
  return buffer.toString();
}

void _write(Object? value, StringBuffer buffer) {
  if (value == null) {
    buffer.write('null');
    return;
  }
  if (value is bool) {
    buffer.write(value ? 'true' : 'false');
    return;
  }
  if (value is num) {
    if (value is double) {
      if (!value.isFinite) {
        throw ArgumentError('Non-finite numbers cannot be serialized.');
      }
      if (value == value.roundToDouble() && value.abs() < 1e16) {
        // Emit integral doubles as integers for stable, compact output.
        buffer.write(value.toInt().toString());
        return;
      }
    }
    buffer.write(value.toString());
    return;
  }
  if (value is String) {
    buffer.write(_encodeString(value));
    return;
  }
  if (value is List<Object?>) {
    buffer.write('[');
    for (var index = 0; index < value.length; index += 1) {
      if (index > 0) {
        buffer.write(',');
      }
      _write(value[index], buffer);
    }
    buffer.write(']');
    return;
  }
  if (value is Map<String, Object?>) {
    final keys = SplayTreeSet<String>.of(value.keys);
    buffer.write('{');
    var first = true;
    for (final key in keys) {
      if (!first) {
        buffer.write(',');
      }
      first = false;
      buffer.write(_encodeString(key));
      buffer.write(':');
      _write(value[key], buffer);
    }
    buffer.write('}');
    return;
  }
  if (value is Map<Object?, Object?>) {
    final normalized = <String, Object?>{};
    for (final entry in value.entries) {
      normalized[entry.key.toString()] = entry.value;
    }
    _write(normalized, buffer);
    return;
  }
  throw ArgumentError('Unsupported value of type ${value.runtimeType}.');
}

String _encodeString(String value) {
  final buffer = StringBuffer('"');
  for (final rune in value.runes) {
    switch (rune) {
      case 0x22:
        buffer.write(r'\"');
      case 0x5C:
        buffer.write(r'\\');
      case 0x0A:
        buffer.write(r'\n');
      case 0x0D:
        buffer.write(r'\r');
      case 0x09:
        buffer.write(r'\t');
      case 0x08:
        buffer.write(r'\b');
      case 0x0C:
        buffer.write(r'\f');
      default:
        if (rune < 0x20) {
          buffer.write(r'\u' + rune.toRadixString(16).padLeft(4, '0'));
        } else {
          buffer.writeCharCode(rune);
        }
    }
  }
  buffer.write('"');
  return buffer.toString();
}
