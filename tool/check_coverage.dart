import 'dart:io';

const _defaultReport = 'coverage/lcov.info';

const _excludedPatterns = [
  '/generated/',
  'lib/l10n/',
  '.g.dart',
  '.freezed.dart',
];

// Every measured group needs a floor. A group that only answers to the total
// floor can rot for free, because a large well-covered group pays for it: that
// is how `pages`, `plugins` and `lib` reached 20-50% while the total stayed
// green. Adding a top-level directory under `lib/` therefore means adding its
// floor here, and `main()` fails the run until you do.
//
// Floors ratchet up only. Raise one when new tests lift a group; never lower
// one to make a run pass.
const _groupFloors = <String, double>{
  'core': 73.0,
  'database': 84.0,
  'widgets': 83.0,
  'features': 82.0,
  'models': 68.0,
  'providers': 69.0,
  'common': 72.0,
  'manager': 52.0,
  'views': 63.0,
  'enum': 89.0,
  'pages': 50.0,
  'plugins': 60.0,
  'lib': 20.0,
};

class _Coverage {
  int found = 0;
  int hit = 0;

  double get percent => found == 0 ? 0 : hit / found * 100;
}

bool _isExcluded(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return _excludedPatterns.any(normalized.contains);
}

String _group(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final index = normalized.indexOf('lib/');
  if (index == -1) {
    return 'other';
  }
  final relative = normalized.substring(index + 4);
  final separator = relative.indexOf('/');
  return separator == -1 ? 'lib' : relative.substring(0, separator);
}

void main(List<String> arguments) {
  final reportPath = arguments.isNotEmpty ? arguments.first : _defaultReport;
  final minimum = arguments.length > 1 ? double.parse(arguments[1]) : 0.0;

  final report = File(reportPath);
  if (!report.existsSync()) {
    stderr.writeln('Coverage report not found: $reportPath');
    exit(1);
  }

  final total = _Coverage();
  final byGroup = <String, _Coverage>{};
  var source = '';
  var excluded = false;

  for (final line in report.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      source = line.substring(3);
      excluded = _isExcluded(source);
      continue;
    }
    if (excluded || source.isEmpty) {
      continue;
    }
    final group = byGroup.putIfAbsent(_group(source), _Coverage.new);
    if (line.startsWith('LF:')) {
      final found = int.parse(line.substring(3));
      total.found += found;
      group.found += found;
    } else if (line.startsWith('LH:')) {
      final hit = int.parse(line.substring(3));
      total.hit += hit;
      group.hit += hit;
    }
  }

  if (total.found == 0) {
    stderr.writeln('No measurable lines in $reportPath after exclusions.');
    exit(1);
  }

  final groups = byGroup.entries.toList()
    ..sort((a, b) => b.value.found.compareTo(a.value.found));
  final failures = <String>[];
  for (final entry in groups) {
    final coverage = entry.value;
    final floor = _groupFloors[entry.key];
    final below = floor != null && coverage.percent < floor;
    if (below) {
      failures.add(
        '${entry.key} ${coverage.percent.toStringAsFixed(2)}% is below its '
        '${floor.toStringAsFixed(2)}% floor.',
      );
    }
    stdout.writeln(
      '${entry.key.padRight(12)} '
      '${coverage.hit.toString().padLeft(6)}/${coverage.found.toString().padLeft(6)} '
      '${coverage.percent.toStringAsFixed(1).padLeft(6)}%'
      '${floor == null ? ' (NO FLOOR)' : ' (floor ${floor.toStringAsFixed(0)}%)'}'
      '${below ? ' FAIL' : ''}',
    );
  }
  stdout.writeln(
    'TOTAL (generated code excluded): '
    '${total.hit}/${total.found} ${total.percent.toStringAsFixed(2)}%',
  );

  final missing = _groupFloors.keys
      .where((group) => !byGroup.containsKey(group))
      .toList();
  for (final group in missing) {
    failures.add('$group has a floor but no measured lines in the report.');
  }

  final unguarded = groups
      .map((entry) => entry.key)
      .where((group) => !_groupFloors.containsKey(group))
      .toList();
  for (final group in unguarded) {
    failures.add(
      '$group is measured but has no floor in _groupFloors; add one at or '
      'below its current coverage.',
    );
  }

  if (total.percent < minimum) {
    failures.add(
      'TOTAL ${total.percent.toStringAsFixed(2)}% is below the '
      '${minimum.toStringAsFixed(2)}% floor.',
    );
  }

  if (failures.isEmpty) {
    return;
  }
  for (final failure in failures) {
    stderr.writeln(failure);
  }
  exit(1);
}
