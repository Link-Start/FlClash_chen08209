import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/plugins/tile.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingListener with TileListener {
  final calls = <String>[];

  @override
  void onStart() => calls.add('start');

  @override
  void onStop() => calls.add('stop');

  @override
  void onDetached() => calls.add('detached');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = '$packageName/tile';
  const codec = StandardMethodCodec();

  Future<void> emitFromPlatform(String method) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channelName,
          codec.encodeMethodCall(MethodCall(method)),
          null,
        );
  }

  test('routes every quick settings action to its listener callback', () async {
    final listener = _RecordingListener();
    Tile.instance.addListener(listener);
    addTearDown(() => Tile.instance.removeListener(listener));

    await emitFromPlatform('start');
    await emitFromPlatform('stop');
    await emitFromPlatform('detached');

    expect(listener.calls, ['start', 'stop', 'detached']);
  });

  test('delivers one action to every registered listener', () async {
    final first = _RecordingListener();
    final second = _RecordingListener();
    Tile.instance.addListener(first);
    Tile.instance.addListener(second);
    addTearDown(() {
      Tile.instance.removeListener(first);
      Tile.instance.removeListener(second);
    });

    await emitFromPlatform('start');

    expect(first.calls, ['start']);
    expect(second.calls, ['start']);
  });

  test('ignores an action it does not model', () async {
    final listener = _RecordingListener();
    Tile.instance.addListener(listener);
    addTearDown(() => Tile.instance.removeListener(listener));

    await emitFromPlatform('somethingElse');

    expect(listener.calls, isEmpty);
  });

  test('a removed listener stops receiving actions', () async {
    final listener = _RecordingListener();
    Tile.instance.addListener(listener);
    expect(Tile.instance.hasListeners, isTrue);

    Tile.instance.removeListener(listener);
    expect(Tile.instance.hasListeners, isFalse);
    await emitFromPlatform('start');

    expect(listener.calls, isEmpty);
  });
}
