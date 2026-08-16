import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String pluginSource;

  setUpAll(() {
    pluginSource = File('windows/tray_plugin.cpp').readAsStringSync();
  });

  test('windows menu clicks come from TrackPopupMenu, not WM_COMMAND', () {
    expect(pluginSource, contains('TPM_RETURNCMD'));
    expect(pluginSource, isNot(contains('WM_COMMAND')));
  });

  test('windows show reports a failed icon load', () {
    expect(
      pluginSource,
      contains('''
  if (loaded == nullptr) {
    return false;
  }'''),
    );
  });

  test('windows show reports a rejected shell notification', () {
    expect(pluginSource, contains('bool applied = ApplyIcon(!visible_);'));
    expect(pluginSource, contains('return applied;'));
  });
}
