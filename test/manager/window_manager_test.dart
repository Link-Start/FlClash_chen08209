import 'dart:async';

import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/window_manager.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart' show WindowListener;

import '../helpers/test_profiles.dart';

const _windowChannel = MethodChannel('window_manager');

class _RecordingSystemAction extends SystemAction {
  static final calls = <String>[];

  @override
  Future<void> handleClose([bool exit = true]) async {
    calls.add('close');
  }

  @override
  Future<void> handleExit([bool needSave = false]) async {
    calls.add('exit');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late Rect bounds;
  Completer<void>? boundsGate;

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  setUp(() {
    _RecordingSystemAction.calls.clear();
    bounds = const Rect.fromLTWH(0, 0, 1000, 800);
    boundsGate = null;
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        systemActionProvider.overrideWith(_RecordingSystemAction.new),
      ],
    );
    globalState.container = container;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (call) async {
          if (call.method == 'getBounds') {
            await boundsGate?.future;
            return <String, double>{
              'x': bounds.left,
              'y': bounds.top,
              'width': bounds.width,
              'height': bounds.height,
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, null);
    container.dispose();
  });

  Future<WindowListener> pumpWindowManager(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WindowManager(child: SizedBox.shrink())),
      ),
    );
    await tester.pump();
    return tester.state(find.byType(WindowManager)) as WindowListener;
  }

  testWidgets('renders its child untouched', (tester) async {
    await pumpWindowManager(tester);

    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('a close request is delegated to the system action', (
    tester,
  ) async {
    final listener = await pumpWindowManager(tester);

    listener.onWindowClose();
    await tester.pumpAndSettle();

    expect(_RecordingSystemAction.calls, ['close']);
  });

  testWidgets('moving the window records its new position', (tester) async {
    final listener = await pumpWindowManager(tester);
    bounds = const Rect.fromLTWH(120, 64, 1000, 800);

    listener.onWindowMoved();
    await tester.pumpAndSettle();

    final setting = container.read(windowSettingProvider);
    expect(setting.left, 120);
    expect(setting.top, 64);
  });

  testWidgets('resizing the window records its new size', (tester) async {
    final listener = await pumpWindowManager(tester);
    bounds = const Rect.fromLTWH(0, 0, 1280, 960);

    listener.onWindowResized();
    await tester.pumpAndSettle();

    final setting = container.read(windowSettingProvider);
    expect(setting.width, 1280);
    expect(setting.height, 960);
  });

  testWidgets('minimize and restore survive without a visible window', (
    tester,
  ) async {
    final listener = await pumpWindowManager(tester);

    listener.onWindowMinimize();
    listener.onWindowRestore();
    listener.onWindowFocus();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a move that resolves after disposal is dropped', (tester) async {
    final listener = await pumpWindowManager(tester);
    bounds = const Rect.fromLTWH(500, 500, 640, 480);
    final gate = Completer<void>();
    boundsGate = gate;

    listener.onWindowMoved();
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(container.read(windowSettingProvider).left, isNot(500));
  });

  testWidgets('a resize that resolves after disposal is dropped', (
    tester,
  ) async {
    final listener = await pumpWindowManager(tester);
    bounds = const Rect.fromLTWH(0, 0, 640, 480);
    final gate = Completer<void>();
    boundsGate = gate;

    listener.onWindowResized();
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(container.read(windowSettingProvider).width, isNot(640));
  });

  group('WindowHeaderContainer', () {
    testWidgets('wraps its child', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: WindowHeaderContainer(child: Text('body')),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('body'), findsOneWidget);
    });
  });

  testWidgets('AppIcon renders the bundled application icon', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppIcon()));

    expect(find.byType(Image), findsOneWidget);
  });
}
