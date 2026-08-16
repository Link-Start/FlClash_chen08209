import 'dart:ui';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'generated/changelog.freezed.dart';
part 'generated/changelog.g.dart';

/// Matches `schemaVersion` in the payload `tool/changelog.dart` embeds in the
/// release body. A newer payload is ignored rather than half decoded.
const changelogSchemaVersion = 1;

const changelogFallbackLocale = 'en';

enum ChangelogType { breaking, feat, fix, perf, revert, unknown }

@freezed
abstract class ChangelogEntry with _$ChangelogEntry {
  const factory ChangelogEntry({
    required String id,
    String? scope,
    @Default({}) Map<String, String> text,
  }) = _ChangelogEntry;

  factory ChangelogEntry.fromJson(Map<String, dynamic> json) =>
      _$ChangelogEntryFromJson(json);
}

@freezed
abstract class ChangelogGroup with _$ChangelogGroup {
  const factory ChangelogGroup({
    @JsonKey(unknownEnumValue: ChangelogType.unknown)
    @Default(ChangelogType.unknown)
    ChangelogType type,
    @Default([]) List<ChangelogEntry> entries,
  }) = _ChangelogGroup;

  factory ChangelogGroup.fromJson(Map<String, dynamic> json) =>
      _$ChangelogGroupFromJson(json);
}

@freezed
abstract class ChangelogVersion with _$ChangelogVersion {
  const factory ChangelogVersion({
    required String version,
    required String tag,
    @Default('') String date,
    @Default(false) bool prerelease,
    @Default([]) List<ChangelogGroup> groups,
  }) = _ChangelogVersion;

  factory ChangelogVersion.fromJson(Map<String, dynamic> json) =>
      _$ChangelogVersionFromJson(json);
}

@freezed
abstract class Changelog with _$Changelog {
  const factory Changelog({
    @Default(0) int schemaVersion,
    @Default([]) List<ChangelogVersion> versions,
  }) = _Changelog;

  factory Changelog.fromJson(Map<String, dynamic> json) =>
      _$ChangelogFromJson(json);
}

extension ChangelogEntryExt on ChangelogEntry {
  String textFor(String locale) =>
      text[locale] ?? text[changelogFallbackLocale] ?? '';
}

extension ChangelogVersionExt on ChangelogVersion {
  List<ChangelogGroup> get visibleGroups => groups
      .where((group) => group.type != ChangelogType.unknown)
      .where((group) => group.entries.isNotEmpty)
      .toList();

  bool get isEmpty => visibleGroups.isEmpty;
}

extension ChangelogExt on Changelog {
  bool get isSupported => schemaVersion == changelogSchemaVersion;
}

/// Maps a Flutter locale onto the keys used by the changelog payload, which
/// follow the `arb/intl_*.arb` names: `en`, `zh-CN`, `ja`, `ru`.
String changelogLocaleKey(Locale locale) {
  final country = locale.countryCode;
  if (country == null || country.isEmpty) {
    return locale.languageCode;
  }
  return '${locale.languageCode}-$country';
}
