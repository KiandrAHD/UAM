import '../../../shared/models/equalizer_configuration.dart';
import '../../../shared/models/preset_document.dart';
import '../domain/preset_entry.dart';
import '../domain/preset_source.dart';

/// Canonical built-in presets.
///
/// IDs are stable and never regenerated, so seeding is idempotent and
/// favorites survive re-seeding. Documents mirror the repository reference
/// fixtures under `presets/examples/`.
List<PresetEntry> builtInPresetEntries() {
  return <PresetEntry>[
    PresetEntry(
      id: 'builtin-balanced-warm',
      source: PresetSource.builtin,
      createdAt: '2026-01-01T00:00:00Z',
      document: PresetDocument(
        metadata: const PresetMetadata(
          name: 'Balanced Warm',
          author: 'UAM Phase 0 Fixture',
          description:
              'A balanced profile with gentle low-frequency warmth and a soft '
              'treble lift.',
          createdAt: '2026-01-01T00:00:00Z',
          tags: <String>['balanced', 'warm'],
        ),
        compatibility: const PresetCompatibility(),
        audio: PresetAudio(
          preampDb: -2,
          bands: const <EqBandConfiguration>[
            EqBandConfiguration(
              filterType: EqFilterType.peaking,
              frequencyHz: 60,
              gainDb: 2,
              q: 1,
            ),
            EqBandConfiguration(
              filterType: EqFilterType.peaking,
              frequencyHz: 250,
              gainDb: 1,
              q: 1,
            ),
            EqBandConfiguration(
              filterType: EqFilterType.peaking,
              frequencyHz: 1000,
              gainDb: 0,
              q: 1,
            ),
            EqBandConfiguration(
              filterType: EqFilterType.peaking,
              frequencyHz: 4000,
              gainDb: -1,
              q: 1,
            ),
            EqBandConfiguration(
              filterType: EqFilterType.peaking,
              frequencyHz: 10000,
              gainDb: 1.5,
              q: 1,
            ),
          ],
        ),
      ),
    ),
    PresetEntry(
      id: 'builtin-neutral-reference',
      source: PresetSource.builtin,
      createdAt: '2026-03-01T08:00:00Z',
      document: PresetDocument(
        metadata: const PresetMetadata(
          name: 'Neutral Reference',
          author: 'UAM Phase 0 Fixture',
          description:
              'Zero preamp and no bands. Useful for verifying that a valid '
              'preset may contain an empty equalizer list.',
          createdAt: '2026-03-01T08:00:00Z',
          tags: <String>['neutral', 'reference'],
        ),
        compatibility: const PresetCompatibility(),
        audio: const PresetAudio(preampDb: 0, bands: <EqBandConfiguration>[]),
      ),
    ),
    PresetEntry(
      id: 'builtin-shelf-bass-boost',
      source: PresetSource.builtin,
      createdAt: '2026-02-14T12:30:00Z',
      document: PresetDocument(
        metadata: const PresetMetadata(
          name: 'Shelf Bass Boost',
          author: 'UAM Phase 0 Fixture',
          description:
              'Low-shelf bass lift with a restrained high-shelf cut, used to '
              'exercise both shelving filter shapes.',
          createdAt: '2026-02-14T12:30:00Z',
          tags: <String>['bass', 'shelf'],
        ),
        compatibility: const PresetCompatibility(
          requiredCapabilities: <String>['dsp.eq.peaking', 'dsp.eq.shelving'],
        ),
        audio: PresetAudio(
          preampDb: -4.5,
          bands: const <EqBandConfiguration>[
            EqBandConfiguration(
              filterType: EqFilterType.lowShelf,
              frequencyHz: 120,
              gainDb: 6,
              q: 0.707,
            ),
            EqBandConfiguration(
              filterType: EqFilterType.highShelf,
              frequencyHz: 8000,
              gainDb: -2.5,
              q: 0.707,
            ),
          ],
        ),
      ),
    ),
  ];
}
