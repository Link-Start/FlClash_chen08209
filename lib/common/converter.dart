import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_clash/enum/enum.dart';

import 'print.dart';

// Persisted state that fails to decode is replaced by defaults so the app still
// starts. Log it: a silent restore is indistinguishable from settings the user
// believes they never changed.
T decodeOrRestoreDefault<T>(
  String label,
  T Function() decode,
  T Function() restoreDefault,
) {
  try {
    return decode();
  } catch (error) {
    commonPrint.log(
      'Discarded damaged $label and restored defaults: ${compactError(error)}',
      logLevel: LogLevel.warning,
    );
    return restoreDefault();
  }
}

class Uint8ListToListIntConverter extends Converter<Uint8List, List<int>> {
  @override
  List<int> convert(Uint8List input) {
    return input.toList();
  }

  @override
  Sink<Uint8List> startChunkedConversion(Sink<List<int>> sink) {
    return _Uint8ListToListIntConverterSink(sink);
  }
}

class _Uint8ListToListIntConverterSink implements Sink<Uint8List> {
  const _Uint8ListToListIntConverterSink(this._target);

  final Sink<List<int>> _target;

  @override
  void add(Uint8List data) {
    _target.add(data.toList());
  }

  @override
  void close() {
    _target.close();
  }
}

final uint8ListToListIntConverter = Uint8ListToListIntConverter();
