import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

class FolioColors {
  static const bgDeep = Color(0xFF0A0C10);
  static const bgPanel = Color(0xFF12151C);
  static const bgSoft = Color(0xFF1A1F2A);
  static const ink = Color(0xFFF2EFE8);
  static const inkMuted = Color(0xFF9A958C);
  static const inkFaint = Color(0xFF6A665F);
  static const copper = Color(0xFFD4A574);
  static const copperSoft = Color(0x2ED4A574);
  static const teal = Color(0xFF5FB3A8);
  static const line = Color(0x14F2EFE8);
  static const lineStrong = Color(0x29F2EFE8);
  static const danger = Color(0xFFE07A6B);
  static const scrim = Color(0xB804060A);
}

ThemeData folioTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: FolioColors.bgDeep,
    splashFactory: InkSparkle.splashFactory,
    // Zoom 默认会对下层做 snapshot，Ink 水波纹会被冻住，返回后才继续播完。
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(
          allowEnterRouteSnapshotting: false,
        ),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(
          allowEnterRouteSnapshotting: false,
        ),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(
          allowEnterRouteSnapshotting: false,
        ),
      },
    ),
    colorScheme: const ColorScheme.dark(
      surface: FolioColors.bgPanel,
      primary: FolioColors.copper,
      secondary: FolioColors.teal,
      error: FolioColors.danger,
      onSurface: FolioColors.ink,
      onPrimary: Color(0xFF1A1208),
    ),
  );
  final font = folioSystemFont();
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: FolioColors.ink,
      displayColor: FolioColors.ink,
      fontFamily: font,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: FolioColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xB312151C),
      hintStyle: const TextStyle(color: FolioColors.inkFaint),
      labelStyle: const TextStyle(color: FolioColors.inkMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: FolioColors.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: FolioColors.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: FolioColors.copper),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: FolioColors.bgSoft,
      contentTextStyle: TextStyle(color: FolioColors.ink, fontFamily: font),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: FolioColors.bgPanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

String? folioSystemFont() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
      return 'sans-serif';
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return 'CupertinoSystemText';
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return null;
  }
}

TextStyle folioDisplay({double size = 32, FontWeight weight = FontWeight.w700, Color? color}) {
  return TextStyle(
    fontFamily: folioSystemFont(),
    fontSize: size,
    fontWeight: weight,
    letterSpacing: -0.6,
    height: 1,
    color: color ?? FolioColors.ink,
  );
}
