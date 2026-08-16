import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray/tray.dart';

const MethodChannel _channel = MethodChannel('tray');
const StandardMethodCodec _codec = StandardMethodCodec();

TraySpec _spec({List<TrayMenuItem> menu = const []}) {
  return TraySpec(
    icon: const TrayIcon.asset('assets/icon.ico'),
    toolTip: 'FlClash',
    menu: menu,
  );
}

Future<void> _emit(String method, Object? arguments) {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _channel.name,
        _codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late bool showResult;

  int showCount() => calls.where((call) => call.method == 'show').length;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    calls = [];
    showResult = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return call.method == 'show' ? showResult : true;
        });
    Tray.instance.resetForTesting();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    Tray.instance.resetForTesting();
    debugDefaultTargetPlatformOverride = null;
  });

  test('a rejected show stays invisible and is retried', () async {
    showResult = false;
    await Tray.instance.show(_spec());

    expect(showCount(), 1);
    expect(Tray.instance.isVisible, isFalse);

    showResult = true;
    await Tray.instance.show(_spec());

    expect(showCount(), 2);
    expect(Tray.instance.isVisible, isTrue);
  });

  test(
    'an unchanged payload is suppressed only after an accepted show',
    () async {
      showResult = true;
      await Tray.instance.show(_spec());
      await Tray.instance.show(_spec());

      expect(showCount(), 1);

      showResult = false;
      await Tray.instance.show(_spec(menu: const [TrayMenuAction(label: 'a')]));
      await Tray.instance.show(_spec(menu: const [TrayMenuAction(label: 'a')]));

      expect(showCount(), 3);
    },
  );

  test('menu selection dispatches only for known integer ids', () async {
    var selected = 0;
    await Tray.instance.show(
      _spec(
        menu: [TrayMenuAction(label: 'a', onSelected: () => selected++)],
      ),
    );

    await _emit('onMenuItemSelected', <String, Object?>{'id': 1024});
    expect(selected, 1);

    await _emit('onMenuItemSelected', <String, Object?>{'id': 4096});
    await _emit('onMenuItemSelected', <String, Object?>{'id': '1024'});
    await _emit('onMenuItemSelected', null);
    expect(selected, 1);
  });
}
