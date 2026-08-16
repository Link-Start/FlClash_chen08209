import 'dart:convert';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/changelog.dart';

import 'common.dart';

/// Opens the HTML comment `tool/changelog.dart render release` appends to the
/// release body. It is invisible on the release page and rides along with the
/// response `checkForUpdate` already makes, so the notes need no request of
/// their own.
const releaseChangelogJsonMarker = '<!-- flclash:changelog:json';

const _releaseChangelogJsonEndMarker = '-->';

String changelogGroupTitle(
  AppLocalizations appLocalizations,
  ChangelogType type,
) => switch (type) {
  ChangelogType.breaking => appLocalizations.changelogBreaking,
  ChangelogType.feat => appLocalizations.changelogFeatures,
  ChangelogType.fix => appLocalizations.changelogFixes,
  ChangelogType.perf => appLocalizations.changelogPerformance,
  ChangelogType.revert => appLocalizations.changelogReverts,
  ChangelogType.unknown => '',
};

/// The translated notes for a release, or null when the body predates the
/// embedded block or was written by a newer `tool/changelog.dart`. Callers fall
/// back to [parseReleaseBody], which reads the English bullets instead.
ChangelogVersion? parseReleaseChangelog(String? body) {
  if (body == null) {
    return null;
  }
  final begin = body.indexOf(releaseChangelogJsonMarker);
  if (begin < 0) {
    return null;
  }
  final start = begin + releaseChangelogJsonMarker.length;
  final end = body.indexOf(_releaseChangelogJsonEndMarker, start);
  if (end < 0) {
    return null;
  }
  try {
    final changelog = Changelog.fromJson(
      jsonDecode(body.substring(start, end)) as Map<String, dynamic>,
    );
    if (!changelog.isSupported) {
      commonPrint.log(
        'changelog schema ${changelog.schemaVersion} is not supported',
        logLevel: LogLevel.warning,
      );
      return null;
    }
    return changelog.versions.firstOrNull;
  } catch (error) {
    commonPrint.log(
      'changelog decode failed ${compactError(error)}',
      logLevel: LogLevel.warning,
    );
    return null;
  }
}
