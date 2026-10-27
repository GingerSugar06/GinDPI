import 'package:flutter/material.dart';

/// GinDPI paleti: koyu mürekkep zemin, "zencefil" vurgu, durum renkleri.
class P {
  static const bg = Color(0xFF0B0C11);
  static const side = Color(0xFF0F1117);
  static const panel = Color(0xFF151822);
  static const panelHi = Color(0xFF1B1F2C);
  static const line = Color(0xFF262B3A);
  static const text = Color(0xFFEEF0F6);
  static const muted = Color(0xFF8E95A9);
  static const faint = Color(0xFF5B6276);
  static const accent = Color(0xFFFF8A3D);
  static const accentSoft = Color(0xFFFFB873);
  static const ok = Color(0xFF3DDC97);
  static const warn = Color(0xFFFFC857);
  static const bad = Color(0xFFFF5C72);

  static Color status(String s) => switch (s) {
        'ok' => ok,
        'warn' => warn,
        'fail' => bad,
        _ => accent,
      };
}

const kFont = 'Segoe UI Variable Text';
const kFontFallback = ['Segoe UI', 'Arial'];

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: P.bg,
    colorScheme: const ColorScheme.dark(
      primary: P.accent,
      secondary: P.accentSoft,
      surface: P.panel,
      error: P.bad,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: kFont,
      fontFamilyFallback: kFontFallback,
      bodyColor: P.text,
      displayColor: P.text,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.white.withValues(alpha: 0.04),
    dividerColor: P.line,
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(P.line),
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(6),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: P.panelHi,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: P.line),
      ),
      textStyle: const TextStyle(color: P.text, fontSize: 12),
      waitDuration: const Duration(milliseconds: 400),
    ),
  );
}
