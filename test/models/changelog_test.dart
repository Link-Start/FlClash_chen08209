import 'dart:convert';
import 'dart:ui';

import 'package:fl_clash/models/changelog.dart';
import 'package:flutter_test/flutter_test.dart';

const _payload = '''
{
  "schemaVersion": 1,
  "versions": [
    {
      "version": "0.8.96",
      "tag": "v0.8.96",
      "date": "2026-08-16",
      "prerelease": false,
      "groups": [
        {
          "type": "breaking",
          "entries": [
            {
              "id": "af20769",
              "scope": "lib",
              "text": {"en": "Backups need re-import"}
            }
          ]
        },
        {
          "type": "feat",
          "entries": [
            {
              "id": "1a2b3c4",
              "text": {"en": "Override scripts", "zh-CN": "覆写脚本"}
            }
          ]
        }
      ]
    }
  ]
}
''';

Changelog decode(String source) =>
    Changelog.fromJson(jsonDecode(source) as Map<String, dynamic>);

void main() {
  group('Changelog.fromJson', () {
    test('decodes the payload written by tool/changelog.dart', () {
      final changelog = decode(_payload);

      expect(changelog.isSupported, isTrue);
      expect(changelog.versions.single.tag, 'v0.8.96');
      expect(changelog.versions.single.date, '2026-08-16');
      expect(changelog.versions.single.prerelease, isFalse);
      expect(
        changelog.versions.single.groups.first.type,
        ChangelogType.breaking,
      );
      expect(
        changelog.versions.single.groups.first.entries.single.scope,
        'lib',
      );
    });

    test('maps an unrecognised group type to unknown instead of throwing', () {
      final changelog = decode('''
{
  "schemaVersion": 1,
  "versions": [
    {
      "version": "0.9.0",
      "tag": "v0.9.0",
      "groups": [
        {"type": "docs", "entries": [{"id": "abc1234", "text": {"en": "x"}}]}
      ]
    }
  ]
}
''');

      expect(
        changelog.versions.single.groups.single.type,
        ChangelogType.unknown,
      );
      expect(changelog.versions.single.visibleGroups, isEmpty);
      expect(changelog.versions.single.isEmpty, isTrue);
    });

    test('reports an unsupported schema version', () {
      expect(
        decode('{"schemaVersion": 99, "versions": []}').isSupported,
        isFalse,
      );
    });

    test('tolerates a version without optional fields', () {
      final changelog = decode(
        '{"schemaVersion": 1, "versions": [{"version": "1.0.0", "tag": "v1.0.0"}]}',
      );

      expect(changelog.versions.single.date, '');
      expect(changelog.versions.single.groups, isEmpty);
    });
  });

  group('ChangelogEntry.textFor', () {
    test('prefers the requested locale', () {
      final entry = decode(_payload).versions.single.groups.last.entries.single;

      expect(entry.textFor('zh-CN'), '覆写脚本');
    });

    test('falls back to english for a locale without a translation', () {
      final entry = decode(_payload).versions.single.groups.last.entries.single;

      expect(entry.textFor('ja'), 'Override scripts');
    });

    test('returns an empty string when even english is missing', () {
      const entry = ChangelogEntry(id: 'abc1234');

      expect(entry.textFor('en'), '');
    });
  });

  group('changelogLocaleKey', () {
    test('uses the bare language code when there is no country', () {
      expect(changelogLocaleKey(const Locale('en')), 'en');
      expect(changelogLocaleKey(const Locale('ja')), 'ja');
    });

    test('joins language and country the way the arb files are named', () {
      expect(changelogLocaleKey(const Locale('zh', 'CN')), 'zh-CN');
    });

    test('treats an empty country code as absent', () {
      expect(changelogLocaleKey(const Locale('ru', '')), 'ru');
    });
  });
}
