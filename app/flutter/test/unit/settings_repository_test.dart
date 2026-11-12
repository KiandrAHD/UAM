import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uam/core/database/app_setting_keys.dart';
import 'package:uam/features/settings/data/settings_repository.dart';

import '../support/test_data_stack.dart';

void main() {
  late TestDataStack stack;
  late SettingsRepository settings;

  setUp(() async {
    stack = await TestDataStack.create();
    settings = stack.settings;
  });

  tearDown(() async {
    await stack.dispose();
  });

  group('SqliteSettingsRepository', () {
    test('an unknown key reads as null', () async {
      expect(await settings.get<String>('does.not.exist'), isNull);
    });

    test('writes and reads back a boolean', () async {
      await settings.set<bool>(AppSettingKeys.reducedMotion, true);
      expect(await settings.get<bool>(AppSettingKeys.reducedMotion), isTrue);
    });

    test('writes and reads back a string', () async {
      await settings.set<String>(AppSettingKeys.themeMode, 'dark');
      expect(await settings.get<String>(AppSettingKeys.themeMode), 'dark');
    });

    test('writes and reads back a list and a map', () async {
      await settings.set<List<String>>('custom.tags', <String>['a', 'b']);
      await settings.set<Map<String, int>>('custom.map', <String, int>{'x': 1});
      // JSON decoding yields dynamic collections, so callers read them back as
      // `List<dynamic>` / `Map<String, dynamic>`; typed generics are not
      // re-derived. This is the documented storage contract.
      expect(await settings.get<List<dynamic>>('custom.tags'), <dynamic>[
        'a',
        'b',
      ]);
      expect(
        await settings.get<Map<String, dynamic>>('custom.map'),
        <String, dynamic>{'x': 1},
      );
    });

    test('overwriting a key replaces the value', () async {
      await settings.set<bool>(AppSettingKeys.reducedMotion, true);
      await settings.set<bool>(AppSettingKeys.reducedMotion, false);
      expect(await settings.get<bool>(AppSettingKeys.reducedMotion), isFalse);
      final all = await settings.getAll();
      expect(
        all.keys.where((key) => key == AppSettingKeys.reducedMotion),
        hasLength(1),
      );
    });

    test('remove deletes the row and reports whether it existed', () async {
      await settings.set<bool>(AppSettingKeys.launchAtStartup, true);
      expect(await settings.remove(AppSettingKeys.launchAtStartup), isTrue);
      expect(await settings.get<bool>(AppSettingKeys.launchAtStartup), isNull);
      expect(await settings.remove(AppSettingKeys.launchAtStartup), isFalse);
    });

    test('a type mismatch reads as absent instead of throwing', () async {
      await settings.set<bool>(AppSettingKeys.reducedMotion, true);
      expect(await settings.get<String>(AppSettingKeys.reducedMotion), isNull);
      expect(await settings.get<int>(AppSettingKeys.reducedMotion), isNull);
    });

    test('an int value is readable as a double', () async {
      await settings.set<int>('custom.number', 3);
      expect(await settings.get<double>('custom.number'), 3.0);
    });

    test('invalid JSON in a row reads as absent and is skipped', () async {
      await stack.services.database.rawInsert(
        'INSERT INTO app_settings (key, value_json, updated_at) '
        'VALUES (?, ?, ?)',
        <Object?>['custom.broken', '{not json', '2026-01-01T00:00:00.000Z'],
      );
      expect(await settings.get<String>('custom.broken'), isNull);
      final all = await settings.getAll();
      expect(all.containsKey('custom.broken'), isFalse);
    });

    test('setting keys are matched exactly, not case-insensitively', () async {
      await settings.set<String>('Custom.Key', 'value');
      expect(await settings.get<String>('custom.key'), isNull);
      expect(await settings.get<String>('Custom.Key'), 'value');
    });

    test('getAll returns every readable setting sorted by key', () async {
      await settings.set<bool>('b.second', true);
      await settings.set<bool>('a.first', true);
      final all = await settings.getAll();
      final keys = all.keys.toList();
      expect(keys, equals(List<String>.from(keys)..sort()));
      expect(all['a.first'], isTrue);
    });

    test(
      'resetToDefaults clears appearance and general settings only',
      () async {
        await settings.set<String>(AppSettingKeys.themeMode, 'dark');
        await settings.set<bool>(AppSettingKeys.reducedMotion, true);
        await settings.set<bool>(AppSettingKeys.launchAtStartup, true);
        await settings.set<String>('custom.keep', 'value');

        await settings.resetToDefaults();

        expect(await settings.get<String>(AppSettingKeys.themeMode), isNull);
        expect(await settings.get<bool>(AppSettingKeys.reducedMotion), isNull);
        expect(
          await settings.get<bool>(AppSettingKeys.launchAtStartup),
          isNull,
        );
        expect(await settings.get<String>('custom.keep'), 'value');
      },
    );

    test('values survive a reopen of the same database file', () async {
      await settings.set<String>(AppSettingKeys.themeMode, 'light');
      await settings.set<bool>(AppSettingKeys.reducedMotion, true);

      final reopened = await stack.reopen();
      addTearDown(() => reopened.dispose(deleteDirectory: false));
      expect(
        await reopened.settings.get<String>(AppSettingKeys.themeMode),
        'light',
      );
      expect(
        await reopened.settings.get<bool>(AppSettingKeys.reducedMotion),
        isTrue,
      );
    });

    test('the stored value is JSON encoded, not raw text', () async {
      await settings.set<String>(AppSettingKeys.themeMode, 'dark');
      final rows = await stack.services.database.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: <Object?>[AppSettingKeys.themeMode],
      );
      expect(rows, hasLength(1));
      expect(rows.single['value_json'], '"dark"');
      expect(jsonDecode(rows.single['value_json']! as String), 'dark');
    });

    test(
      'an unknown key namespace is not restricted by the repository',
      () async {
        await settings.set<String>('future.namespace.value', 'x');
        expect(
          await settings.get<String>('future.namespace.value'),
          'x',
          reason: 'The repository must not block keys added by later versions.',
        );
      },
    );

    test(
      'a non-serializable value fails the write instead of storing junk',
      () async {
        await expectLater(
          settings.set<Object>('custom.bad', const Object()),
          throwsA(isA<Object>()),
        );
        expect(await settings.get<String>('custom.bad'), isNull);
      },
    );
  });
}
