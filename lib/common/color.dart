import 'dart:math';

import 'package:flutter/material.dart';

extension ColorExtension on Color {
  Color get opacity80 {
    return withValues(alpha: 0.8);
  }

  Color get opacity60 {
    return withValues(alpha: 0.6);
  }

  Color get opacity50 {
    return withValues(alpha: 0.5);
  }

  Color get opacity38 {
    return withValues(alpha: 0.38);
  }

  Color get opacity30 {
    return withValues(alpha: 0.3);
  }

  Color get opacity12 {
    return withValues(alpha: 0.12);
  }

  Color get opacity15 {
    return withValues(alpha: 0.15);
  }

  Color get opacity10 {
    return withValues(alpha: 0.1);
  }

  Color get opacity3 {
    return withValues(alpha: 0.03);
  }

  Color get opacity0 {
    return withValues(alpha: 0);
  }

  int get value32bit {
    return _floatToInt8(a) << 24 |
        _floatToInt8(r) << 16 |
        _floatToInt8(g) << 8 |
        _floatToInt8(b) << 0;
  }

  int get alpha8bit => (0xff000000 & value32bit) >> 24;

  int get red8bit => (0x00ff0000 & value32bit) >> 16;

  int get green8bit => (0x0000ff00 & value32bit) >> 8;

  int get blue8bit => (0x000000ff & value32bit) >> 0;

  int _floatToInt8(double x) {
    return (x * 255.0).round() & 0xff;
  }

  Color lighten([double amount = 10]) {
    if (amount <= 0) return this;
    if (amount > 100) return Colors.white;
    final HSLColor hsl = this == const Color(0xFF000000)
        ? HSLColor.fromColor(this).withSaturation(0)
        : HSLColor.fromColor(this);
    return hsl
        .withLightness(min(1, max(0, hsl.lightness + amount / 100)))
        .toColor();
  }

  String get hex {
    final value = toARGB32();
    final red = (value >> 16) & 0xFF;
    final green = (value >> 8) & 0xFF;
    final blue = value & 0xFF;
    return '#${red.toRadixString(16).padLeft(2, '0')}'
            '${green.toRadixString(16).padLeft(2, '0')}'
            '${blue.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  Color darken([final int amount = 10]) {
    if (amount <= 0) return this;
    if (amount > 100) return Colors.black;
    final HSLColor hsl = HSLColor.fromColor(this);
    return hsl
        .withLightness(min(1, max(0, hsl.lightness - amount / 100)))
        .toColor();
  }

  Color blendDarken(BuildContext context, {double factor = 0.1}) {
    final brightness = Theme.of(context).brightness;
    return Color.lerp(
      this,
      brightness == Brightness.dark ? Colors.white : Colors.black,
      factor,
    )!;
  }
}

extension ColorSchemeExtension on ColorScheme {
  ColorScheme toPureBlack(bool isPrueBlack) => isPrueBlack
      ? copyWith(
          surface: Colors.black,
          surfaceContainer: surfaceContainer.darken(5),
        )
      : this;
}

Color? getDelayColor(int? delay) {
  if (delay == null) return null;
  if (delay < 0) return Colors.red;
  if (delay < 600) return Colors.green;
  return const Color(0xFFC57F0A);
}

const _indexPrimary = [50, 100, 200, 300, 400, 500, 600, 700, 800, 850, 900];

MaterialColor _createPrimarySwatch(Color color) {
  final Map<int, Color> swatch = <int, Color>{};
  final int a = color.alpha8bit;
  final int r = color.red8bit;
  final int g = color.green8bit;
  final int b = color.blue8bit;
  for (final int strength in _indexPrimary) {
    final double ds = 0.5 - strength / 1000;
    swatch[strength] = Color.fromARGB(
      a,
      r + ((ds < 0 ? r : (255 - r)) * ds).round(),
      g + ((ds < 0 ? g : (255 - g)) * ds).round(),
      b + ((ds < 0 ? b : (255 - b)) * ds).round(),
    );
  }
  swatch[50] = swatch[50]!.lighten(18);
  swatch[100] = swatch[100]!.lighten(16);
  swatch[200] = swatch[200]!.lighten(14);
  swatch[300] = swatch[300]!.lighten(10);
  swatch[400] = swatch[400]!.lighten(6);
  swatch[700] = swatch[700]!.darken(2);
  swatch[800] = swatch[800]!.darken(3);
  swatch[900] = swatch[900]!.darken(4);
  return MaterialColor(color.value32bit, swatch);
}

List<Color> getMaterialColorShades(Color color) {
  final swatch = _createPrimarySwatch(color);
  return <Color>[
    if (swatch[50] != null) swatch[50]!,
    if (swatch[100] != null) swatch[100]!,
    if (swatch[200] != null) swatch[200]!,
    if (swatch[300] != null) swatch[300]!,
    if (swatch[400] != null) swatch[400]!,
    if (swatch[500] != null) swatch[500]!,
    if (swatch[600] != null) swatch[600]!,
    if (swatch[700] != null) swatch[700]!,
    if (swatch[800] != null) swatch[800]!,
    if (swatch[850] != null) swatch[850]!,
    if (swatch[900] != null) swatch[900]!,
  ];
}
