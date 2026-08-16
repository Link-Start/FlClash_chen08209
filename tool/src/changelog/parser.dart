import 'models.dart';

/// A single rendered line of a version, together with the group it belongs to.
class ChangelogItem {
  const ChangelogItem({required this.type, required this.entry});

  final ChangelogType type;
  final ChangelogEntry entry;
}

const _skipMarker = 'skip';

const _defaultTypes = <String, ChangelogType>{
  'feat': ChangelogType.feat,
  'fix': ChangelogType.fix,
  'perf': ChangelogType.perf,
  'revert': ChangelogType.revert,
};

final _subjectPattern = RegExp(r'^([a-z]+)(?:\(([^)]*)\))?(!)?:[ \t]+(.+)$');

final _trailerPattern = RegExp(
  r'^(BREAKING[ -]CHANGE|Changelog(?:-[A-Za-z0-9-]+)?|Breaking-[A-Za-z0-9-]+):[ \t]*(.*)$',
);

/// Turns conventional commits into changelog items.
///
/// The parser is pure: it never touches git or the filesystem, so every rule
/// below is covered by `test/tool/changelog_parser_test.dart`.
class ChangelogParser {
  final List<String> warnings = <String>[];

  List<ChangelogItem> parseAll(List<RawCommit> commits) =>
      commits.expand(parse).toList();

  List<ChangelogItem> parse(RawCommit commit) {
    final match = _subjectPattern.firstMatch(commit.subject.trim());
    if (match == null) {
      warnings.add(
        '${commit.shortHash} is not a conventional commit: ${commit.subject}',
      );
      return const <ChangelogItem>[];
    }

    final type = match.group(1)!;
    final scope = match.group(2);
    final bang = match.group(3) != null;
    final description = match.group(4)!.trim();

    final trailers = _readTrailers(commit);
    final changelog = trailers['Changelog'];
    if (changelog != null && changelog.toLowerCase() == _skipMarker) {
      return const <ChangelogItem>[];
    }

    final items = <ChangelogItem>[];
    final breakingText = trailers['BREAKING CHANGE'];
    if (bang || breakingText != null) {
      if (breakingText == null) {
        warnings.add(
          '${commit.shortHash} is marked breaking but has no '
          '"BREAKING CHANGE:" footer; using the subject instead.',
        );
      }
      items.add(
        ChangelogItem(
          type: ChangelogType.breaking,
          entry: ChangelogEntry(
            id: commit.shortHash,
            scope: _normalizeScope(scope),
            text: _collectText(
              trailers,
              prefix: 'Breaking',
              fallback: breakingText ?? _capitalize(description),
            ),
          ),
        ),
      );
    }

    final group = _resolveType(type, trailers, commit);
    if (group != null) {
      items.add(
        ChangelogItem(
          type: group,
          entry: ChangelogEntry(
            id: commit.shortHash,
            scope: _normalizeScope(scope),
            text: _collectText(
              trailers,
              prefix: 'Changelog',
              fallback: changelog ?? _capitalize(description),
            ),
          ),
        ),
      );
    }

    return items;
  }

  ChangelogType? _resolveType(
    String type,
    Map<String, String> trailers,
    RawCommit commit,
  ) {
    final override = trailers['Changelog-Type'];
    if (override != null) {
      final resolved = ChangelogType.fromId(override);
      if (resolved == null) {
        warnings.add(
          '${commit.shortHash} has an unknown Changelog-Type: $override',
        );
      }
      return resolved ?? ChangelogType.feat;
    }
    final byType = _defaultTypes[type];
    if (byType != null) {
      return byType;
    }
    return trailers.containsKey('Changelog') ? ChangelogType.feat : null;
  }

  Map<String, String> _collectText(
    Map<String, String> trailers, {
    required String prefix,
    required String fallback,
  }) {
    final text = <String, String>{changelogFallbackLocale: fallback};
    for (final locale in changelogLocales) {
      if (locale == changelogFallbackLocale) {
        continue;
      }
      final value = trailers['$prefix-$locale'];
      if (value != null && value.isNotEmpty) {
        text[locale] = value;
      }
    }
    return text;
  }

  Map<String, String> _readTrailers(RawCommit commit) {
    final trailers = <String, String>{};
    String? currentKey;
    for (final line in commit.body.split('\n')) {
      final match = _trailerPattern.firstMatch(line);
      if (match != null) {
        currentKey = match
            .group(1)!
            .replaceAll('BREAKING-CHANGE', 'BREAKING CHANGE');
        _warnUnknownLocale(currentKey, commit);
        trailers[currentKey] = match.group(2)!.trim();
        continue;
      }
      if (currentKey == null) {
        continue;
      }
      final continuation = line.trim();
      if (continuation.isEmpty) {
        currentKey = null;
        continue;
      }
      trailers[currentKey] = '${trailers[currentKey]} $continuation'.trim();
    }
    return trailers;
  }

  void _warnUnknownLocale(String key, RawCommit commit) {
    for (final prefix in const ['Changelog-', 'Breaking-']) {
      if (!key.startsWith(prefix)) {
        continue;
      }
      final suffix = key.substring(prefix.length);
      if (suffix == 'Type' && prefix == 'Changelog-') {
        return;
      }
      if (!changelogLocales.contains(suffix)) {
        warnings.add(
          '${commit.shortHash} uses an unknown changelog locale: $key',
        );
      }
      return;
    }
  }
}

/// Collapses items into the groups of one version, keeping [ChangelogType]
/// declaration order and dropping groups that ended up empty.
List<ChangelogGroup> groupItems(List<ChangelogItem> items) {
  final groups = <ChangelogGroup>[];
  for (final type in ChangelogType.values) {
    final entries = items
        .where((item) => item.type == type)
        .map((item) => item.entry)
        .toList();
    if (entries.isNotEmpty) {
      groups.add(ChangelogGroup(type: type, entries: entries));
    }
  }
  return groups;
}

String? _normalizeScope(String? scope) {
  final trimmed = scope?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _capitalize(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toUpperCase() + value.substring(1);
}
