import 'migration.dart';
import 'migration_001_initial.dart';

/// The schema this build ships.
///
/// Add new files as `migration_00N_description.dart` and append them here; the
/// registry sorts by `version` and rejects duplicates or non-increasing
/// versions at construction time.
final MigrationRegistry uamMigrations = MigrationRegistry(<Migration>[
  migration001Initial,
]);
